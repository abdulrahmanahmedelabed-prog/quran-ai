"""Server settings, read from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env_float(name: str, default: float) -> float:
    value = os.environ.get(name)
    return float(value) if value else default


@dataclass(frozen=True)
class StreamConfig:
    """Voice activity and segmentation settings for streaming recognition."""

    sample_rate: int = 16_000
    frame_ms: int = 30
    # How often the in-progress segment is re-transcribed for live feedback.
    partial_interval_s: float = 1.0
    # Silence that closes a segment (a natural pause between phrases).
    end_silence_s: float = 0.7
    # Segments are cut here even without a pause; Whisper's window is 30 s.
    max_segment_s: float = 20.0
    # Shorter voiced bursts (clicks, breaths) are not sent to the model.
    min_speech_s: float = 0.3
    # Audio kept from before speech starts, so first syllables aren't cut.
    preroll_s: float = 0.3
    # A frame is voiced when RMS > max(rms_min, voice_ratio * noise_floor).
    rms_min: float = 0.004
    voice_ratio: float = 2.5
    noise_floor_cap: float = 0.02

    @property
    def frame_samples(self) -> int:
        return self.sample_rate * self.frame_ms // 1000


@dataclass(frozen=True)
class Settings:
    model_id: str = field(
        default_factory=lambda: os.environ.get(
            "QURAN_ASR_MODEL", "tarteel-ai/whisper-base-ar-quran"
        )
    )
    # "auto" picks CUDA, then Apple MPS, then CPU.
    device: str = field(default_factory=lambda: os.environ.get("QURAN_ASR_DEVICE", "auto"))
    # When set, clients must send it as the `key` query parameter or the
    # `X-API-Key` header.
    api_key: str | None = field(
        default_factory=lambda: os.environ.get("QURAN_ASR_API_KEY") or None
    )
    max_upload_s: float = field(
        default_factory=lambda: _env_float("QURAN_ASR_MAX_UPLOAD_S", 60.0)
    )
    stream: StreamConfig = field(default_factory=StreamConfig)
