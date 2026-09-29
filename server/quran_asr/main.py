"""HTTP and WebSocket API for Quran recitation recognition.

Endpoints
---------
GET  /health         liveness and model info
POST /v1/transcribe  transcribe a 16-bit PCM WAV upload
WS   /v1/stream      live recognition of a PCM16 16 kHz mono stream

Streaming protocol: the client sends binary audio messages and, when done, a
text message ``{"type": "stop"}``. The server sends JSON text messages:
``{"type": "ready"}`` once, then ``partial``/``final`` events per segment
(see ``streaming.py``), and ``{"type": "done"}`` before closing. ``final``
events carry ``words`` (text with start/end seconds) when the model supports
word timestamps; the app uses them to check madd lengths.
"""

from __future__ import annotations

import asyncio
import io
import json
import logging
import wave
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, Header, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect

from .config import Settings
from .streaming import StreamSession
from .transcriber import SAMPLE_RATE, Transcriber

log = logging.getLogger(__name__)


def decode_wav(data: bytes) -> np.ndarray:
    """Decode a 16-bit PCM WAV into mono float32 at 16 kHz."""
    try:
        with wave.open(io.BytesIO(data)) as w:
            if w.getsampwidth() != 2:
                raise ValueError("only 16-bit PCM WAV is supported")
            rate, channels = w.getframerate(), w.getnchannels()
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
    except (wave.Error, EOFError) as err:
        raise ValueError(f"invalid WAV file: {err}") from err
    audio = pcm.astype(np.float32) / 32768.0
    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE and audio.size:
        duration = audio.size / rate
        target = np.linspace(0, duration, int(duration * SAMPLE_RATE), endpoint=False)
        audio = np.interp(target, np.arange(audio.size) / rate, audio).astype(np.float32)
    return audio


def create_app(settings: Settings | None = None, transcriber: Transcriber | None = None) -> FastAPI:
    settings = settings or Settings()
    state: dict = {"transcriber": transcriber}

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if state["transcriber"] is None:
            from .transcriber import WhisperTranscriber

            state["transcriber"] = await asyncio.to_thread(
                WhisperTranscriber, settings.model_id, settings.device
            )
        yield

    app = FastAPI(title="Quran AI recognition server", lifespan=lifespan)

    def authorized(key: str | None) -> bool:
        return settings.api_key is None or key == settings.api_key

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "model": settings.model_id, "sample_rate": SAMPLE_RATE}

    @app.post("/v1/transcribe")
    async def transcribe(
        file: UploadFile,
        key: str | None = Query(default=None),
        x_api_key: str | None = Header(default=None),
    ) -> dict:
        if not authorized(key or x_api_key):
            raise HTTPException(status_code=401, detail="invalid API key")
        try:
            audio = decode_wav(await file.read())
        except ValueError as err:
            raise HTTPException(status_code=400, detail=str(err)) from err
        if audio.size > settings.max_upload_s * SAMPLE_RATE:
            raise HTTPException(status_code=413, detail="audio too long")
        text = await asyncio.to_thread(state["transcriber"].transcribe, audio)
        return {"text": text, "duration": audio.size / SAMPLE_RATE}

    @app.websocket("/v1/stream")
    async def stream(ws: WebSocket, key: str | None = Query(default=None)) -> None:
        if not authorized(key or ws.headers.get("x-api-key")):
            await ws.close(code=4401, reason="invalid API key")
            return
        await ws.accept()
        transcriber = state["transcriber"]
        session = StreamSession(
            transcriber.transcribe,
            settings.stream,
            transcribe_words=getattr(transcriber, "transcribe_words", None),
        )
        audio_queue: asyncio.Queue[bytes | None] = asyncio.Queue()

        async def receive() -> None:
            try:
                while True:
                    msg = await ws.receive()
                    if msg["type"] == "websocket.disconnect":
                        break
                    if msg.get("bytes"):
                        await audio_queue.put(msg["bytes"])
                    elif msg.get("text"):
                        try:
                            command = json.loads(msg["text"])
                        except json.JSONDecodeError:
                            continue
                        if command.get("type") == "stop":
                            break
            except WebSocketDisconnect:
                pass
            finally:
                await audio_queue.put(None)

        receiver = asyncio.create_task(receive())
        try:
            await ws.send_json({"type": "ready"})
            done = False
            while not done:
                # Coalesce everything that arrived while the model was busy.
                chunks = [await audio_queue.get()]
                while not audio_queue.empty():
                    chunks.append(audio_queue.get_nowait())
                if None in chunks:
                    done = True
                    chunks = [c for c in chunks if c is not None]
                if chunks:
                    for event in await asyncio.to_thread(session.feed, b"".join(chunks)):
                        await ws.send_json(event)
            for event in await asyncio.to_thread(session.finish):
                await ws.send_json(event)
            await ws.send_json({"type": "done"})
            await ws.close()
        except (WebSocketDisconnect, RuntimeError):
            log.info("client disconnected")
        finally:
            receiver.cancel()

    return app


app = create_app()
