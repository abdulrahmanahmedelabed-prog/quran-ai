#!/usr/bin/env bash
# Runs the recognition server without Docker (Linux/macOS, Python 3.10+).
# First run creates a virtualenv and installs dependencies (~2 GB with
# PyTorch); the model downloads from Hugging Face on first start.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q -r requirements.txt
fi
exec .venv/bin/uvicorn quran_asr.main:app --host 0.0.0.0 --port "${PORT:-8000}"
