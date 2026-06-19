#!/usr/bin/env bash
# Pick an active Forge project, open Terminal running claude there,
# and output the project name so the KM macro can copy the session-start text.
set -euo pipefail

FORGE_DIR="$HOME/forge/Active Projects"

# Build project list — handles spaces in folder names
PROJECTS=()
while IFS= read -r -d '' dir; do
  PROJECTS+=("$(basename "$dir")")
done < <(find "$FORGE_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z || true)

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  osascript -e 'display alert "No active projects in ~/forge/Active Projects"'
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

# Open new Terminal window running claude at the project path
PROJECT_PATH="$FORGE_DIR/$CHOICE"
osascript -e "tell application \"Terminal\" to do script \"cd '$PROJECT_PATH' && claude\""
osascript -e "tell application \"Terminal\" to activate"

# Output chosen name for KM to use in the session-start text
echo "$CHOICE"
