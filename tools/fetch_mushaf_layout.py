#!/usr/bin/env python3
"""Fetches the Madinah Mushaf layout (604 pages x 15 lines, Hafs) from the
quran.com API and writes which words sit on which page and line.

The output keys words by (surah, ayah, word index) so the app lays out its
own Tanzil text with the mushaf's line breaks. Where quran.com splits an ayah
into a different number of words than Tanzil (a few dozen ayahs), its line
breaks are mapped proportionally onto Tanzil's words, so every word of the
text still appears exactly once.

Usage: python tools/fetch_mushaf_layout.py [--out PATH]

Output: {"pages": [[line, ...] x 604]} where each line is a list of segments
[surah, ayah, first_word, last_word, ends_ayah] (word indices 0-based,
inclusive; -1 when a line holds only an ayah's end marker). Lines holding a
surah title or the basmala have no segments.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import time
import urllib.request
from collections import defaultdict

API = (
    "https://api.quran.com/api/v4/verses/by_page/{page}"
    "?words=true&word_fields=text_uthmani,line_number,page_number&per_page=50&page={chunk}"
)
REPO = pathlib.Path(__file__).resolve().parents[1]
QURAN = REPO / "app" / "assets" / "quran" / "quran_uthmani.json"
PAGES = 604
LINES = 15


def get(url: str) -> dict:
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "quran-ai-layout/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except Exception:  # noqa: BLE001 - retry transient failures
            if attempt == 4:
                raise
            time.sleep(2 * (attempt + 1))
    raise AssertionError


def page_verses(page: int) -> list[dict]:
    verses, chunk = [], 1
    while chunk:
        data = get(API.format(page=page, chunk=chunk))
        verses += data["verses"]
        chunk = (data.get("pagination") or {}).get("next_page")
    return verses


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=REPO / "app" / "assets" / "quran" / "mushaf_madani.json")
    args = parser.parse_args()

    # Every word's own page and line. A verse spanning two pages may be
    # returned for either page, so words are placed by their page_number,
    # never by the page that was requested.
    words: dict[tuple[int, int], dict[int, tuple[int, int]]] = defaultdict(dict)
    ends: dict[tuple[int, int], tuple[int, int]] = {}
    for page in range(1, PAGES + 1):
        for verse in page_verses(page):
            key = tuple(map(int, verse["verse_key"].split(":")))
            for w in verse["words"]:
                where = (w["page_number"] - 1, w["line_number"] - 1)
                if w["char_type_name"] == "end":
                    ends[key] = where
                else:
                    words[key][w["position"] - 1] = where
        if page % 50 == 0:
            print(f"page {page}/{PAGES}", flush=True)

    ours = json.loads(QURAN.read_text(encoding="utf-8"))
    pages: list[list[list[list[int]]]] = [[[] for _ in range(LINES)] for _ in range(PAGES)]
    remapped = []
    for s in ours["surahs"]:
        for a, text in enumerate(s["ayahs"], start=1):
            key = (s["n"], a)
            n = len(text.split())
            theirs = [words[key][i] for i in sorted(words[key])]
            if not theirs:
                raise SystemExit(f"no layout for {key}")
            m = len(theirs)
            if m != n:
                remapped.append(f"{key[0]}:{key[1]} quran.com={m} tanzil={n}")
            # Our word i sits where their word floor(i * m / n) sits.
            for i in range(n):
                p, line = theirs[min(m - 1, i * m // n)]
                segs = pages[p][line]
                if segs and segs[-1][0] == key[0] and segs[-1][1] == a and segs[-1][3] == i - 1:
                    segs[-1][3] = i
                else:
                    segs.append([key[0], a, i, i, 0])
            p, line = ends.get(key, theirs[-1])
            segs = pages[p][line]
            if segs and segs[-1][0] == key[0] and segs[-1][1] == a:
                segs[-1][4] = 1
            else:
                segs.append([key[0], a, -1, -1, 1])

    args.out.write_text(
        json.dumps({"source": "quran.com API v4, Madinah Mushaf (15 lines)", "pages": pages}, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"wrote {args.out} ({args.out.stat().st_size // 1024} KiB)")
    print(f"{len(remapped)} ayahs split into a different number of words (mapped proportionally):")
    for r in remapped:
        print("  ", r)


if __name__ == "__main__":
    main()
