#!/usr/bin/env python3
"""Add one release <item> to a Sparkle appcast (RSS 2.0); create the file when it is missing.

  appcast_add_item.py --self-test
  appcast_add_item.py --appcast appcast.xml --version 0.2.0 --check-newer
  appcast_add_item.py --appcast appcast.xml --version 0.2.0 --build 20261005.101500 \
      --url https://.../Tessera-0.2.0.zip --length 1234 --signature <edSignature> \
      --notes-file notes.md [--channel beta] [--min-system 15.0]

Release notes are embedded as Markdown: <description sparkle:format="markdown"> (Sparkle 2.9+, macOS 12+).
The new item goes first (newest first). Adding also requires --version to be newer than every
sparkle:shortVersionString already in the feed, using SemVer precedence. Standard library only.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NS)

SKELETON = (
    f'<rss version="2.0" xmlns:sparkle="{NS}"><channel><title>Tessera</title></channel></rss>'
)

# SemVer 2.0.0 without build metadata: X.Y.Z or X.Y.Z-pre.release (numeric identifiers have no leading zero).
_ID = r"(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = re.compile(rf"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-({_ID}(?:\.{_ID})*))?$")


def sp(name):
    """Clark-notation tag/attribute name in the sparkle namespace."""
    return f"{{{NS}}}{name}"


def semver_key(version):
    """Sort key implementing SemVer precedence: 0.2.0-beta.1 < 0.2.0-beta.2 < 0.2.0 < 0.2.1."""
    m = SEMVER.match(version)
    if not m:
        raise ValueError(f"'{version}' is not SemVer (expected X.Y.Z or X.Y.Z-beta.N)")
    core = tuple(int(g) for g in m.groups()[:3])
    if m.group(4) is None:
        return core, 1, ()  # a release outranks every pre-release of the same core
    # Numeric identifiers sort numerically and below alphanumeric ones; a shorter prefix sorts first.
    pre = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in m.group(4).split("."))
    return core, 0, pre


def load(path):
    p = Path(path)
    return ET.fromstring(p.read_text(encoding="utf-8") if p.exists() else SKELETON)


def check_newer(root, version):
    key = semver_key(version)
    for el in root.iterfind(f".//{sp('shortVersionString')}"):
        existing = (el.text or "").strip()
        if semver_key(existing) >= key:
            raise ValueError(f"version {version} is not newer than {existing}, already in the appcast")


def build_item(a):
    item = ET.Element("item")

    def add(tag, text, **attrib):
        el = ET.SubElement(item, tag, attrib)
        el.text = text

    add("title", f"Tessera {a.version}")
    add("pubDate", format_datetime(datetime.now(timezone.utc)))
    add(sp("version"), a.build)
    add(sp("shortVersionString"), a.version)
    if a.channel:
        add(sp("channel"), a.channel)
    if a.min_system:
        add(sp("minimumSystemVersion"), a.min_system)
    add("description", Path(a.notes_file).read_text(encoding="utf-8").strip(), **{sp("format"): "markdown"})
    ET.SubElement(item, "enclosure", {
        "url": a.url,
        "length": str(a.length),
        "type": "application/octet-stream",
        sp("edSignature"): a.signature,
    })
    return item


def self_test():
    order = ["0.1.0", "0.2.0-alpha", "0.2.0-beta.1", "0.2.0-beta.2", "0.2.0-beta.10", "0.2.0-rc.1",
             "0.2.0", "0.2.1", "0.10.0", "1.0.0"]
    keys = [semver_key(v) for v in order]
    assert keys == sorted(keys) and len(set(keys)) == len(keys), "SemVer ordering is wrong"
    for bad in ("", "1.2", "v1.0.0", "01.0.0", "1.0.0-", "1.0.0-beta.01", "1.0.0+build"):
        try:
            semver_key(bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted invalid version {bad!r}")
    print("ok")


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--appcast", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--check-newer", action="store_true", help="only validate --version; change nothing")
    ap.add_argument("--build")
    ap.add_argument("--url")
    ap.add_argument("--length", type=int)
    ap.add_argument("--signature")
    ap.add_argument("--notes-file")
    ap.add_argument("--channel")
    ap.add_argument("--min-system")
    a = ap.parse_args()

    if not a.check_newer:
        missing = [f"--{n}" for n in ("build", "url", "length", "signature", "notes-file")
                   if getattr(a, n.replace("-", "_")) is None]
        if missing:
            ap.error(f"required to add an item: {', '.join(missing)}")

    try:
        root = load(a.appcast)
        check_newer(root, a.version)
        if a.check_newer:
            return
        channel = root.find("channel")
        if channel is None:
            raise ValueError(f"{a.appcast} has no <channel>")
        # Newest first: insert before the first existing item, or at the end of an empty channel.
        first = next((i for i, c in enumerate(channel) if c.tag == "item"), len(channel))
        channel.insert(first, build_item(a))
    except (ValueError, OSError, ET.ParseError) as e:
        sys.exit(f"error: {e}")

    ET.indent(root, space="    ")
    xml = ET.tostring(root, encoding="unicode")
    Path(a.appcast).write_text(f'<?xml version="1.0" encoding="utf-8"?>\n{xml}\n', encoding="utf-8")


if __name__ == "__main__":
    main()
