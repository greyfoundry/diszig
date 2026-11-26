#!/usr/bin/env python3
"""Local REST transport checks: auth, same-origin redirects, cross-origin refusal, 204."""

import http.server
import pathlib
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXE = ROOT / "zig-out" / "bin" / "transport_probe.exe"
ZIG = "zig"

records = {}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def _send(self, status, body=b"", location=None):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        if location:
            self.send_header("Location", location)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        port = self.server.server_address[1]
        records.setdefault(port, []).append((self.path, self.headers.get("Authorization")))
        if self.path == "/ok":
            self._send(200, b"ok")
        elif self.path == "/redirect":
            self._send(302, location=f"http://127.0.0.1:{records['p1']}/ok")
        elif self.path == "/cross":
            self._send(302, location=f"http://127.0.0.1:{records['p2']}/leak")
        elif self.path == "/empty":
            self._send(204)
        elif self.path == "/leak":
            self._send(200, b"leaked")
        else:
            self._send(404, b"missing")


def start():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, server.server_address[1], thread


def run(mode, port):
    result = subprocess.run(
        [str(EXE), mode, str(port)], text=True, capture_output=True, timeout=20
    )
    print(mode, result.returncode, (result.stdout + result.stderr).strip())
    return result


def main():
    subprocess.run([ZIG, "build", "transport-probe"], cwd=ROOT, check=True, capture_output=True)
    server1, p1, t1 = start()
    server2, p2, t2 = start()
    records["p1"] = p1
    records["p2"] = p2
    failures = []
    try:
        records[p1] = []
        result = run("get", p1)
        if result.returncode != 0 or "status=200 body=ok" not in result.stdout:
            failures.append("get")
        if records[p1] != [("/ok", "Bearer abc")]:
            failures.append("get-auth")

        records[p1] = []
        result = run("redirect", p1)
        if result.returncode != 0 or "status=200 body=ok" not in result.stdout:
            failures.append("redirect")
        if [item[1] for item in records[p1]] != ["Bearer abc", "Bearer abc"]:
            failures.append("redirect-auth")

        records[p1] = []
        records[p2] = []
        result = run("cross", p1)
        if result.returncode != 0 or "error=CrossOriginRedirect" not in result.stdout:
            failures.append("cross")
        if records[p2]:
            failures.append("cross-origin-leak")

        records[p1] = []
        result = run("empty", p1)
        if result.returncode != 0 or "status=204 len=0" not in result.stdout:
            failures.append("empty")
    finally:
        for server, thread in ((server1, t1), (server2, t2)):
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    if failures:
        print("FAIL:", ", ".join(failures))
        return 1
    print("PASS: REST transport fixture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
