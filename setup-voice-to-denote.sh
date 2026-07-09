#!/usr/bin/env bash
# Sets up the voice-to-denote pipeline on a new Mac.
# Requires: Homebrew, and at least one of: Claude Code CLI or Grok Build CLI.
set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.grok/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "==> Creating directories..."
mkdir -p ~/voice_notes ~/notes ~/bin ~/forge/Active\ Projects

echo "==> Installing ffmpeg..."
brew install ffmpeg

echo "==> Installing pipx..."
brew install pipx
pipx ensurepath

echo "==> Installing openai-whisper..."
pipx install openai-whisper

echo "==> Verifying installs..."
which whisper && whisper --version
which jq || brew install jq

echo "==> Checking LLM CLIs (need at least one)..."
HAVE_LLM=0
if command -v claude >/dev/null 2>&1; then
  echo "    claude: $(command -v claude)"
  HAVE_LLM=1
else
  echo "    claude: not found (optional — https://claude.ai/code )"
fi
if command -v grok >/dev/null 2>&1; then
  echo "    grok:   $(command -v grok)"
  HAVE_LLM=1
else
  echo "    grok:   not found (optional — Grok Build CLI)"
fi
if [[ "$HAVE_LLM" -eq 0 ]]; then
  echo ""
  echo "WARNING: neither claude nor grok is on PATH."
  echo "Install at least one before the pipeline can classify transcripts."
  echo "  VOICE_TO_DENOTE_LLM=auto|claude|grok  (default auto)"
  echo "  FORGE_AGENT=auto|claude|grok          (default auto, for forge-open-session)"
fi

echo "==> Copying scripts to ~/bin/..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/voice-to-denote.sh" ~/bin/voice-to-denote.sh
chmod +x ~/bin/voice-to-denote.sh
if [[ -f "$SCRIPT_DIR/forge-open-session.sh" ]]; then
  cp "$SCRIPT_DIR/forge-open-session.sh" ~/bin/forge-open-session.sh
  chmod +x ~/bin/forge-open-session.sh
fi
if [[ -f "$SCRIPT_DIR/sweep-voice-notes.sh" ]]; then
  cp "$SCRIPT_DIR/sweep-voice-notes.sh" ~/bin/sweep-voice-notes.sh
  chmod +x ~/bin/sweep-voice-notes.sh
fi

echo ""
echo "Done. Next steps:"
echo "  1. In MEGA app: sync your phone's voice recordings folder to ~/voice_notes"
echo "  2. In Keyboard Maestro: import Voice to Denote.kmmacros and Forge Sessions.kmmacros"
echo "     (double-click each .kmmacros file)"
echo "  3. Optional env (shell profile or KM Execute Shell Script prefix):"
echo "       export VOICE_TO_DENOTE_LLM=auto   # or claude | grok"
echo "       export FORGE_AGENT=auto           # or claude | grok"
echo "  4. Test voice-to-denote: copy an audio file into ~/voice_notes and watch ~/notes"
echo "  5. Test Forge — Open Session: press the bound hotkey to pick a project"
