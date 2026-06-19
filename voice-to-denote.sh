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
PROCESSING_DIR="$HOME/voice_notes/.processing"
PROCESSED_DIR="$HOME/voice_notes/processed"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Atomically claim the file by moving it to .processing.
# If it's already in .processing (came from sweeper retry), process it directly.
# If mv fails, another process already claimed it — exit cleanly.
mkdir -p "$PROCESSING_DIR"
if [[ "$(dirname "$(realpath "$AUDIO_FILE")")" != "$(realpath "$PROCESSING_DIR")" ]]; then
  CLAIMED="$PROCESSING_DIR/$(basename "$AUDIO_FILE")"
  if ! mv "$AUDIO_FILE" "$CLAIMED" 2>/dev/null; then
    log "Skipping $(basename "$AUDIO_FILE") — already claimed by another process"
    exit 0
  fi
  AUDIO_FILE="$CLAIMED"
fi

log "Processing: $(basename "$AUDIO_FILE")"

# Transcribe — on failure, leave file in .processing for sweeper to retry
TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

if ! whisper "$AUDIO_FILE" --output_format txt --output_dir "$TMPWORK" --model base.en 2>/dev/null; then
  log "ERROR: Whisper failed — $(basename "$AUDIO_FILE") left in .processing for retry"
  exit 1
fi

TRANSCRIPT_FILE="$TMPWORK/$(basename "${AUDIO_FILE%.*}").txt"
if [[ ! -f "$TRANSCRIPT_FILE" ]]; then
  log "ERROR: Transcript file not found — $(basename "$AUDIO_FILE") left in .processing for retry"
  exit 1
fi
TRANSCRIPT=$(cat "$TRANSCRIPT_FILE")

# Build prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << STATIC
Classify and structure a voice transcript into one of four types: note, task, reminder, or project.

Classification rules:
- task: explicit prefix "TODO" or "task" OR sounds like something to do/investigate/follow up on
- reminder: explicit prefix "REMIND ME" or "reminder" OR mentions a specific date/time with an action
- project: speaker is explicitly starting or naming a new project ("new project", "start a project", "I'm building", "create a project for")
- note: everything else — thoughts, ideas, reference info, observations

Respond with valid JSON only — no markdown fences, no explanation, nothing else.

Schema:
{
  "type": "note" | "task" | "reminder" | "project",
  "title": "3-7 word plain English title, no punctuation",
  "tags": ["tag1", "tag2"],
  "content": "cleaned up well-structured prose from the transcript",
  "scheduled_date": "YYYY-MM-DD or null — only for reminders, infer from transcript",
  "project_name": "2-5 word title case name for the project folder, only when type is project, otherwise null"
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
  log "WARNING: Claude returned invalid JSON — saving raw transcript"
  TIMESTAMP=$(date +%Y%m%dT%H%M%S)
  FILENAME="${TIMESTAMP}--voice-note-raw__unprocessed.org"
  printf '#+title: Voice Note (unprocessed)\n#+date: [%s]\n#+filetags: :unprocessed:\n#+identifier: %s\n\n%s\n' \
    "$(date '+%Y-%m-%d %a %H:%M')" "$TIMESTAMP" "$TRANSCRIPT" \
    > "$NOTES_DIR/$FILENAME"
  log "Fallback note: $NOTES_DIR/$FILENAME"
  echo "Fallback note: $NOTES_DIR/$FILENAME"
  mkdir -p "$PROCESSED_DIR" && mv "$AUDIO_FILE" "$PROCESSED_DIR/"
  exit 0
fi

# Parse response
TYPE=$("$JQ" -r '.type' <<< "$RESPONSE")
TITLE=$("$JQ" -r '.title' <<< "$RESPONSE")
CONTENT=$("$JQ" -r '.content' <<< "$RESPONSE")

# Write output FIRST — trash audio only after successful write
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
  log "Task added: $TITLE"
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
  log "Reminder added: $TITLE"
  echo "Reminder added: $UPCOMING_FILE"

elif [[ "$TYPE" == "project" ]]; then
  PROJECT_NAME=$("$JQ" -r '.project_name // empty' <<< "$RESPONSE")
  [[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$TITLE"
  FORGE_DIR="$HOME/forge/Active Projects/$PROJECT_NAME"
  mkdir -p "$FORGE_DIR/Drafts" "$FORGE_DIR/Assets" "$FORGE_DIR/Outputs"

  {
    printf '# %s\n\n%s\n\n' "$PROJECT_NAME" "$CONTENT"
    cat << 'TMPL'
## Where things live

| File / Folder | What's in it |
|---|---|
| `STATUS.md` | Current state — what's in progress, what's blocked, what's next |
| `Steps.md` | The plan — ordered tasks and milestones |
| `Notes.md` | Decisions, constraints, references, context that informs the work |
| `Drafts/` | Work in progress |
| `Assets/` | Source material |
| `Outputs/` | Final deliverables |

## Which file to read first

- **Starting a new session** → `STATUS.md`, then `Steps.md`
- **Writing or editing content** → `Notes.md`, then `Drafts/`
- **Looking for source material** → `Assets/`
- **Checking what's done** → `Outputs/`

## How to work here

- Read `STATUS.md` before asking what to do next — it should answer that.
- Save finished work to `Outputs/`, not `Drafts/`.
- Log significant decisions in `Notes.md` so they survive across sessions.
- Update `STATUS.md` at the end of each session.
TMPL
  } > "$FORGE_DIR/CLAUDE.md"

  printf '# Status\n\n**Last updated:** %s\n\n## In progress\n_Nothing yet._\n\n## Blocked\n_Nothing._\n\n## Up next\n_See Steps.md._\n\n## Recently completed\n_Nothing yet._\n' \
    "$(date +%Y-%m-%d)" > "$FORGE_DIR/STATUS.md"

  printf '# Plan\n\nSteps in order. Check off as done.\n\n_Add steps here._\n' > "$FORGE_DIR/Steps.md"

  printf '# Notes\n\nDecisions, constraints, and context that inform the work.\n\n## Voice note (%s)\n%s\n' \
    "$(date '+%Y-%m-%d')" "$CONTENT" > "$FORGE_DIR/Notes.md"

  log "Project scaffolded: $FORGE_DIR"
  echo "Project created: $PROJECT_NAME"
fi

mkdir -p "$PROCESSED_DIR" && mv "$AUDIO_FILE" "$PROCESSED_DIR/"
