"""Turns a live PCM16 stream into partial and final transcripts.

Audio is cut into segments at natural pauses using an adaptive energy gate.
While a segment is open it is re-transcribed periodically (``partial``
events); when the reciter pauses it is transcribed once more and closed
(``final`` event). Silence is never sent to the model, which keeps Whisper
from hallucinating text on it.
"""

from __future__ import annotations

from collections import deque
from typing import Callable, Optional

import numpy as np

from .config import StreamConfig

Event = dict


class StreamSession:
    def __init__(
        self,
        transcribe: Callable[[np.ndarray], str],
        config: StreamConfig | None = None,
        transcribe_words: Optional[Callable[[np.ndarray], tuple[str, list[dict]]]] = None,
    ) -> None:
        """``transcribe_words``, when given, is used for final transcripts so
        ``final`` events carry per-word timings (seconds since stream start)."""
        self._transcribe = transcribe
        self._transcribe_words = transcribe_words
        self.cfg = config or StreamConfig()
        fs = self.cfg.frame_samples
        self._remainder = b""
        self._preroll: deque[np.ndarray] = deque(
            maxlen=max(1, int(self.cfg.preroll_s * self.cfg.sample_rate) // fs)
        )
        self._noise_floor = self.cfg.rms_min
        self._segment: list[np.ndarray] = []
        self._in_speech = False
        self._speech_samples = 0
        self._silence_samples = 0
        self._since_partial = 0
        self._last_partial = ""
        self.segment_index = 0
        # Samples consumed so far, and where the open segment starts.
        self._position = 0
        self._segment_start = 0

    # -- public API -------------------------------------------------------

    def feed(self, pcm16: bytes) -> list[Event]:
        """Consume little-endian mono PCM16 audio; return events to send."""
        data = self._remainder + pcm16
        frame_bytes = self.cfg.frame_samples * 2
        usable = len(data) - len(data) % frame_bytes
        self._remainder = data[usable:]
        events: list[Event] = []
        if usable == 0:
            return events
        samples = np.frombuffer(data[:usable], dtype="<i2").astype(np.float32) / 32768.0
        for frame in samples.reshape(-1, self.cfg.frame_samples):
            events.extend(self._process_frame(frame))
        # At most one partial per feed call, so a slow model never falls
        # further behind by transcribing stale audio repeatedly.
        if self._in_speech and self._since_partial >= self._samples(self.cfg.partial_interval_s):
            events.extend(self._partial())
        return events

    def finish(self) -> list[Event]:
        """Close the stream, transcribing whatever speech is still open."""
        events: list[Event] = []
        if self._in_speech:
            events.extend(self._finalize())
        return events

    # -- internals --------------------------------------------------------

    def _samples(self, seconds: float) -> int:
        return int(seconds * self.cfg.sample_rate)

    def _is_voiced(self, frame: np.ndarray) -> bool:
        rms = float(np.sqrt(np.mean(frame * frame)))
        voiced = rms > max(self.cfg.rms_min, self.cfg.voice_ratio * self._noise_floor)
        if not voiced:
            self._noise_floor = min(
                self.cfg.noise_floor_cap, 0.95 * self._noise_floor + 0.05 * rms
            )
        return voiced

    def _process_frame(self, frame: np.ndarray) -> list[Event]:
        frame_start = self._position
        self._position += frame.size
        voiced = self._is_voiced(frame)
        if not self._in_speech:
            if not voiced:
                self._preroll.append(frame)
                return []
            self._in_speech = True
            self._segment = list(self._preroll)
            self._segment_start = frame_start - sum(f.size for f in self._preroll)
            self._preroll.clear()
            self._speech_samples = 0
            self._silence_samples = 0
            self._since_partial = 0
            self._last_partial = ""

        events: list[Event] = []
        if self._segment_samples() + frame.size > self._samples(self.cfg.max_segment_s):
            events = self._finalize()
            # Speech continues straight into the next segment.
            self._in_speech = True
            self._segment_start = frame_start

        self._segment.append(frame)
        self._since_partial += frame.size
        if voiced:
            self._speech_samples += frame.size
            self._silence_samples = 0
        else:
            self._silence_samples += frame.size

        if self._silence_samples >= self._samples(self.cfg.end_silence_s):
            events.extend(self._finalize())
        return events

    def _segment_samples(self) -> int:
        return sum(f.size for f in self._segment)

    def _segment_audio(self) -> np.ndarray:
        audio = np.concatenate(self._segment) if self._segment else np.zeros(0, np.float32)
        if self._silence_samples:
            audio = audio[: max(0, audio.size - self._silence_samples)]
        return audio

    def _partial(self) -> list[Event]:
        self._since_partial = 0
        if self._speech_samples < self._samples(self.cfg.min_speech_s):
            return []
        text = self._transcribe(self._segment_audio())
        if not text or text == self._last_partial:
            return []
        self._last_partial = text
        return [{"type": "partial", "segment": self.segment_index, "text": text}]

    def _finalize(self) -> list[Event]:
        events: list[Event] = []
        if self._speech_samples >= self._samples(self.cfg.min_speech_s):
            audio = self._segment_audio()
            event: Event = {"type": "final", "segment": self.segment_index}
            if self._transcribe_words is not None:
                text, words = self._transcribe_words(audio)
                offset = self._segment_start / self.cfg.sample_rate
                event["words"] = [
                    {**w, "start": round(w["start"] + offset, 3), "end": round(w["end"] + offset, 3)}
                    for w in words
                ]
            else:
                text = self._transcribe(audio)
            event["text"] = text
            events.append(event)
            self.segment_index += 1
        self._in_speech = False
        self._segment = []
        self._speech_samples = 0
        self._silence_samples = 0
        self._since_partial = 0
        self._last_partial = ""
        return events
