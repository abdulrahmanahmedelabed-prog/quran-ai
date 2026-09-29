#!/usr/bin/env python3
"""Fetches the Madinah Mushaf layout (604 pages x 15 lines, Hafs) from the
quran.com API and writes which words sit on which page and line.

The output keys words by (surah, ayah, word index) so the app can lay out its
own Tanzil text with the mushaf's exact line breaks. Word counts per ayah are
checked against app/assets/quran/quran_uthmani.json.

Usage: python tools/fetch_mushaf_layout.py [--out PATH]

Output: {"pages": [[line, ...] x 604]} where each line is a list of segments
[surah, ayah, first_word, last_word, ends_ayah] (word indices 0-based,
inclusive). Lines holding a surah title or the basmala have no segments.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import time
import urllib.request

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

    ours = json.loads(QURAN.read_text(encoding="utf-8"))
    our_counts = {
        (s["n"], a + 1): len(text.split()) for s in ours["surahs"] for a, text in enumerate(s["ayahs"])
    }

    pages = []
    mismatches = []
    for page in range(1, PAGES + 1):
        lines: list[list[list]] = [[] for _ in range(LINES)]
        for verse in page_verses(page):
            surah, ayah = map(int, verse["verse_key"].split(":"))
            words = [w for w in verse["words"] if w.get("page_number", page) == page]
            index = 0  # word index within the ayah, counting words only
            # quran.com positions count words of the whole ayah, even ones on
            # the previous page; recover the index from the position.
            for w in words:
                line = w["line_number"] - 1
                is_end = w["char_type_name"] == "end"
                if not is_end:
                    index = w["position"] - 1
                segs = lines[line]
                if segs and segs[-1][0] == surah and segs[-1][1] == ayah:
                    seg = segs[-1]
                    if is_end:
                        seg[4] = 1
                    else:
                        seg[3] = index
                elif not is_end:
                    segs.append([surah, ayah, index, index, 0])
                else:
                    # An ayah marker alone at the start of a line.
                    segs.append([surah, ayah, -1, -1, 1])
            total = sum(1 for w in verse["words"] if w["char_type_name"] == "word")
            if total != our_counts.get((surah, ayah)):
                mismatches.append(f"{surah}:{ayah} quran.com={total} ours={our_counts.get((surah, ayah))}")
        pages.append(lines)
        if page % 50 == 0:
            print(f"page {page}/{PAGES}", flush=True)

    args.out.write_text(
        json.dumps({"source": "quran.com API v4, Madinah Mushaf (15 lines)", "pages": pages}, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"wrote {args.out} ({args.out.stat().st_size // 1024} KiB)")
    print(f"{len(set(mismatches))} ayahs with different word counts")
    for m in sorted(set(mismatches))[:40]:
        print("  ", m)


if __name__ == "__main__":
    main()
