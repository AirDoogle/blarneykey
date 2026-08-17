#!/bin/bash
# One-time setup on a new Mac. Downloads the speech model from Hugging Face and
# assembles it into the layout BlarneyKey expects, then builds the app.
#
# Nothing here comes from anywhere but Homebrew and Hugging Face.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")" && pwd)"
MODEL_NAME="${1:-distil-large-v3}"
PREFIX="${2:-distil}"
STAGING="$PROJECT/.model-download"
TARGET="$PROJECT/models/combined"

echo "==> Checking for whisperkit-cli"
if ! command -v whisperkit-cli >/dev/null 2>&1; then
  echo "    installing via Homebrew"
  brew install whisperkit-cli
fi

echo "==> Downloading $MODEL_NAME (about 1.4 GB for distil-large-v3)"
mkdir -p "$STAGING"
# Transcribing a scrap of silence is the way to make the CLI fetch the model and
# tokenizer; there is no separate download subcommand.
SILENCE="$STAGING/silence.wav"
if [ ! -f "$SILENCE" ]; then
  say -o "$SILENCE" --data-format=LEF32@16000 "setup" >/dev/null 2>&1
fi
whisperkit-cli transcribe \
  --model "$MODEL_NAME" \
  --model-prefix "$PREFIX" \
  --download-model-path "$STAGING" \
  --download-tokenizer-path "$STAGING" \
  --audio-path "$SILENCE" \
  --without-timestamps >/dev/null

echo "==> Assembling $TARGET"
# whisperkit-cli looks for tokenizer.json beside the .mlmodelc folders. Keeping them
# together means the app never needs the network again.
MODEL_DIR="$(find "$STAGING" -type d -name '*.mlmodelc' -print -quit | xargs dirname)"
if [ -z "$MODEL_DIR" ]; then
  echo "!! Could not find the downloaded model under $STAGING" >&2
  exit 1
fi
TOKENIZER_DIR="$(find "$STAGING" -name 'tokenizer.json' -print -quit | xargs dirname)"
if [ -z "$TOKENIZER_DIR" ]; then
  echo "!! Could not find tokenizer.json under $STAGING" >&2
  exit 1
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -R "$MODEL_DIR/." "$TARGET/"
cp "$TOKENIZER_DIR/tokenizer.json" "$TOKENIZER_DIR/tokenizer_config.json" "$TARGET/"

echo "==> Testing the engine"
whisperkit-cli transcribe --model-path "$TARGET" --model-prefix "$PREFIX" \
  --audio-path "$SILENCE" --without-timestamps --skip-special-tokens >/dev/null
echo "    engine OK"

rm -rf "$STAGING"

echo "==> Building the app"
"$PROJECT/build.sh"

echo
echo "Done. Open it with:  open ~/Applications/BlarneyKey.app"
