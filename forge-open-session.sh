#!/usr/bin/env bash
# Pick an active Forge project, open Terminal running the chosen agent (claude or
# grok) with the session-start prompt, and set the KM variable ForgeProject.
#
# Agent selection: FORGE_AGENT=auto|claude|grok (default auto).
# auto = first available of claude, then grok.
set -euo pipefail

FORGE_DIR="$HOME/forge/Active Projects"
FORGE_AGENT="${FORGE_AGENT:-auto}"

export PATH="$HOME/.local/bin:$HOME/.grok/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

resolve_agent() {
  local prefer
  prefer=$(echo "${FORGE_AGENT:-auto}" | tr '[:upper:]' '[:lower:]')
  local claude_bin grok_bin
  claude_bin=$(command -v claude 2>/dev/null || true)
  grok_bin=$(command -v grok 2>/dev/null || true)

  case "$prefer" in
    claude)
      [[ -n "$claude_bin" ]] || { echo "claude CLI not found" >&2; return 1; }
      echo "claude|$claude_bin"
      ;;
    grok)
      [[ -n "$grok_bin" ]] || { echo "grok CLI not found" >&2; return 1; }
      echo "grok|$grok_bin"
      ;;
    auto|"")
      if [[ -n "$claude_bin" ]]; then
        echo "claude|$claude_bin"
      elif [[ -n "$grok_bin" ]]; then
        echo "grok|$grok_bin"
      else
        echo "No agent CLI found (install claude and/or grok)" >&2
        return 1
      fi
      ;;
    *)
      echo "Unknown FORGE_AGENT='$prefer' (use auto|claude|grok)" >&2
      return 1
      ;;
  esac
}

# Build project list — handles spaces in folder names
PROJECTS=()
while IFS= read -r -d '' dir; do
  PROJECTS+=("$(basename "$dir")")
done < <(find "$FORGE_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z || true)

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  osascript -e 'display alert "No active projects in ~/forge/Active Projects"' > /dev/null 2>&1
  exit 1
fi

# Build quoted AppleScript list
OALIST=""
for p in "${PROJECTS[@]}"; do
  OALIST="${OALIST}\"${p}\","
done
OALIST="${OALIST%,}"

# Show chooser — returns "false" if cancelled
CHOICE=$(osascript -e "choose from list {$OALIST} with prompt \"Open a forge session:\" without multiple selections allowed" 2>/dev/null)

if [[ "$CHOICE" == "false" ]] || [[ -z "$CHOICE" ]]; then
  exit 1
fi

if ! AGENT_SPEC=$(resolve_agent); then
  osascript -e "display alert \"Forge agent error\" message \"$(resolve_agent 2>&1 || true)\"" > /dev/null 2>&1 || true
  exit 1
fi
AGENT_NAME="${AGENT_SPEC%%|*}"
AGENT_BIN="${AGENT_SPEC#*|}"

PROJECT_PATH="$FORGE_DIR/$CHOICE"
# Agent-agnostic session start — AGENTS.md only (no CLAUDE.md / no symlinks).
SESSION_PROMPT="Project: ${CHOICE}. Read AGENTS.md, then STATUS. Where did we leave off?"

# Set the KM variable directly — no stdout, no results window
osascript -e "tell application \"Keyboard Maestro Engine\" to setvariable \"ForgeProject\" to \"${CHOICE}\"" > /dev/null 2>&1

# Escape single quotes for AppleScript string
ESC_PATH="${PROJECT_PATH//\'/\'\\\'\'}"
ESC_PROMPT="${SESSION_PROMPT//\'/\'\\\'\'}"
ESC_BIN="${AGENT_BIN//\'/\'\\\'\'}"

osascript > /dev/null 2>&1 << APPLESCRIPT
tell application "Terminal"
  do script "cd '${ESC_PATH}' && '${ESC_BIN}' '${ESC_PROMPT}'"
  activate
end tell
APPLESCRIPT
