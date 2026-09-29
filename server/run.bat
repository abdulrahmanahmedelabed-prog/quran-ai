@echo off
rem Runs the recognition server without Docker (Windows, Python 3.10+).
cd /d "%~dp0"
if not exist .venv (
  python -m venv .venv
  .venv\Scripts\pip install -q --upgrade pip
  .venv\Scripts\pip install -q -r requirements.txt
)
.venv\Scripts\uvicorn quran_asr.main:app --host 0.0.0.0 --port 8000
