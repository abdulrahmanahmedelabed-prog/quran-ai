#!/usr/bin/env python3
"""Build the Quran text asset bundled with the app.

Downloads the Uthmani (Hafs) text published by the quran-json project
(itself derived from the Tanzil Project, https://tanzil.net) and writes a
compact JSON file the app and the server both load.

The verse text is kept verbatim; only the container structure changes.

Usage:
    python tools/build_quran_data.py [--source URL_OR_PATH] [--out PATH]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import urllib.request

DEFAULT_SOURCE = "https://raw.githubusercontent.com/risan/quran-json/main/dist/quran.json"
REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OUT = REPO_ROOT / "app" / "assets" / "quran" / "quran_uthmani.json"

EXPECTED_SURAHS = 114
EXPECTED_AYAHS = 6236


def load_source(source: str) -> list[dict]:
    if source.startswith(("http://", "https://")):
        with urllib.request.urlopen(source, timeout=60) as resp:
            return json.load(resp)
    return json.loads(pathlib.Path(source).read_text(encoding="utf-8"))


def convert(raw: list[dict]) -> dict:
    surahs = []
    for s in raw:
        surahs.append(
            {
                "n": s["id"],
                "name": s["name"],
                "en": s["transliteration"],
                "type": s["type"],
                "ayahs": [v["text"] for v in s["verses"]],
            }
        )
    total = sum(len(s["ayahs"]) for s in surahs)
    if len(surahs) != EXPECTED_SURAHS or total != EXPECTED_AYAHS:
        raise SystemExit(f"unexpected data: {len(surahs)} surahs, {total} ayahs")
    return {
        "script": "uthmani-hafs",
        "source": "Tanzil Project (https://tanzil.net) via quran-json",
        "surahs": surahs,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    parser.add_argument("--out", type=pathlib.Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    data = convert(load_source(args.source))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    print(f"wrote {args.out} ({args.out.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
