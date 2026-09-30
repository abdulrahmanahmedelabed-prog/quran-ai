#!/usr/bin/env python3
"""Fixes n_text_ctx in a Whisper ggml file converted from Hugging Face.

convert-h5-to-ggml.py writes the generation max_length as n_text_ctx, but
the decoder's positional embedding has max_target_positions rows; when they
differ (1024 vs 448 for tarteel-ai/whisper-base-ar-quran) whisper.cpp stops
with "tensor 'decoder.positional_embedding' has wrong size" and the model
never loads.

Usage:
  fix_ggml_text_ctx.py MODEL.bin CONFIG.json   patch the header in place
  fix_ggml_text_ctx.py --check-heard FILE      check a transcript of al-Fatiha 1-4
"""

import json
import re
import struct
import sys

# Header: magic, then n_vocab, n_audio_ctx, n_audio_state, n_audio_head,
# n_audio_layer, n_text_ctx, ... as int32.
TEXT_CTX_OFFSET = 4 + 5 * 4


def fix(model: str, config: str) -> None:
    want = json.load(open(config, encoding="utf-8"))["max_target_positions"]
    with open(model, "r+b") as f:
        if struct.unpack("<I", f.read(4))[0] != 0x67676D6C:
            sys.exit(f"{model}: not a ggml file")
        f.seek(TEXT_CTX_OFFSET)
        have = struct.unpack("<i", f.read(4))[0]
        if have != want:
            f.seek(TEXT_CTX_OFFSET)
            f.write(struct.pack("<i", want))
        print(f"n_text_ctx: {have} -> {want}")


def check_heard(path: str) -> None:
    text = open(path, encoding="utf-8").read()
    # Compare skeletons: no marks and no alefs, so Uthmani and plain
    # spellings (ٱلرَّحْمَٰنِ, الرحمن) match.
    plain = re.sub(r"[ً-ٰٟۖ-ۭـاأإآٱ]", "", text)
    missing = [w for w in ("لرحمن", "لرحيم", "لحمد", "لعلمين") if w not in plain]
    if missing:
        sys.exit(f"transcript lacks {missing}: {text!r}")
    print("recognized al-Fatiha")


if __name__ == "__main__":
    if sys.argv[1] == "--check-heard":
        check_heard(sys.argv[2])
    else:
        fix(sys.argv[1], sys.argv[2])
