FROM python:3.11-slim

WORKDIR /app

# CPU build of PyTorch; use a CUDA base image and wheel for GPU servers.
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ARG QURAN_ASR_MODEL=tarteel-ai/whisper-base-ar-quran
ENV QURAN_ASR_MODEL=${QURAN_ASR_MODEL}
# Bake the model into the image so containers start without downloading it.
RUN python -c "import os; from transformers import WhisperProcessor, WhisperForConditionalGeneration as W; \
m = os.environ['QURAN_ASR_MODEL']; WhisperProcessor.from_pretrained(m); W.from_pretrained(m)"

COPY quran_asr ./quran_asr

EXPOSE 8000
CMD ["uvicorn", "quran_asr.main:app", "--host", "0.0.0.0", "--port", "8000"]
