import base64
import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sarvamai import SarvamAI

load_dotenv()

app = FastAPI(title="Anuwad Translation API")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

api_key = os.getenv("SARVAM_API_KEY")


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


@app.post("/translate", response_model=TranslationResponse)
def translate(request: TranslationRequest):
    if not api_key:
        raise HTTPException(status_code=500, detail="SARVAM_API_KEY is not configured")

    allowed_pairs = {("hi-IN", "kn-IN"), ("kn-IN", "hi-IN")}
    if (request.source_language, request.target_language) not in allowed_pairs:
        raise HTTPException(status_code=400, detail="Only Hindi and Kannada translation is supported")
    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Please enter text to translate")

    try:
        client = SarvamAI(api_subscription_key=api_key)
        result = client.text.translate(
            input=request.text,
            source_language_code=request.source_language,
            target_language_code=request.target_language,
            model="mayura:v1",
        )
        return TranslationResponse(translated_text=result.translated_text)
    except Exception as exc:
        print(f"Translation error: {type(exc).__name__}: {exc}")
        raise HTTPException(status_code=502, detail="Translation failed. Check backend logs and API access.") from exc


@app.post("/speak", response_model=SpeechResponse)
def speak(request: SpeechRequest):
    if not api_key:
        raise HTTPException(status_code=500, detail="SARVAM_API_KEY is not configured")
    if request.language_code not in {"hi-IN", "kn-IN"}:
        raise HTTPException(status_code=400, detail="Speech generation supports Hindi and Kannada only")
    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Please provide text to speak")

    try:
        client = SarvamAI(api_subscription_key=api_key)
        result = client.text_to_speech.convert(
            text=request.text,
            language_code=request.language_code,
            model="bulbul:v3",
            speaker="shubh",
            output_audio_codec="wav",
        )
        audios = getattr(result, "audios", None)
        if not audios or not audios[0]:
            raise ValueError("Sarvam returned an empty audio response")
        audio_base64 = audios[0]
        base64.b64decode(audio_base64, validate=True)
        return SpeechResponse(audio_base64=audio_base64)
    except Exception as exc:
        print(f"Speech generation error: {type(exc).__name__}: {exc}")
        raise HTTPException(status_code=502, detail="Audio generation failed. Check backend logs and Sarvam API access.") from exc
