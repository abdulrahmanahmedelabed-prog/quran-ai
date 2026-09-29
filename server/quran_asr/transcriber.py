"""Speech recognition backends.

The default backend runs a Whisper checkpoint fine-tuned on Quran recitation
(tarteel-ai/whisper-base-ar-quran) with Hugging Face transformers. Anything
with a ``transcribe(audio) -> str`` method can stand in for it, which is how
the tests run without downloading a model.
"""

from __future__ import annotations

import logging
import threading
from typing import Protocol

import numpy as np

log = logging.getLogger(__name__)

SAMPLE_RATE = 16_000


class Transcriber(Protocol):
    def transcribe(self, audio: np.ndarray) -> str:
        """Transcribe mono float32 audio at 16 kHz in [-1, 1]."""
        ...


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
