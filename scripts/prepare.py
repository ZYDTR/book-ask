#!/usr/bin/env python3
"""Build a local EPUB context index and point at existing credentials; never copy keys."""
import argparse
import html.parser
import json
import os
import re
import sys
import urllib.request
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


class Paragraphs(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.items = []
        self.buffer = []
        self.skip = 0

    def flush(self):
        text = re.sub(r"\s+", " ", "".join(self.buffer)).strip()
        if text:
            self.items.append(text)
        self.buffer = []

    def handle_starttag(self, tag, attrs):
        if tag in ("aside", "script", "style"):
            self.skip += 1
        if not self.skip and tag in ("p", "h1", "h2", "h3", "li", "blockquote"):
            self.flush()
        if tag == "br" and not self.skip:
            self.buffer.append(" ")

    def handle_endtag(self, tag):
        if tag in ("aside", "script", "style"):
            self.skip = max(0, self.skip - 1)
        elif not self.skip and tag in ("p", "h1", "h2", "h3", "li", "blockquote"):
            self.flush()

    def handle_data(self, data):
        if not self.skip:
            self.buffer.append(data)


def extract(epub):
    paragraphs = []
    with zipfile.ZipFile(epub) as z:
        root = ET.fromstring(z.read("META-INF/container.xml"))
        opf = next(x.attrib["full-path"] for x in root.iter() if x.tag.endswith("rootfile"))
        package = ET.fromstring(z.read(opf))
        manifest = {x.attrib["id"]: x.attrib.get("href", "") for x in package.iter() if x.tag.endswith("}item")}
        for item in package.iter():
            if not item.tag.endswith("}itemref"):
                continue
            filename = str(Path(opf).parent / manifest[item.attrib["idref"]])
            if filename not in z.namelist():
                # Some already annotated EPUBs retain stale front-matter spine entries.
                print(f"EPUB missing spine entry (not indexed): {filename}", file=sys.stderr)
                continue
            parser = Paragraphs()
            parser.feed(z.read(filename).decode("utf-8"))
            parser.flush()
            for i, text in enumerate(parser.items):
                paragraphs.append({"id": f"{filename}#{i}", "chapter": filename, "text": text})
    return paragraphs


def write_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
    path.chmod(0o600)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--epub", required=True, type=Path)
    p.add_argument("--opencode-config", required=True, type=Path)
    p.add_argument("--auth-file", required=True, type=Path)
    args = p.parse_args()
    provider = json.loads(args.opencode_config.read_text())["provider"]["litellm"]
    base = provider["options"]["baseURL"].rstrip("/")
    key = json.loads(args.auth_file.read_text())["litellm"]["key"]
    req = urllib.request.Request(base + "/models", headers={"Authorization": "Bearer " + key})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=20) as response:
        names = [x["id"] for x in json.load(response)["data"]]
    flashes = [x for x in names if "gemini" in x.lower() and "flash" in x.lower()]
    if not flashes:
        raise SystemExit("No Gemini Flash model is available on this LiteLLM endpoint.")
    model = "gemini-3.7-flash" if "gemini-3.7-flash" in flashes else sorted(flashes)[-1]
    root = Path.home() / ".config/book-ask"
    index = root / "mom-test-context.json"
    paragraphs = extract(args.epub)
    write_private(index, paragraphs)
    config = {"baseURL": base, "authFile": str(args.auth_file.resolve()), "authProvider": "litellm", "model": model,
              "contextFile": str(index), "bookTitle": "The Mom Test", "sourceEPUB": str(args.epub.resolve())}
    write_private(root / "config.json", config)
    print(json.dumps({"model": model, "paragraphs": len(paragraphs), "config": str(root / "config.json"), "keyCopied": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
