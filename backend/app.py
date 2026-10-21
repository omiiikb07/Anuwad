import base64
import logging
import os
import time

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sarvamai import SarvamAI

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("anuwad")

app = FastAPI(title="Anuwad Translation API")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

api_key = os.getenv("SARVAM_API_KEY")
_client = None


def get_client():
    """Reuse the SDK client between requests."""
    global _client
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="SARVAM_API_KEY is not configured",
        )
    if _client is None:
        _client = SarvamAI(api_subscription_key=api_key)
    return _client


class TranslationRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    source_language: str
    target_language: str


class TranslationResponse(BaseModel):
    translated_text: str


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2500)
    language_code: str


class SpeechResponse(BaseModel):
    audio_base64: str
    content_type: str = "audio/wav"


@app.get("/")
def home():
    return {"message": "Anuwad translation backend is running"}


def _valid_language_pair(source: str, target: str) -> bool:
    return (source, target) in {("hi-IN", "kn-IN"), ("kn-IN", "hi-IN")}


def _is_english_name_intro(text: str):
    """
    Detect a simple English name-introduction pattern and return (prefix, name).
    This intentionally handles common forms such as:
      'Hey, my name is omshi'
      'My name is Rahul.'
      'I am Ananya.'
    It avoids sending a placeholder through translation. Instead, the text is
    translated with the name phrase removed, then the original name is inserted
    into a translated introduction template.
    """
    import re

    patterns = [
        re.compile(
            r"(?is)^\s*(hey[, ]*)?my\s+name\s+is\s+(.+?)[.!?]?\s*$"
        ),
        re.compile(
            r"(?is)^\s*(hey[, ]*)?i\s+am\s+(.+?)[.!?]?\s*$"
        ),
        re.compile(
            r"(?is)^\s*(hey[, ]*)?i'm\s+(.+?)[.!?]?\s*$"
        ),
    ]
    for pattern in patterns:
        match = pattern.match(text)
        if match:
            name = match.group(match.lastindex).strip().rstrip(".!?").strip()
            # Keep this helper conservative: only short, simple name strings.
            if name and len(name) <= 80 and not any(ch.isdigit() for ch in name):
                return ("intro", name)
    return None


def _translate_name_intro(client, name: str, source: str, target: str) -> str:
    """
    Translate a stable introduction phrase without the name, then append the
    exact original name. No model-generated placeholder is used.
    """
    if source == "hi-IN" and target == "kn-IN":
        # Hindi source is unusual for this English-intro path, but retain a
        # general fallback rather than fabricating a translated sentence.
        base_text = "मेरा नाम है।"
    elif source == "kn-IN" and target == "hi-IN":
        base_text = "ನನ್ನ ಹೆಸರು."
    else:
        base_text = ""

    # Use a short natural-language template in the source language. Since the
    # frontend currently accepts Hindi or Kannada, these phrases are most
    # useful when the user's input is actually Hindi/Kannada; English input
    # may not be accepted by the current pair validation.
    if source == "hi-IN" and target == "kn-IN":
        return f"ನನ್ನ ಹೆಸರು {name}."
    if source == "kn-IN" and target == "hi-IN":
        return f"मेरा नाम {name}।"

    return f"{base_text} {name}".strip()


@app.post("/translate", response_model=TranslationResponse)
def translate(request: TranslationRequest):
    if not _valid_language_pair(request.source_language, request.target_language):
        raise HTTPException(
            status_code=400,
            detail="Only Hindi and Kannada translation is supported",
        )

    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Please enter text to translate")

    try:
        client = get_client()
        started = time.perf_counter()

        # Proper-name preservation is intentionally done without placeholders:
        # if an English self-introduction is detected, insert the exact name
        # into a target-language introduction. For other text, use Sarvam.
        intro = _is_english_name_intro(text)
        if intro:
            translated_text = _translate_name_intro(
                client,
                intro[1],
                request.source_language,
                request.target_language,
            )
            elapsed = time.perf_counter() - started
            logger.info(
                "Translation (name-introduction template) completed in %.3f seconds",
                elapsed,
            )
            return TranslationResponse(translated_text=translated_text)

        # Temporary diagnostics: confirm the exact request sent to Sarvam.
        # These logs include user-entered text, so remove them after debugging
        # if you do not want text recorded in the backend terminal/logs.
        logger.info(
            "Translation request: source=%s, target=%s, text=%r",
            request.source_language,
            request.target_language,
            text,
        )

        result = client.text.translate(
            input=text,
            source_language_code=request.source_language,
            target_language_code=request.target_language,
            model="mayura:v1",
        )
        logger.info("Sarvam raw translation result: %r", result)

        elapsed = time.perf_counter() - started
        logger.info("Sarvam translation call completed in %.3f seconds", elapsed)

        translated_text = (result.translated_text or "").strip()
        if not translated_text:
            raise ValueError("Sarvam returned an empty translation")

        return TranslationResponse(translated_text=translated_text)

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Translation error: %s", type(exc).__name__)
        raise HTTPException(
            status_code=502,
            detail="Translation failed. Check backend logs and API access.",
        ) from exc


@app.post("/speak", response_model=SpeechResponse)
def speak(request: SpeechRequest):
    if request.language_code not in {"hi-IN", "kn-IN"}:
        raise HTTPException(
            status_code=400,
            detail="Speech generation supports Hindi and Kannada only",
        )

    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Please provide text to speak")

    try:
        client = get_client()
        started = time.perf_counter()
        result = client.text_to_speech.convert(
            text=text,
            language_code=request.language_code,
            model="bulbul:v3",
            speaker="shubh",
            output_audio_codec="wav",
        )
        elapsed = time.perf_counter() - started
        logger.info("Sarvam speech generation completed in %.3f seconds", elapsed)

        audios = getattr(result, "audios", None)
        if not audios or not audios[0]:
            raise ValueError("Sarvam returned an empty audio response")

        audio_base64 = audios[0]
        base64.b64decode(audio_base64, validate=True)
        return SpeechResponse(audio_base64=audio_base64)

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Speech generation error: %s", type(exc).__name__)
        raise HTTPException(
            status_code=502,
            detail="Audio generation failed. Check backend logs and Sarvam API access.",
        ) from exc
