#!/usr/bin/env python3
"""Raw RFC 6455 server used to exercise Diszig's Gateway transport.

No third-party WebSocket library is used: the handshake and frames are written
directly so the fixture controls TCP coalescing, fragmentation, control frames,
partial frames and compressed payloads exactly. No Discord connection is made.
"""

from __future__ import annotations

import pathlib
import socket
import struct
import subprocess
import sys
import zlib

from ws_support import SUFFIX, frame, handshake, read_frame

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXE = ROOT / "zig-out" / "bin" / (
    "gateway_probe.exe" if sys.platform == "win32" else "gateway_probe"
)
ZIG = "zig"


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
