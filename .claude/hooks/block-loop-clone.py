#!/usr/bin/env python3
"""PreToolUse guard: keeps Claude out of loop/, the upstream Loop (GPL-3.0) clone in the main checkout.

Tessera is a clean-room implementation: docs/loop-*.md hold the behaviour notes, the source stays unread.
A deliberate research session starts Claude with TESSERA_LOOP_RESEARCH=1.
Self-check: python3 .claude/hooks/block-loop-clone.py --self-test
"""
import json
import os
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MESSAGE = (
    "Blocked: loop/ is the upstream Loop source (GPL-3.0) and Tessera is clean-room. "
    "Use docs/loop-*.md for behaviour, never the source. A search rooted above loop/ also reaches it: "
    "point it at a subfolder. (A deliberate research session needs the user to start Claude with "
    "TESSERA_LOOP_RESEARCH=1.)"
)


def main_checkout(directory):
    """Root of the main checkout, which every worktree shares through its .git, or None outside git."""
    try:
        out = subprocess.run(
            ["git", "-C", directory, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return os.path.dirname(out) if out else None


def norm(path, base):
    # APFS is case-insensitive by default, so compare case-folded real paths.
    return os.path.realpath(os.path.join(base, os.path.expanduser(path))).casefold()


def touches(payload, loop, main):
    tool = payload.get("tool_name")
    args = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()
    loop = os.path.realpath(loop).casefold()

    def inside(path):
        return path == loop or path.startswith(loop + os.sep)

    if tool == "Read":
        return inside(norm(args.get("file_path", ""), cwd))
    if tool in ("Grep", "Glob"):
        root = norm(args.get("path") or cwd, cwd)
        if inside(root) or loop.startswith(root.rstrip(os.sep) + os.sep):
            return True
        pattern = args.get("pattern" if tool == "Glob" else "glob")
        return bool(pattern) and inside(norm(pattern, root))
    if tool == "Bash":
        command = args.get("command", "")
        try:
            tokens = shlex.split(command)
        except ValueError:
            tokens = command.split()
        # ponytail: path-shaped tokens only (a slash, or a cd target); a bare `rg x loop` run from the
        # main checkout slips through. Add sandbox.filesystem.denyRead if that ever matters.
        previous = ""
        for token in tokens:
            value = token.split("=", 1)[1] if token.startswith("-") and "=" in token else token
            if "/" in value or previous in ("cd", "pushd"):
                if inside(norm(value, cwd)) or inside(norm(value, main)):
                    return True
            previous = token
    return False


def self_test():
    main = main_checkout(HERE)
    assert main, "not inside a git checkout"
    loop = os.path.join(main, "loop")
    worktree = os.path.dirname(os.path.dirname(HERE))

    def check(expected, tool, cwd=worktree, **args):
        got = touches({"tool_name": tool, "tool_input": args, "cwd": cwd}, loop, main)
        assert got == expected, f"{tool} {args} from {cwd}: expected {expected}, got {got}"

    check(True, "Read", file_path=os.path.join(loop, "Loop", "App.swift"))
    check(True, "Read", file_path=os.path.join(main, "LOOP", "README.md"))
    check(False, "Read", file_path=os.path.join(worktree, "AGENTS.md"))
    check(True, "Glob", path=main, pattern="loop/**/*.swift")
    check(True, "Grep", path=main, pattern="func")
    check(False, "Grep", path=os.path.join(worktree, "Tessera"), pattern="func")
    check(True, "Bash", command=f"cat '{loop}/README.md'")
    check(True, "Bash", command="sed -n 1,40p loop/Loop/App.swift")
    check(True, "Bash", cwd=main, command="cd loop && ls")
    check(False, "Bash", cwd=main, command="grep -rn loop Tessera")
    check(False, "Bash", command='git commit -m "fix run loop/timer"')
    check(False, "Bash", command="cat docs/loop-technical-mechanics.md")
    print("block-loop-clone: self-test passed")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return 0
    if os.environ.get("TESSERA_LOOP_RESEARCH") == "1":
        return 0
    payload = json.load(sys.stdin)
    main_root = main_checkout(HERE)
    if main_root and touches(payload, os.path.join(main_root, "loop"), main_root):
        print(MESSAGE, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
