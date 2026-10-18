"""Launch the packaged release app and require its editor to become visible.

Run on a macOS GUI session: python3 scripts/smoke_macos.py 'dist/Cappella Mac.app'
An Open panel or a process that crashes during layout must not count as success.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def smoke(app, timeout):
    if sys.platform != "darwin":
        raise RuntimeError("This test requires a macOS GUI session.")
    binary = app.resolve() / "Contents" / "MacOS" / "CappellaMac"
    if not binary.is_file():
        raise RuntimeError(f"Application executable missing: {binary}")
    with tempfile.TemporaryDirectory(prefix="cappella-smoke-") as directory:
        marker = Path(directory) / "editor-ready.txt"
        log = Path(directory) / "launch.log"
        environment = os.environ.copy()
        environment["CAPPELLA_SMOKE_TEST_MARKER"] = str(marker)
        problem = None
        with log.open("wb") as output:
            process = subprocess.Popen([str(binary)], cwd=directory, env=environment,
                                       stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + timeout
                while not marker.exists():
                    if process.poll() is not None:
                        raise RuntimeError(f"App exited before showing its editor (status {process.returncode}).")
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Editor did not appear before the timeout (possibly an Open/error panel).")
                    time.sleep(0.2)
                if marker.read_text(encoding="utf-8") != "editor-visible\n":
                    raise RuntimeError("Unexpected readiness marker.")
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    pass  # Expected: app remains alive after initial layout.
                else:
                    raise RuntimeError(f"App exited just after showing its editor (status {process.returncode}).")
            except Exception as error:
                problem = error
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        if problem is not None:
            print(log.read_text(encoding="utf-8", errors="replace")[-16000:], file=sys.stderr)
            raise problem
    print("PASS: packaged release app displayed its editor and stayed alive.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 120:
        parser.error("timeout must be between 1 and 120 seconds")
    try:
        smoke(args.app, args.timeout)
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
