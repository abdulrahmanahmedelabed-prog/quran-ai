#!/usr/bin/env python3
"""Prints screenshots as base64 JPEG between markers, so they can be read
back from CI logs where artifact downloads aren't available.

Usage: python tools/print_screenshots.py app/screenshots
"""
import base64
import io
import pathlib
import sys

from PIL import Image

for path in sorted(pathlib.Path(sys.argv[1]).glob("*.png")):
    im = Image.open(path).convert("RGB")
    im.thumbnail((540, 1200))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=70)
    data = base64.b64encode(buf.getvalue()).decode()
    print(f"SHOT_BEGIN {path.stem}")
    for i in range(0, len(data), 900):
        print(data[i : i + 900])
    print("SHOT_END")
