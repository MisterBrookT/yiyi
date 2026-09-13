#!/usr/bin/env python3
"""Validate the dependency-free GitHub Pages site, including every release image."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import sys
import struct

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "docs" / "site"

class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.refs, self.meta, self.images = set(), [], {}, []
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"): self.ids.add(values["id"])
        if tag in {"a", "link"} and values.get("href"): self.refs.append(values["href"])
        if tag in {"img", "source", "script"} and values.get("src"): self.refs.append(values["src"])
        if tag == "source" and values.get("srcset"): self.refs.extend(values["srcset"].split())
        if tag == "meta":
            key = values.get("name") or values.get("property")
            if key: self.meta[key] = values.get("content", "")
        if tag == "img": self.images.append(values)

html_path = SITE / "index.html"
parser = SiteParser()
parser.feed(html_path.read_text(encoding="utf-8"))
errors = []
for ref in parser.refs:
    parsed = urlparse(ref)
    if parsed.scheme in {"http", "https", "mailto"} or ref.startswith("//"): continue
    if ref.startswith("#"):
        if ref[1:] not in parser.ids: errors.append(f"missing anchor target: {ref}")
        continue
    clean = parsed.path
    path = SITE / clean
    if not path.exists():
        errors.append(f"missing local reference: {clean}")
for image in parser.images:
    if not image.get("alt") and image.get("alt") != "": errors.append(f"image missing alt: {image.get('src')}")
    if not image.get("width") or not image.get("height"): errors.append(f"image missing dimensions: {image.get('src')}")
    path = SITE / image.get('src', '')
    if path.is_file() and path.suffix == '.png':
        width, height = struct.unpack('>II', path.read_bytes()[16:24])
        if width * int(image.get('height', 0)) != height * int(image.get('width', 0)):
            errors.append(f"image dimensions have wrong aspect ratio: {path.name}")
for key in ["description", "og:title", "og:description", "og:url", "og:image", "twitter:card"]:
    if not parser.meta.get(key): errors.append(f"missing metadata: {key}")
text = html_path.read_text(encoding="utf-8")
for required in ['rel="canonical"', 'application/ld+json', 'prefers-reduced-motion', 'Skip to content']:
    corpus = text + (SITE / "styles.css").read_text(encoding="utf-8")
    if required not in corpus: errors.append(f"missing required feature: {required}")
print(f"Checked {html_path.relative_to(ROOT)}: {len(parser.refs)} references, {len(parser.ids)} anchors")
social = SITE / 'assets/social-preview.png'
if not social.is_file() or struct.unpack('>II', social.read_bytes()[16:24]) != (1200, 630):
    errors.append('missing or incorrectly sized social preview')
if errors:
    print("ERRORS:\n- " + "\n- ".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("PASS: links, anchors, all local assets, image dimensions, and metadata are valid")
