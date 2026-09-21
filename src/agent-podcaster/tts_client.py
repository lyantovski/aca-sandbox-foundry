"""Azure OpenAI text-to-speech client."""
from __future__ import annotations

import os

import httpx

VOICE_MAP = {
    "host": "nova",
    "guest": "onyx",
}


class TTSClient:
    """Synthesize podcast turns through the APIM-governed TTS endpoint."""

    def __init__(self):
        self._http = httpx.AsyncClient(timeout=60.0)

    async def synthesize(self, text: str, speaker: str) -> bytes:
        """Synthesize speech for one podcast turn and return WAV bytes."""
        voice = VOICE_MAP.get(speaker, "nova")
        endpoint = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
        api_key = os.environ["AZURE_OPENAI_API_KEY"]
        api_version = os.getenv("AZURE_OPENAI_TTS_API_VERSION", "2024-12-01-preview")

        url = f"{endpoint}/openai/deployments/tts-1/audio/speech?api-version={api_version}"
        resp = await self._http.post(
            url,
            headers={"api-key": api_key, "Content-Type": "application/json"},
            json={"model": "tts-1", "input": text, "voice": voice, "response_format": "wav"},
            timeout=30.0,
        )
        resp.raise_for_status()
        return resp.content

    async def close(self) -> None:
        await self._http.aclose()
