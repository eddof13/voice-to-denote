#!/usr/bin/env bash
# Processes new audio files in ~/voice_notes and retries stuck files in .processing.
# Run on KM Engine launch and periodically to catch files that arrived while KM was off.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

VOICE_DIR="$HOME/voice_notes"
PROCESSING_DIR="$HOME/voice_notes/.processing"
LOG="$HOME/.voice-to-denote.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

mkdir -p "$PROCESSING_DIR"
count=0

# Process new files in root — voice-to-denote.sh claims each one atomically
for f in "$VOICE_DIR"/*; do
  [[ ! -f "$f" ]] && continue
  case "${f##*.}" in
    m4a|mp3|wav|aiff|aac|ogg|flac|opus)
      ~/bin/voice-to-denote.sh "$f" || log "ERROR: Failed processing $(basename "$f")"
      count=$((count + 1))
      ;;
  esac
done

# Retry stuck files in .processing older than 10 minutes.
# Atomically move them back to root so voice-to-denote.sh can re-claim them cleanly.
# If two sweepers run concurrently, only one mv will succeed per file.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  RETRY="$VOICE_DIR/retry_$(basename "$f")"
  if mv "$f" "$RETRY" 2>/dev/null; then
    log "Retrying stuck file: $(basename "$f")"
    ~/bin/voice-to-denote.sh "$RETRY" || log "ERROR: Retry failed for $(basename "$f")"
    count=$((count + 1))
  fi
done < <(find "$PROCESSING_DIR" -maxdepth 1 -type f -mmin +10 2>/dev/null)

[[ $count -gt 0 ]] && log "Sweep complete: $count file(s) processed"
