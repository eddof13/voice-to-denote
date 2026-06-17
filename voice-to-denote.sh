#!/usr/bin/env bash
set -euo pipefail

AUDIO_FILE="${1:-$KMVAR_TriggerValue}"

# Only process audio files
case "${AUDIO_FILE##*.}" in
  m4a|mp3|wav|aiff|aac|ogg|flac|opus) ;;
  *) exit 0 ;;
esac

NOTES_DIR="$HOME/notes"
TODO_FILE="$HOME/notes/todo.org"
UPCOMING_FILE="$HOME/notes/upcoming.org"
CLAUDE="/opt/homebrew/bin/claude"
JQ="/usr/bin/jq"
LOG="$HOME/.voice-to-denote.log"
TODAY=$(date +%Y-%m-%d)

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "Processing: $(basename "$AUDIO_FILE")"

# Transcribe
TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

if ! whisper "$AUDIO_FILE" --output_format txt --output_dir "$TMPWORK" --model base.en 2>/dev/null; then
  log "ERROR: Whisper failed on $(basename "$AUDIO_FILE")"
  exit 1
fi

TRANSCRIPT_FILE="$TMPWORK/$(basename "${AUDIO_FILE%.*}").txt"
if [[ ! -f "$TRANSCRIPT_FILE" ]]; then
  log "ERROR: Transcript file not found for $(basename "$AUDIO_FILE")"
  exit 1
fi
TRANSCRIPT=$(cat "$TRANSCRIPT_FILE")

# Build prompt — static part single-quoted, today's date and transcript appended
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << STATIC
Classify and structure a voice transcript into one of three types: note, task, or reminder.

Classification rules:
- task: explicit prefix "TODO" or "task" OR sounds like something to do/investigate/follow up on
- reminder: explicit prefix "REMIND ME" or "reminder" OR mentions a specific date/time with an action
- note: everything else — thoughts, ideas, reference info, observations

Respond with valid JSON only — no markdown fences, no explanation, nothing else.

Schema:
{
  "type": "note" | "task" | "reminder",
  "title": "3-7 word plain English title, no punctuation",
  "tags": ["tag1", "tag2"],
  "content": "cleaned up well-structured prose from the transcript",
  "scheduled_date": "YYYY-MM-DD or null — only for reminders, infer from transcript"
}

Rules:
- tags: 1-3 lowercase single words
- title: no punctuation, plain English
- content: remove filler words, organize ideas clearly, preserve all meaning
- scheduled_date: infer from relative references using today's date $TODAY

Transcript:
STATIC
printf '%s' "$TRANSCRIPT" >> "$PROMPT_FILE"

# Call Claude — fall back to raw note on invalid JSON
RESPONSE=$("$CLAUDE" -p "$(cat "$PROMPT_FILE")" 2>/dev/null) || true
rm "$PROMPT_FILE"

if ! "$JQ" . <<< "$RESPONSE" >/dev/null 2>&1; then
  log "WARNING: Claude returned invalid JSON, saving raw transcript"
  TIMESTAMP=$(date +%Y%m%dT%H%M%S)
  FILENAME="${TIMESTAMP}--voice-note-raw__unprocessed.org"
  printf '#+title: Voice Note (unprocessed)\n#+date: [%s]\n#+filetags: :unprocessed:\n#+identifier: %s\n\n%s\n' \
    "$(date '+%Y-%m-%d %a %H:%M')" "$TIMESTAMP" "$TRANSCRIPT" \
    > "$NOTES_DIR/$FILENAME"
  log "Fallback note: $NOTES_DIR/$FILENAME"
  echo "Fallback note: $NOTES_DIR/$FILENAME"
  osascript -e "tell application \"Finder\" to delete POSIX file \"$(realpath "$AUDIO_FILE")\""
  exit 0
fi

# Parse response
TYPE=$("$JQ" -r '.type' <<< "$RESPONSE")
TITLE=$("$JQ" -r '.title' <<< "$RESPONSE")
CONTENT=$("$JQ" -r '.content' <<< "$RESPONSE")

# Move audio to Trash
osascript -e "tell application \"Finder\" to delete POSIX file \"$(realpath "$AUDIO_FILE")\""

if [[ "$TYPE" == "note" ]]; then
  TAGS_SLUG=$("$JQ" -r '.tags | join("_")' <<< "$RESPONSE")
  FILETAGS=$("$JQ" -r '[""] + .tags + [""] | join(":")' <<< "$RESPONSE")
  TIMESTAMP=$(date +%Y%m%dT%H%M%S)
  SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  FILENAME="${TIMESTAMP}--${SLUG}__${TAGS_SLUG}.org"

  printf '#+title: %s\n#+date: [%s]\n#+filetags: %s\n#+identifier: %s\n\n%s\n' \
    "$TITLE" "$(date '+%Y-%m-%d %a %H:%M')" "$FILETAGS" "$TIMESTAMP" "$CONTENT" \
    > "$NOTES_DIR/$FILENAME"

  log "Note created: $FILENAME"
  echo "Note created: $NOTES_DIR/$FILENAME"

elif [[ "$TYPE" == "task" ]]; then
  touch "$TODO_FILE"
  printf '\n* TODO %s\n%s\n' "$TITLE" "$CONTENT" >> "$TODO_FILE"
  log "Task added to todo.org: $TITLE"
  echo "Task added: $TODO_FILE"

elif [[ "$TYPE" == "reminder" ]]; then
  SCHEDULED=$("$JQ" -r '.scheduled_date // empty' <<< "$RESPONSE")
  touch "$UPCOMING_FILE"
  if [[ -n "$SCHEDULED" ]]; then
    DAY=$(date -j -f "%Y-%m-%d" "$SCHEDULED" "+%a" 2>/dev/null || echo "")
    printf '\n* TODO %s\nSCHEDULED: <%s %s>\n%s\n' "$TITLE" "$SCHEDULED" "$DAY" "$CONTENT" >> "$UPCOMING_FILE"
  else
    printf '\n* TODO %s\n%s\n' "$TITLE" "$CONTENT" >> "$UPCOMING_FILE"
  fi
  log "Reminder added to upcoming.org: $TITLE"
  echo "Reminder added: $UPCOMING_FILE"
fi
