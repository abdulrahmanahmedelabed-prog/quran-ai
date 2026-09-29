"""Speech recognition backends.

The default backend runs a Whisper checkpoint fine-tuned on Quran recitation
(tarteel-ai/whisper-base-ar-quran) with Hugging Face transformers. Anything
with a ``transcribe(audio) -> str`` method can stand in for it, which is how
the tests run without downloading a model.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from typing import Protocol

import numpy as np

log = logging.getLogger(__name__)

SAMPLE_RATE = 16_000

# Cross-attention heads that track time in openai/whisper-base. Fine-tuned
# checkpoints usually drop them from their generation config, but keep the
# architecture, so the base model's heads still give usable word timings.
WHISPER_BASE_ALIGNMENT_HEADS = [[3, 1], [4, 2], [4, 3], [4, 7], [5, 1], [5, 2], [5, 4], [5, 6]]


class Transcriber(Protocol):
    def transcribe(self, audio: np.ndarray) -> str:
        """Transcribe mono float32 audio at 16 kHz in [-1, 1]."""
        ...


class TimedTranscriber(Transcriber, Protocol):
    def transcribe_words(self, audio: np.ndarray) -> tuple[str, list[dict]]:
        """Like ``transcribe``, plus ``[{"text", "start", "end"}]`` per word
        (seconds from the start of ``audio``)."""
        ...


def words_from_chunks(chunks: list[dict], duration: float) -> list[dict]:
    """Converts transformers' word chunks into ``{"text", "start", "end"}``.

    The last chunk's end can be missing; it is clamped to the audio length.
    """
    words = []
    for chunk in chunks:
        text = chunk.get("text", "").strip()
        start, end = chunk.get("timestamp") or (None, None)
        if not text or start is None:
            continue
        end = duration if end is None else min(end, duration)
        words.append({"text": text, "start": round(float(start), 3), "end": round(float(max(end, start)), 3)})
    return words


def _pick_device(requested: str) -> str:
    import torch

    if requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


class WhisperTranscriber:
    """Whisper via transformers. Thread-safe; calls are serialized."""

    def __init__(self, model_id: str, device: str = "auto") -> None:
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor

        self._torch = torch
        self.device = _pick_device(device)
        self._dtype = torch.float16 if self.device == "cuda" else torch.float32
        log.info("loading %s on %s", model_id, self.device)
        self._processor = WhisperProcessor.from_pretrained(model_id)
        self._model = WhisperForConditionalGeneration.from_pretrained(
            model_id, torch_dtype=self._dtype
        ).to(self.device)
        self._model.eval()
        self._lock = threading.Lock()
        # Older fine-tuned checkpoints lack the language tables newer
        # transformers need for `language=`; they are Arabic-only anyway.
        self._generate_kwargs: dict = {"language": "ar", "task": "transcribe"}
        self._timestamps = self._setup_alignment_heads()
        self._pipe = None

    def _setup_alignment_heads(self) -> bool:
        gen = self._model.generation_config
        env = os.environ.get("QURAN_ASR_ALIGNMENT_HEADS")
        if env:
            gen.alignment_heads = json.loads(env)
        elif getattr(gen, "alignment_heads", None) is None:
            cfg = self._model.config
            if (cfg.decoder_layers, cfg.decoder_attention_heads) == (6, 8):
                gen.alignment_heads = WHISPER_BASE_ALIGNMENT_HEADS
        enabled = getattr(gen, "alignment_heads", None) is not None
        if not enabled:
            log.warning("no alignment heads for this model; word timings disabled")
        return enabled

    def transcribe(self, audio: np.ndarray) -> str:
        if audio.size == 0:
            return ""
        features = self._processor(
            audio, sampling_rate=SAMPLE_RATE, return_tensors="pt"
        ).input_features.to(self.device, dtype=self._dtype)
        with self._lock, self._torch.inference_mode():
            try:
                ids = self._model.generate(features, **self._generate_kwargs)
            except (ValueError, TypeError) as err:
                if not self._generate_kwargs:
                    raise
                log.warning("model rejected language hints (%s); retrying without", err)
                self._generate_kwargs = {}
                ids = self._model.generate(features)
        text = self._processor.batch_decode(ids, skip_special_tokens=True)[0]
        return text.strip()

    def transcribe_words(self, audio: np.ndarray) -> tuple[str, list[dict]]:
        if audio.size == 0:
            return "", []
        if not self._timestamps:
            return self.transcribe(audio), []
        from transformers import pipeline

        with self._lock, self._torch.inference_mode():
            if self._pipe is None:
                self._pipe = pipeline(
                    "automatic-speech-recognition",
                    model=self._model,
                    tokenizer=self._processor.tokenizer,
                    feature_extractor=self._processor.feature_extractor,
                    device=self.device,
                )
            try:
                out = self._pipe(
                    audio.copy(), return_timestamps="word", generate_kwargs=self._generate_kwargs
                )
            except Exception as err:  # noqa: BLE001 - timings are optional
                log.warning("word timestamps failed (%s); disabling them", err)
                self._timestamps = False
                out = None
        if out is None:
            return self.transcribe(audio), []
        return out["text"].strip(), words_from_chunks(out.get("chunks", []), audio.size / SAMPLE_RATE)
