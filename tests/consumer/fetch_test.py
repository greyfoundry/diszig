#!/usr/bin/env python3
"""Fetch the package as an archive and build a fresh external consumer.

This exercises the real Zig package fetch and hash check without using a path
dependency. No repository-relative imports are available to the consumer.
"""
from __future__ import annotations

import functools
import http.server
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ZIG = shutil.which("zig") or r"C:\Users\User\Tools\zig\0.17.1\zig.exe"

sys.path.insert(0, str(ROOT / "tools"))
from check_package import collect_from_paths, read_paths  # noqa: E402


def make_archive(dest: pathlib.Path) -> pathlib.Path:
    paths = read_paths(ROOT / "build.zig.zon")
    names = collect_from_paths(ROOT, paths)
    archive = dest / "diszig.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for name in names:
            tar.add(ROOT / name, arcname=f"diszig/{name}")
    return archive


def serve(directory: pathlib.Path):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, server.server_address[1], thread


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        archive = make_archive(work)
        server, port, thread = serve(work)
        try:
            url = f"http://127.0.0.1:{port}/{archive.name}"

            consumer = work / "consumer"
            shutil.copytree(HERE / "src", consumer / "src")
            shutil.copy2(HERE / "build.zig", consumer / "build.zig")
            zon = """.{
    .name = .diszig_consumer,
    .version = "0.0.0",
    .fingerprint = 0x5469fb8cf749a056,
    .minimum_zig_version = "0.17.1",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
"""
            (consumer / "build.zig.zon").write_text(zon, encoding="utf-8")

            fetched = subprocess.run(
                [ZIG, "fetch", "--save=diszig", url],
                cwd=consumer, text=True, capture_output=True,
            )
            print("fetch --save stdout:", fetched.stdout.strip())
            print("fetch --save stderr:", fetched.stderr.strip())
            if fetched.returncode != 0:
                print("FAIL: package fetch failed")
                return 1
            print("consumer zon:\n" + (consumer / "build.zig.zon").read_text(encoding="utf-8"))

            built = subprocess.run(
                [ZIG, "build", "run"], cwd=consumer, text=True, capture_output=True
            )
            print("consumer stdout:", built.stdout.strip())
            print("consumer stderr:", built.stderr.strip())
            if built.returncode != 0 or "18446744073709551615 5818116911103" not in built.stdout:
                print("FAIL: external archive consumer")
                return 1

            saved = (consumer / "build.zig.zon").read_text(encoding="utf-8")
            hash_line = next(line for line in saved.splitlines() if ".hash =" in line)
            hash_value = hash_line.split('"')[1]
            name, version, _ = hash_value.split("-", 2)
            digest_start = len(name) + 1 + len(version) + 1
            index = digest_start + 4
            replacement = "A" if hash_value[index] != "A" else "B"
            tampered_value = hash_value[:index] + replacement + hash_value[index + 1 :]
            (consumer / "build.zig.zon").write_text(
                saved.replace(hash_value, tampered_value), encoding="utf-8"
            )
            bad = subprocess.run(
                [ZIG, "build", "--fetch"], cwd=consumer, text=True, capture_output=True
            )
            if bad.returncode == 0 or "hash mismatch" not in (bad.stdout + bad.stderr):
                print("FAIL: wrong archive hash was not rejected")
                return 1
            print("wrong hash rejected")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    print("PASS: external archive consumer")
    return 0


if __name__ == "__main__":
    sys.exit(main())
