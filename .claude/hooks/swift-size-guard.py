#!/usr/bin/env python3
"""PostToolUse nudge: AGENTS.md keeps Swift files below 300 lines and says not to grow oversized ones.

Flags a .swift file at or over the limit only when the edit left it longer than its HEAD version,
so untouched oversized files and edits that shrink them stay quiet.
"""
import json
import os
import subprocess
import sys

LIMIT = 300


def head_lines(path):
    """Line count of the committed version, 0 for a new file."""
    shown = subprocess.run(
        ["git", "-C", os.path.dirname(path), "show", f"HEAD:./{os.path.basename(path)}"],
        capture_output=True, text=True, errors="replace",
    )
    return len(shown.stdout.splitlines()) if shown.returncode == 0 else 0


def main():
    payload = json.load(sys.stdin)
    path = (payload.get("tool_input") or {}).get("file_path", "")
    if not path.endswith(".swift") or not os.path.isfile(path):
        return 0
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = len(f.read().splitlines())
    before = head_lines(path)
    if lines >= LIMIT and lines > before:
        was = f"{before} at HEAD" if before else "new file"
        print(
            f"{os.path.basename(path)} is now {lines} lines ({was}). AGENTS.md keeps Swift files below "
            f"{LIMIT} lines and says not to grow oversized ones: move the new code into a focused sibling file.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
