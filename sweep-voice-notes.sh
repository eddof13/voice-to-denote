#!/usr/bin/env bash
# Processes any audio files sitting in ~/voice_notes.
# Run on KM Engine startup and periodically to catch files that arrived while KM was off.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

VOICE_DIR="$HOME/voice_notes"
LOG="$HOME/.voice-to-denote.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

count=0
for f in "$VOICE_DIR"/*; do
  [[ ! -f "$f" ]] && continue
  case "${f##*.}" in
    m4a|mp3|wav|aiff|aac|ogg|flac|opus)
      log "Sweep found: $(basename "$f")"
      ~/bin/voice-to-denote.sh "$f" || log "ERROR: Failed processing $(basename "$f")"
      count=$((count + 1))
      ;;
  esac
done

[[ $count -gt 0 ]] && log "Sweep complete: $count file(s) processed"
