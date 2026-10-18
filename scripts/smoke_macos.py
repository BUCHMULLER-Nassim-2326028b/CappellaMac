"""Launch the packaged app and require a visible editor, optionally with a DetX.

Run on a macOS GUI session. Optional screenshots help compare the native layout.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def smoke(app, timeout, fixture=None, screenshot=None):
    if sys.platform != "darwin":
        raise RuntimeError("This test requires a macOS GUI session.")
    binary = app.resolve() / "Contents" / "MacOS" / "CappellaMac"
    if not binary.is_file():
        raise RuntimeError(f"Application executable missing: {binary}")
    if fixture is not None and not fixture.is_file():
        raise RuntimeError(f"Fixture missing: {fixture}")
    with tempfile.TemporaryDirectory(prefix="cappella-smoke-") as directory:
        marker = Path(directory) / "editor-ready.txt"
        log = Path(directory) / "launch.log"
        environment = os.environ.copy()
        environment.pop("CAPPELLA_SMOKE_TEST_FIXTURE", None)
        environment["CAPPELLA_SMOKE_TEST_MARKER"] = str(marker)
        if fixture is not None:
            environment["CAPPELLA_SMOKE_TEST_FIXTURE"] = str(fixture.resolve())
        problem = None
        with log.open("wb") as output:
            process = subprocess.Popen([str(binary)], cwd=directory, env=environment,
                                       stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + timeout
                while True:
                    if process.poll() is not None:
                        raise RuntimeError(f"App exited before showing its editor (status {process.returncode}).")
                    if marker.exists():
                        contents = marker.read_text(encoding="utf-8").strip()
                        if contents.startswith("editor-visible:"):
                            count = int(contents.split(":", 1)[1])
                            if fixture is None or count > 0:
                                break
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Expected editor did not appear (possibly an Open/error panel).")
                    time.sleep(0.2)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    pass
                else:
                    raise RuntimeError(f"App exited just after showing its editor (status {process.returncode}).")
                if screenshot is not None:
                    screenshot = screenshot.resolve()
                    screenshot.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        subprocess.run(["/usr/sbin/screencapture", "-x", str(screenshot)], check=True, timeout=8)
                    except (subprocess.SubprocessError, OSError) as error:
                        # Screen Recording permission is independent of app startup.
                        print(f"Preview unavailable: {error}", file=sys.stderr)
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
    print(f"PASS: packaged release app displayed its editor ({count} phrases) and stayed alive.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 120:
        parser.error("timeout must be between 1 and 120 seconds")
    try:
        smoke(args.app, args.timeout, args.fixture, args.screenshot)
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
