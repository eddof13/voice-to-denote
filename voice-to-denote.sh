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
JQ="${JQ:-/usr/bin/jq}"
LOG="$HOME/.voice-to-denote.log"
TODAY=$(date +%Y-%m-%d)
PROCESSING_DIR="$HOME/voice_notes/.processing"
PROCESSED_DIR="$HOME/voice_notes/processed"

# LLM backend: auto | claude | grok
# Override with VOICE_TO_DENOTE_LLM. auto = first available (claude, then grok).
VOICE_TO_DENOTE_LLM="${VOICE_TO_DENOTE_LLM:-auto}"

export PATH="$HOME/.local/bin:$HOME/.grok/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

find_bin() {
  local name="$1"
  command -v "$name" 2>/dev/null || true
}

resolve_llm() {
  local prefer="${VOICE_TO_DENOTE_LLM:-auto}"
  prefer=$(echo "$prefer" | tr '[:upper:]' '[:lower:]')
  local claude_bin grok_bin
  claude_bin=$(find_bin claude)
  grok_bin=$(find_bin grok)

  case "$prefer" in
    claude)
      if [[ -z "$claude_bin" ]]; then
        log "ERROR: VOICE_TO_DENOTE_LLM=claude but claude CLI not found"
        return 1
      fi
      echo "claude|$claude_bin"
      ;;
    grok)
      if [[ -z "$grok_bin" ]]; then
        log "ERROR: VOICE_TO_DENOTE_LLM=grok but grok CLI not found"
        return 1
      fi
      echo "grok|$grok_bin"
      ;;
    auto|"")
      if [[ -n "$claude_bin" ]]; then
        echo "claude|$claude_bin"
      elif [[ -n "$grok_bin" ]]; then
        echo "grok|$grok_bin"
      else
        log "ERROR: no LLM CLI found (install claude and/or grok)"
        return 1
      fi
      ;;
    *)
      log "ERROR: unknown VOICE_TO_DENOTE_LLM='$prefer' (use auto|claude|grok)"
      return 1
      ;;
  esac
}

# Call the selected LLM with a prompt file; print model text to stdout.
# Both backends are used headless / single-turn — no tools needed for classify.
call_llm() {
  local backend="$1"
  local bin="$2"
  local prompt_file="$3"

  case "$backend" in
    claude)
      # -p/--print: non-interactive; prompt as argument
      "$bin" -p "$(cat "$prompt_file")" 2>/dev/null
      ;;
    grok)
      # --prompt-file: headless single-turn; plain text to stdout
      "$bin" \
        --prompt-file "$prompt_file" \
        --output-format plain \
        --no-subagents \
        --disable-web-search \
        --max-turns 1 \
        2>/dev/null
      ;;
    *)
      log "ERROR: unsupported backend '$backend'"
      return 1
      ;;
  esac
}

