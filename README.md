# Anuwad — Hindi ↔ Kannada Translator

Anuwad is a voice-enabled translation application designed to help Hindi and Kannada speakers communicate across language barriers. It combines speech input, AI-powered text translation, and generated speech playback in one simple interface.

## Features

- **Voice Input:** Speak naturally using your microphone.
- **Hindi ↔ Kannada Translation:** Translate text in both directions.
- **AI-Generated Speech:** Listen to translations in the target language.
- **Copy Translation:** Copy translated text easily.
- **Editable Input:** Review and correct recognized speech before translating.

## Tech Stack

| Component | Technology |
|---|---|
| Frontend | Flutter, Dart |
| Backend | Python, FastAPI |
| Translation | Sarvam AI |
| Speech Generation | Sarvam AI Text-to-Speech |
| Speech Recognition | `speech_to_text` |
| HTTP Communication | REST API |

## How It Works

1. The user speaks into the microphone or enters text manually.
2. The application sends the text to the FastAPI backend.
3. The backend requests a translation from Sarvam AI.
4. The translated text appears in the Flutter interface.
5. When requested, the backend generates speech audio for playback.

## Getting Started

### Prerequisites

- Flutter SDK and Dart
- Python
- A Sarvam AI API key

### 1. Clone the repository

```bash
git clone https://github.com/omiiikb07/Anuwad.git
cd Anuwad
```

### 2. Configure the backend

Create and activate a Python virtual environment inside `backend`, then install the backend dependencies required by the project.

Create `backend/.env` and add:

```env
SARVAM_API_KEY=your_api_key_here
```

Never commit your real API key.

### 3. Start the backend

From the project root, run:

```bash
cd backend
python -m uvicorn app:app --reload
```

The backend should be available at `http://127.0.0.1:8000`.

### 4. Start the Flutter application

Open a second terminal in the project root:

```bash
flutter pub get
flutter run -d chrome
```

## Project Structure

```text
Anuwad/
├── backend/
│   └── app.py
├── lib/
│   └── main.dart
├── test/
├── web/
├── android/
├── ios/
├── windows/
├── linux/
├── macos/
├── pubspec.yaml
└── README.md
```

## Current Status

The web prototype supports Hindi ↔ Kannada text translation, microphone input, translation copying, and AI-generated audio playback.

## Future Improvements

- Improve responsive UI and accessibility.
- Add automated tests for translation and speech workflows.
- Improve error handling and loading states.
- Prepare deployment for wider access.
- Explore mobile platform support.

## Author

**Omshi Bhaskar**

GitHub: [@omiiikb07](https://github.com/omiiikb07)
