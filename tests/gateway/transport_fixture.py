#!/usr/bin/env python3
"""Raw RFC 6455 server used to exercise Diszig's Gateway transport.

No third-party WebSocket library is used: the handshake and frames are written
directly so the fixture controls TCP coalescing, fragmentation, control frames,
partial frames and compressed payloads exactly. No Discord connection is made.
"""

from __future__ import annotations

import base64
import hashlib
import pathlib
import socket
import struct
import subprocess
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXE = ROOT / "zig-out" / "bin" / (
    "gateway_probe.exe" if sys.platform == "win32" else "gateway_probe"
)
ZIG = "zig"
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
SUFFIX = b"\x00\x00\xff\xff"


def recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def recv_until(conn: socket.socket, marker: bytes) -> bytes:
    buf = b""
    while marker not in buf:
        chunk = conn.recv(4096)
        if not chunk:
            raise ConnectionError("closed during handshake")
        buf += chunk
    return buf


def handshake(conn: socket.socket) -> None:
    request = recv_until(conn, b"\r\n\r\n")
    key = None
    for line in request.split(b"\r\n"):
        if line.lower().startswith(b"sec-websocket-key:"):
            key = line.split(b":", 1)[1].strip()
    if key is None:
        raise ValueError("missing Sec-WebSocket-Key")
    accept = base64.b64encode(hashlib.sha1(key + GUID.encode()).digest())
    conn.sendall(
        b"HTTP/1.1 101 Switching Protocols\r\n"
        b"Upgrade: websocket\r\n"
        b"Connection: Upgrade\r\n"
        b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n"
    )


def frame(opcode: int, payload: bytes, fin: bool = True) -> bytes:
    first = (0x80 if fin else 0x00) | opcode
    length = len(payload)
    if length < 126:
        header = struct.pack("!BB", first, length)
    elif length < 65536:
        header = struct.pack("!BBH", first, 126, length)
    else:
        header = struct.pack("!BBQ", first, 127, length)
    return header + payload


def read_frame(conn: socket.socket) -> tuple[int, bytes]:
    first, second = recv_exact(conn, 2)
    opcode = first & 0x0F
    masked = bool(second & 0x80)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(conn, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(conn, 8))[0]
    mask = recv_exact(conn, 4) if masked else b""
    data = recv_exact(conn, length)
    if masked:
        data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
    return opcode, data


def compress_two() -> tuple[bytes, bytes]:
    compression = zlib.compressobj(6, zlib.DEFLATED, 15)
    first = compression.compress(b'{"op":10,"d":{}}') + compression.flush(zlib.Z_SYNC_FLUSH)
    second = compression.compress(b'{"op":0,"t":"READY"}') + compression.flush(zlib.Z_SYNC_FLUSH)
    assert first.endswith(SUFFIX) and second.endswith(SUFFIX)
    return first, second


def serve(conn: socket.socket, mode: str) -> list[str]:
    notes: list[str] = []
    handshake(conn)
    if mode == "coalesced":
        # Two complete frames delivered in one TCP write.
        conn.sendall(frame(1, b"first") + frame(1, b"second"))
        notes.append("sent-two-frames-one-write")
    elif mode == "fragmented":
        conn.sendall(frame(1, b'{"op":10', fin=False))
        conn.sendall(frame(9, b"hb"))  # ping between fragments
        conn.sendall(frame(0, b',"d":{}}', fin=True))
        opcode, data = read_frame(conn)
        notes.append(f"control:{opcode}:{data.decode('ascii', 'replace')}")
    elif mode == "partial":
        # First three bytes of a 126-length text frame, then hang up.
        conn.sendall(b"\x81\x7e\x00")
        notes.append("sent-partial")
    elif mode == "compressed":
        first, second = compress_two()
        conn.sendall(frame(1, first))
        conn.sendall(frame(1, second))
        notes.append("sent-compressed-two")
    elif mode == "bomb":
        compression = zlib.compressobj(9, zlib.DEFLATED, 15)
        payload = compression.compress(b"A" * (64 * 1024)) + compression.flush(zlib.Z_SYNC_FLUSH)
        conn.sendall(frame(1, payload))
        notes.append("sent-bomb")
    elif mode == "server-close":
        conn.sendall(frame(8, struct.pack("!H", 1000) + b"bye"))
        notes.append("sent-close")
    else:
        raise ValueError(f"unknown mode: {mode}")
    return notes


def run_case(mode: str, bound: int, expected: list[str], expect_pong: bool = False) -> list[str]:
    failures: list[str] = []
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    process = subprocess.Popen(
        [str(EXE), mode, str(port), str(bound)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    notes: list[str] = []
    try:
        conn, _ = listener.accept()
        conn.settimeout(10)
        try:
            notes = serve(conn, mode)
            if mode in ("coalesced", "compressed"):
                # Let the client consume; it closes after enough messages.
                try:
                    while conn.recv(4096):
                        pass
                except (ConnectionError, socket.timeout):
                    pass
        finally:
            conn.close()
    finally:
        listener.close()

    try:
        stdout, stderr = process.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
        failures.append(f"{mode}: probe hung")
        stdout = stdout or ""

    print(mode, process.returncode, repr((stdout + stderr).strip()), notes)
    for fragment in expected:
        if fragment not in stdout:
            failures.append(f"{mode}: missing {fragment!r} in {stdout!r}")
    if process.returncode != 0:
        failures.append(f"{mode}: exit {process.returncode}")
    if expect_pong and not any(note.startswith("control:10:hb") for note in notes):
        failures.append(f"{mode}: no masked pong")
    return failures


def main() -> int:
    subprocess.run(
        [ZIG, "build", "gateway-probe"], cwd=ROOT, check=True, capture_output=True
    )
    failures: list[str] = []
    failures += run_case("coalesced", 65536, ["msg:first", "msg:second"])
    failures += run_case("fragmented", 65536, ['msg:{"op":10,"d":{}}'], expect_pong=True)
    failures += run_case("partial", 65536, ["error:"])
    failures += run_case(
        "compressed", 65536, ['msg:{"op":10,"d":{}}', 'msg:{"op":0,"t":"READY"}']
    )
    failures += run_case("bomb", 1024, ["error:MessageTooLarge"])
    failures += run_case("server-close", 65536, ["close:1000"])

    if failures:
        print("FAIL:", "; ".join(failures))
        return 1
    print("PASS: Gateway transport fixture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