# If the model wraps JSON in fences or prose, pull out the first JSON object.
extract_json() {
  local raw="$1"
  if "$JQ" . <<< "$raw" >/dev/null 2>&1; then
    printf '%s' "$raw"
    return 0
  fi
  # Strip ```json ... ``` or ``` ... ```
  local stripped
  stripped=$(printf '%s' "$raw" | sed -e 's/^```[a-zA-Z]*//' -e 's/```$//' | sed '/^```/d')
  if "$JQ" . <<< "$stripped" >/dev/null 2>&1; then
    printf '%s' "$stripped"
    return 0
  fi
  # Greedy first {...} block
  local obj
  obj=$(printf '%s' "$raw" | python3 -c '
import sys, re, json
text = sys.stdin.read()
# find outermost object by brace scan
start = text.find("{")
if start < 0:
    sys.exit(1)
depth = 0
for i, ch in enumerate(text[start:], start):
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            chunk = text[start:i+1]
            json.loads(chunk)
            print(chunk)
            sys.exit(0)
sys.exit(1)
' 2>/dev/null) || return 1
  printf '%s' "$obj"
}

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

if ! LLM_SPEC=$(resolve_llm); then
  log "ERROR: LLM resolve failed — $(basename "$AUDIO_FILE") left in .processing for retry"
  exit 1
fi
LLM_BACKEND="${LLM_SPEC%%|*}"
LLM_BIN="${LLM_SPEC#*|}"
log "Using LLM backend: $LLM_BACKEND ($LLM_BIN)"

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

# Call LLM — fall back to raw note on invalid JSON
RAW_RESPONSE=$(call_llm "$LLM_BACKEND" "$LLM_BIN" "$PROMPT_FILE") || true
rm -f "$PROMPT_FILE"

RESPONSE=$(extract_json "$RAW_RESPONSE" 2>/dev/null) || RESPONSE=""

if [[ -z "$RESPONSE" ]] || ! "$JQ" . <<< "$RESPONSE" >/dev/null 2>&1; then
  log "WARNING: $LLM_BACKEND returned invalid JSON — saving raw transcript"
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

  log "Note created: $FILENAME (via $LLM_BACKEND)"
  echo "Note created: $NOTES_DIR/$FILENAME"

elif [[ "$TYPE" == "task" ]]; then
  touch "$TODO_FILE"
  printf '\n* TODO %s\n%s\n' "$TITLE" "$CONTENT" >> "$TODO_FILE"
  log "Task added: $TITLE (via $LLM_BACKEND)"
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
  log "Reminder added: $TITLE (via $LLM_BACKEND)"
  echo "Reminder added: $UPCOMING_FILE"

elif [[ "$TYPE" == "project" ]]; then
  PROJECT_NAME=$("$JQ" -r '.project_name // empty' <<< "$RESPONSE")
  [[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$TITLE"
  FORGE_DIR="$HOME/forge/Active Projects/$PROJECT_NAME"
  mkdir -p "$FORGE_DIR/Drafts" "$FORGE_DIR/Assets" "$FORGE_DIR/Outputs"

  # Agent-agnostic pointer: AGENTS.md only (no CLAUDE.md, no symlinks — MegaSync).
  {
    printf '# %s\n\n%s\n\n' "$PROJECT_NAME" "$CONTENT"
    cat << 'TMPL'
## Which AI is reading this

This pointer file is **agent-agnostic**. Same contract for Claude, Grok, or another
agent. The sole pointer filename is `AGENTS.md` — no `CLAUDE.md`, no symlinks
(MegaSync cannot sync them). Session start always reads this file by name.

## Where things live

| File / Folder | What's in it |
|---|---|
| `AGENTS.md` | This pointer — first thing to read every session |
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
- Log significant decisions in `Notes.md` (newest at top) so they survive across sessions.
- Update `STATUS.md` at the end of each session.
- Do not assume memory between sessions or across models — the files are the only shared memory.
TMPL
  } > "$FORGE_DIR/AGENTS.md"

  printf '# Status\n\n**Last updated:** %s\n\n## In progress\n_Nothing yet._\n\n## Blocked\n_Nothing._\n\n## Up next\n_See Steps.md._\n\n## Recently completed\n_Nothing yet._\n' \
    "$(date +%Y-%m-%d)" > "$FORGE_DIR/STATUS.md"

  printf '# Plan\n\nSteps in order. Check off as done.\n\n_Add steps here._\n' > "$FORGE_DIR/Steps.md"

  printf '# Notes\n\nDecisions, constraints, and context that inform the work. Newest at top.\n\n## Voice note (%s)\n%s\n' \
    "$(date '+%Y-%m-%d')" "$CONTENT" > "$FORGE_DIR/Notes.md"

  log "Project scaffolded: $FORGE_DIR (via $LLM_BACKEND)"
  echo "Project created: $PROJECT_NAME"
fi

mkdir -p "$PROCESSED_DIR" && mv "$AUDIO_FILE" "$PROCESSED_DIR/"
