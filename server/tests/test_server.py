import io
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from quran_asr.config import Settings, StreamConfig
from quran_asr.main import create_app, decode_wav
from quran_asr.streaming import StreamSession
from quran_asr.transcriber import words_from_chunks

RATE = 16_000


def tone(seconds: float, amp: float = 0.3) -> np.ndarray:
    t = np.arange(int(seconds * RATE)) / RATE
    return (amp * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * RATE), np.float32)


def pcm16(audio: np.ndarray) -> bytes:
    return (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()


def wav_bytes(audio: np.ndarray, rate: int = RATE, channels: int = 1) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm16(np.repeat(audio, channels)))
    return buf.getvalue()


class FakeTranscriber:
    """Reports how much audio it was given, so tests can check segmentation."""

    def __init__(self) -> None:
        self.calls: list[int] = []

    def transcribe(self, audio: np.ndarray) -> str:
        self.calls.append(audio.size)
        return f"كلمة{round(audio.size / RATE, 1)}"


def feed_in_chunks(session: StreamSession, audio: np.ndarray, chunk_s: float = 0.1) -> list[dict]:
    data = pcm16(audio)
    step = int(chunk_s * RATE) * 2
    events = []
    for i in range(0, len(data), step):
        events.extend(session.feed(data[i : i + step]))
    return events


class TestStreamSession:
    def test_silence_is_never_transcribed(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe)
        assert feed_in_chunks(session, silence(3)) == []
        assert session.finish() == []
        assert fake.calls == []

    def test_pause_closes_a_segment(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe)
        events = feed_in_chunks(session, np.concatenate([silence(0.5), tone(2.5), silence(1.0)]))
        finals = [e for e in events if e["type"] == "final"]
        partials = [e for e in events if e["type"] == "partial"]
        assert len(finals) == 1
        assert finals[0]["segment"] == 0
        assert partials, "live partials are sent while speaking"
        # Final audio = preroll + speech, with trailing silence trimmed.
        assert abs(fake.calls[-1] / RATE - 2.8) < 0.1

    def test_two_phrases_make_two_segments(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe)
        audio = np.concatenate([tone(1.5), silence(1.0), tone(1.5), silence(1.0)])
        finals = [e for e in feed_in_chunks(session, audio) if e["type"] == "final"]
        assert [e["segment"] for e in finals] == [0, 1]

    def test_long_speech_is_cut_at_max_segment(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe, StreamConfig(max_segment_s=5))
        events = feed_in_chunks(session, tone(12))
        events += session.finish()
        finals = [e for e in events if e["type"] == "final"]
        assert len(finals) == 3
        assert all(n <= 5 * RATE for n in fake.calls)

    def test_short_clicks_are_ignored(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe)
        events = feed_in_chunks(session, np.concatenate([tone(0.1), silence(1.5)]))
        assert events == [] and fake.calls == []

    def test_odd_sized_chunks_are_buffered(self):
        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe)
        data = pcm16(np.concatenate([tone(1.0), silence(1.0)]))
        events = []
        for i in range(0, len(data), 333):
            events.extend(session.feed(data[i : i + 333]))
        assert [e["type"] for e in events if e["type"] == "final"] == ["final"]


class TestDecodeWav:
    def test_resamples_and_downmixes(self):
        one_second_at_44k = np.zeros(44_100, np.float32)
        audio = decode_wav(wav_bytes(one_second_at_44k, rate=44_100, channels=2))
        assert abs(audio.size - RATE) <= 1

    def test_rejects_garbage(self):
        with pytest.raises(ValueError):
            decode_wav(b"not a wav")


@pytest.fixture
def client():
    app = create_app(Settings(api_key="secret"), transcriber=FakeTranscriber())
    with TestClient(app) as c:
        yield c


class TestApi:
    def test_health(self, client):
        assert client.get("/health").json()["status"] == "ok"

    def test_transcribe(self, client):
        files = {"file": ("a.wav", wav_bytes(tone(1.0)), "audio/wav")}
        res = client.post("/v1/transcribe?key=secret", files=files)
        assert res.status_code == 200
        assert res.json()["text"] == "كلمة1.0"

    def test_transcribe_requires_key(self, client):
        files = {"file": ("a.wav", wav_bytes(tone(1.0)), "audio/wav")}
        assert client.post("/v1/transcribe", files=files).status_code == 401

    def test_stream(self, client):
        with client.websocket_connect("/v1/stream?key=secret") as ws:
            assert ws.receive_json() == {"type": "ready"}
            data = pcm16(np.concatenate([tone(1.5), silence(1.0)]))
            for i in range(0, len(data), 3200):
                ws.send_bytes(data[i : i + 3200])
            ws.send_text('{"type": "stop"}')
            events = []
            while True:
                event = ws.receive_json()
                events.append(event)
                if event["type"] == "done":
                    break
        assert [e for e in events if e["type"] == "final"][0]["text"].startswith("كلمة")

    def test_stream_rejects_bad_key(self, client):
        from starlette.websockets import WebSocketDisconnect

        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/v1/stream?key=wrong") as ws:
                ws.receive_json()


class TestWordTimings:
    def test_final_events_carry_word_times_on_the_stream_timeline(self):
        def timed(audio: np.ndarray):
            half = audio.size / RATE / 2
            return "قل هو", [
                {"text": "قل", "start": 0.0, "end": half},
                {"text": "هو", "start": half, "end": 2 * half},
            ]

        fake = FakeTranscriber()
        session = StreamSession(fake.transcribe, transcribe_words=timed)
        audio = np.concatenate([silence(2.0), tone(1.0), silence(1.0)])
        final = [e for e in feed_in_chunks(session, audio) if e["type"] == "final"][0]
        assert final["text"] == "قل هو"
        words = final["words"]
        # Speech starts at 2.0 s; the segment includes 0.3 s of preroll.
        assert abs(words[0]["start"] - 1.7) < 0.05
        assert abs(words[-1]["end"] - 3.0) < 0.05

    def test_words_from_chunks(self):
        chunks = [
            {"text": " بسم", "timestamp": (0.0, 0.4)},
            {"text": " ", "timestamp": (0.4, 0.5)},
            {"text": " الله", "timestamp": (0.5, None)},
        ]
        assert words_from_chunks(chunks, 1.2) == [
            {"text": "بسم", "start": 0.0, "end": 0.4},
            {"text": "الله", "start": 0.5, "end": 1.2},
        ]
