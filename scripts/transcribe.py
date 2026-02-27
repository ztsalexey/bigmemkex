#!/usr/bin/env python3
"""Local Whisper transcription using faster-whisper."""
import sys
import json
from faster_whisper import WhisperModel

def transcribe(audio_path: str, model_size: str = "base") -> dict:
    """Transcribe audio file and return result."""
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    segments, info = model.transcribe(audio_path, beam_size=5)
    
    text = " ".join([segment.text.strip() for segment in segments])
    
    return {
        "text": text,
        "language": info.language,
        "language_probability": round(info.language_probability, 3),
        "duration": round(info.duration, 2)
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: transcribe.py <audio_file> [model_size]")
        print("Models: tiny, base, small, medium, large-v3")
        sys.exit(1)
    
    audio_file = sys.argv[1]
    model = sys.argv[2] if len(sys.argv) > 2 else "base"
    
    result = transcribe(audio_file, model)
    print(json.dumps(result, indent=2))
