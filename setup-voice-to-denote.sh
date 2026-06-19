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

echo "==> Copying scripts to ~/bin/..."
# If running from the same repo/directory as the script:
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/voice-to-denote.sh" ~/bin/voice-to-denote.sh
chmod +x ~/bin/voice-to-denote.sh
cp "$SCRIPT_DIR/forge-open-session.sh" ~/bin/forge-open-session.sh
chmod +x ~/bin/forge-open-session.sh

echo ""
echo "Done. Next steps:"
echo "  1. In MEGA app: sync your phone's voice recordings folder to ~/voice_notes"
echo "  2. In Keyboard Maestro: import Voice to Denote.kmmacros and Forge Sessions.kmmacros"
echo "     (double-click each .kmmacros file)"
echo "  3. Test voice-to-denote: copy an audio file into ~/voice_notes and watch ~/notes"
echo "  4. Test Forge — Open Session: press ⌃⌥⌘O to pick a project and open it"
echo "  5. Test Forge — Close Session: press ⌃⌥⌘C while in a Claude Code session"
