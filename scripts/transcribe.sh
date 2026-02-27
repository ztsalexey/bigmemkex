#!/bin/bash
# Local Whisper transcription wrapper
# Usage: transcribe.sh <audio_file> [model_size]
# Models: tiny (fastest), base (default), small, medium, large-v3 (best)

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
VENV_DIR="$HOME/.openclaw/workspace/whisper-env"

source "$VENV_DIR/bin/activate"
python3 "$SCRIPT_DIR/transcribe.py" "$@"
