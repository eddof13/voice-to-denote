#!/usr/bin/env bash
# Pick an active Forge project, open Terminal running claude with the
# session-start prompt, and set the KM variable ForgeProject directly.
set -euo pipefail

FORGE_DIR="$HOME/forge/Active Projects"

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

PROJECT_PATH="$FORGE_DIR/$CHOICE"
SESSION_PROMPT="Project: ${CHOICE}. Read STATUS. Where did we leave off?"

# Set the KM variable directly — no stdout, no results window
osascript -e "tell application \"Keyboard Maestro Engine\" to setvariable \"ForgeProject\" to \"${CHOICE}\"" > /dev/null 2>&1

# Open Terminal running claude with the session-start prompt
osascript > /dev/null 2>&1 << APPLESCRIPT
tell application "Terminal"
  do script "cd '${PROJECT_PATH}' && claude '${SESSION_PROMPT}'"
  activate
end tell
APPLESCRIPT
