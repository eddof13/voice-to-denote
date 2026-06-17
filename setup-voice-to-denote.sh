#!/usr/bin/env bash
# Sets up the voice-to-denote pipeline on a new Mac.
# Requires: Homebrew, Claude Code CLI already installed.
set -euo pipefail

echo "==> Creating directories..."
mkdir -p ~/voice_notes ~/notes ~/bin

echo "==> Installing ffmpeg..."
brew install ffmpeg

echo "==> Installing pipx..."
brew install pipx
pipx ensurepath

echo "==> Installing openai-whisper..."
pipx install openai-whisper

echo "==> Verifying installs..."
which whisper && whisper --version
which claude
which jq || brew install jq

echo "==> Copying voice-to-denote.sh..."
# If running from the same repo/directory as the script:
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/voice-to-denote.sh" ~/bin/voice-to-denote.sh
chmod +x ~/bin/voice-to-denote.sh

echo ""
echo "Done. Next steps:"
echo "  1. In MEGA app: sync your phone's voice recordings folder to ~/voice_notes"
echo "  2. In Keyboard Maestro: create a Folder Trigger on ~/voice_notes"
echo "     Action: Execute Shell Script"
echo "       ~/bin/voice-to-denote.sh \"\$KMVAR_kMTriggerValue\""
echo "  3. Test: copy an audio file into ~/voice_notes and watch ~/notes for the result"
