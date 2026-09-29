#!/usr/bin/env bash
# Converts a Hugging Face Whisper checkpoint (by default the Quran fine-tuned
# tarteel-ai/whisper-base-ar-quran) to the ggml format used by whisper.cpp,
# for on-device recognition in the app.
#
# Usage: tools/convert_model_to_ggml.sh [MODEL_ID] [OUT_DIR]
# Then host OUT_DIR/ggml-model.bin anywhere reachable over HTTPS and paste
# its URL in the app: الإعدادات ← على الجهاز ← رابط نموذج ggml.
set -euo pipefail

MODEL_ID="${1:-tarteel-ai/whisper-base-ar-quran}"
OUT_DIR="${2:-build/ggml}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m pip install -q huggingface_hub torch transformers numpy
git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp "$WORK/whisper.cpp"
# The converter reads mel filters and tokenizer assets from OpenAI's repo.
git clone -q --depth 1 https://github.com/openai/whisper "$WORK/whisper"
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$MODEL_ID', local_dir='$WORK/model')"

mkdir -p "$OUT_DIR"
python3 "$WORK/whisper.cpp/models/convert-h5-to-ggml.py" "$WORK/model" "$WORK/whisper" "$OUT_DIR"
echo "wrote $OUT_DIR/ggml-model.bin"
