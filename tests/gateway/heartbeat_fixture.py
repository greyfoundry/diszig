#!/usr/bin/env python3
"""Local Gateway heartbeat fixture.

The probe starts the session's background heartbeat thread and then only reads.
It never calls `tick`, so any heartbeat observed here proves the scheduler is
independent from the reading/handler loop. The server scripts Hello, ACKs,
dispatch sequences, an explicit heartbeat request and a missing-ACK zombie.
"""

from __future__ import annotations

import json
import pathlib
import socket
import struct
import subprocess
import sys
import time

from ws_support import frame, handshake, read_frame

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXE = ROOT / "zig-out" / "bin" / (
    "session_probe.exe" if sys.platform == "win32" else "session_probe"
)
ZIG = "zig"
ACK = b'{"op":11}'
DISPATCH = b'{"op":0,"t":"TEST","s":7,"d":{}}'
REQUEST = b'{"op":1}'


def hello(interval_ms: int) -> bytes:
    return json.dumps({"op": 10, "d": {"heartbeat_interval": interval_ms}}).encode()


def listen() -> socket.socket:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(10)
    return listener


def run_case(mode: str, interval_ms: int) -> tuple[list[str], dict]:
    failures: list[str] = []
    facts: dict = {"heartbeats": [], "close_code": None, "request_at": None}
    listener = listen()
    port = listener.getsockname()[1]
    process = subprocess.Popen(
        [str(EXE), mode, str(port)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        conn, _ = listener.accept()
        conn.settimeout(3)
        try:
            handshake(conn)
            conn.sendall(frame(1, hello(interval_ms)))
            deadline = time.monotonic() + 5.0
            dispatch_sent = False
            request_sent = False
            while time.monotonic() < deadline:
                try:
                    opcode, data = read_frame(conn)
                except (socket.timeout, ConnectionError):
                    break
                if opcode == 1:
                    try:
                        message = json.loads(data.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        failures.append(f"{mode}: invalid client payload {data!r}")
                        break
                    if message.get("op") != 1:
                        failures.append(f"{mode}: unexpected op {message.get('op')}")
                        continue
                    at = time.monotonic()
                    facts["heartbeats"].append((at, message.get("d")))
                    if mode == "ack":
                        conn.sendall(frame(1, ACK))
                        if len(facts["heartbeats"]) == 2 and not dispatch_sent:
                            conn.sendall(frame(1, DISPATCH))
                            dispatch_sent = True
                        if len(facts["heartbeats"]) == 3 and not request_sent:
                            conn.sendall(frame(1, REQUEST))
                            request_sent = True
                            facts["request_at"] = at
                    elif mode == "zombie":
                        if len(facts["heartbeats"]) == 1:
                            conn.sendall(frame(1, ACK))
                        # Withhold every later ACK.
                elif opcode == 8:
                    if len(data) >= 2:
                        facts["close_code"] = struct.unpack("!H", data[:2])[0]
                    break
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

    print(mode, process.returncode, repr((stdout + stderr).strip()), facts)
    if process.returncode != 0:
        failures.append(f"{mode}: exit {process.returncode}")

    heartbeats = facts["heartbeats"]
    if mode == "ack":
        if len(heartbeats) < 3:
            failures.append(f"{mode}: only {len(heartbeats)} heartbeats")
        if not any(sequence == 7 for _, sequence in heartbeats):
            failures.append(f"{mode}: no heartbeat carried the dispatch sequence 7")
        if facts["request_at"] is None:
            failures.append(f"{mode}: request was never sent")
        else:
            after = [at for at, _ in heartbeats if at > facts["request_at"]]
            if not after or after[0] - facts["request_at"] > 0.6:
                failures.append(f"{mode}: heartbeat request was not answered promptly")
        if "zombie" in stdout:
            failures.append(f"{mode}: unexpected zombie")
    else:
        if len(heartbeats) < 2:
            failures.append(f"{mode}: only {len(heartbeats)} heartbeats")
        if facts["close_code"] != 4000:
            failures.append(f"{mode}: close code {facts['close_code']} (want 4000)")
        if "zombie" not in stdout:
            failures.append(f"{mode}: probe did not report zombie")
    return failures


def main() -> int:
    subprocess.run(
        [ZIG, "build", "session-probe"], cwd=ROOT, check=True, capture_output=True
    )
    failures = run_case("ack", 1000)
    failures += run_case("zombie", 200)
    if failures:
        print("FAIL:", "; ".join(failures))
        return 1
    print("PASS: Gateway heartbeat fixture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
