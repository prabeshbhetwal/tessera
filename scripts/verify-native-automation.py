#!/usr/bin/env python3
"""Real app/CLI settings and permission-boundary smoke on a disposable GitHub runner."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("CI") != "true":
    raise SystemExit("Run only on an isolated GitHub macOS runner; never against personal app state.")
app = Path(sys.argv[1]).resolve()
cli = app / "Contents/Helpers/tessera"
support = Path.home() / "Library/Application Support/Tessera"
if support.exists():
    raise SystemExit("Refusing to use existing Tessera app data.")
fixture = Path(tempfile.mkdtemp(prefix="tessera-native-fixture-", dir=os.environ["RUNNER_TEMP"]))

def request(*arguments, expected=0):
    result = subprocess.run([str(cli), *arguments, "--json"], text=True, capture_output=True, timeout=10)
    assert result.returncode == expected, (arguments, result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout)

def write(name, data):
    path = fixture / name
    with path.open("x") as output:
        json.dump(data, output)
    return path

def export(name):
    path = fixture / name
    assert request("settings", "export", str(path))["ok"]
    return json.loads(path.read_text())

with (fixture / "app.log").open("x") as log:
    process = subprocess.Popen([str(app / "Contents/MacOS/Tessera")], stdout=log, stderr=subprocess.STDOUT)
    try:
        ready = None
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            assert process.poll() is None, "Fixture app exited; see app.log"
            try:
                result = subprocess.run([str(cli), "displays", "--json"], text=True, capture_output=True, timeout=2)
                if result.returncode == 0:
                    ready = json.loads(result.stdout)
                    break
            except subprocess.TimeoutExpired:
                pass
            time.sleep(0.25)
        assert ready and ready["ok"] and isinstance(ready["displays"], list), "App/CLI bridge did not become ready"
        print("PASS: Real app startup and CLI → socket → CommandBridge → executor display query")

        result = subprocess.run([str(cli), "window", "--json"], text=True, capture_output=True, timeout=10)
        response = json.loads(result.stdout)
        if result.returncode == 0:
            assert response["ok"] is True and isinstance(response.get("window"), dict), response
            window = response["window"]
            assert isinstance(window.get("app"), str) and window["app"], window
            if window.get("bundleID") is not None:
                assert isinstance(window["bundleID"], str) and window["bundleID"], window
            origin, size = window["frame"]
            assert len(origin) == len(size) == 2
            assert all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in origin + size)
            assert all(v > 0 for v in size), window
            if window.get("displayIndex") is not None:
                assert type(window["displayIndex"]) is int and 1 <= window["displayIndex"] <= len(ready["displays"])
            print("PASS: Existing Accessibility authorisation; real read-only window query validates frame/display contract")
        else:
            assert result.returncode == 1 and response["ok"] is False and "Accessibility" in response["message"], response
            print("PASS: Accessibility denial contract; no permission grant requested")

        original = export("original.json")
        edited = dict(original, hudSeconds=2.0)
        assert request("settings", "import", str(write("edited.json", edited)))["ok"]
        assert export("after-import.json") == edited
        invalid = dict(edited, schemaVersion=999)
        rejected = request("settings", "import", str(write("invalid.json", invalid)), expected=1)
        assert not rejected["ok"]
        assert export("after-rejection.json") == edited
        deadline = time.monotonic() + 3
        saved = support / "settings.json"
        while time.monotonic() < deadline:
            if saved.exists() and json.loads(saved.read_text()) == edited:
                break
            time.sleep(0.1)
        assert saved.exists() and json.loads(saved.read_text()) == edited
        print("PASS: Real settings export/import, invalid-import recovery and atomic persistence on fixture data")

    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
