#!/usr/bin/env bash
# setup.sh — Register the hook in Claude Code settings (local or global)
#
# idempotent — running twice must not duplicate or corrupt the hook entry.
# Must merge cleanly into any valid existing settings.json layout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/scripts/annotate-pre.sh"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}Colorful Bash for Claude Code — Setup${RESET}"
echo -e "========================================"
echo ""

# --- Step 1: Verify the hook script exists ---

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo -e "${RED}Error:${RESET} Could not find annotate-pre.sh at:"
  echo "  $HOOK_SCRIPT"
  echo "Make sure you're running this from the project directory."
  exit 1
fi

# Make scripts executable
chmod +x "$HOOK_SCRIPT"
chmod +x "$SCRIPT_DIR/scripts/font-check.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts/install-font.sh" 2>/dev/null || true

# --- Step 2: Choose install scope ---

echo -e "Where would you like to install the hook?"
echo ""
echo -e "  ${CYAN}1)${RESET} Local  — Only active when Claude Code is working in this folder"
echo -e "     File: ${YELLOW}.claude/settings.local.json${RESET} (inside this project)"
echo ""
echo -e "  ${CYAN}2)${RESET} Global — Active in every project you open with Claude Code"
echo -e "     File: ${YELLOW}~/.claude/settings.json${RESET}"
echo ""
echo -e "  ${YELLOW}Note:${RESET} Option 2 modifies a file outside this project directory."
echo -e "  Specifically: ${YELLOW}$(echo ~/.claude/settings.json)${RESET}"
echo ""

while true; do
  read -r -p "Choose (1 or 2): " choice
  case "$choice" in
    1) SCOPE="local"; break ;;
    2) SCOPE="global"; break ;;
    *) echo "Please enter 1 or 2." ;;
  esac
done

echo ""

# --- Step 3: Determine settings file path ---

if [[ "$SCOPE" == "local" ]]; then
  SETTINGS_DIR="$SCRIPT_DIR/.claude"
  SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
  echo -e "Installing ${CYAN}locally${RESET} to: ${YELLOW}${SETTINGS_FILE}${RESET}"
else
  SETTINGS_DIR="$HOME/.claude"
  SETTINGS_FILE="$SETTINGS_DIR/settings.json"
  echo -e "${YELLOW}Note:${RESET} This will modify a file outside this project:"
  echo -e "  ${YELLOW}${SETTINGS_FILE}${RESET}"
  echo ""
  read -r -p "Continue? (y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Setup cancelled."
    exit 0
  fi
fi

echo ""

# --- Step 4: Create or update settings file ---

# Ensure the directory exists
mkdir -p "$SETTINGS_DIR"

# The hook command to register — use absolute path for reliability
HOOK_CMD="bash $HOOK_SCRIPT"

# The hook entry for user settings (no "hooks" wrapper — that's for plugin hooks.json)
HOOK_JSON_ENTRY="{\"matcher\": \"Bash\", \"type\": \"command\", \"command\": \"$HOOK_CMD\"}"

if [[ -f "$SETTINGS_FILE" ]]; then
  # Settings file exists — check if hook is already registered
  if grep -q "$HOOK_SCRIPT" "$SETTINGS_FILE" 2>/dev/null; then
    echo -e "${GREEN}Hook is already registered${RESET} in $SETTINGS_FILE"
    echo "Nothing to do — you're all set!"
    echo ""
    exit 0
  fi

  # File exists but hook is not registered — we need to merge
  existing=$(cat "$SETTINGS_FILE")

  if echo "$existing" | grep -q '"PreToolUse"'; then
    # Append to existing PreToolUse array
    updated=$(echo "$existing" | sed "s|\"PreToolUse\"[[:space:]]*:[[:space:]]*\[|\"PreToolUse\": [$HOOK_JSON_ENTRY,|")
    echo "$updated" > "$SETTINGS_FILE"
  else
    # No PreToolUse — add it before closing }
    updated=$(echo "$existing" | sed '$ s/}$//' | sed '$ s/[[:space:]]*$//')
    if echo "$updated" | grep -q '"'; then
      updated="${updated},
  \"PreToolUse\": [
    $HOOK_JSON_ENTRY
  ]
}"
    else
      updated="{
  \"PreToolUse\": [
    $HOOK_JSON_ENTRY
  ]
}"
    fi
    echo "$updated" > "$SETTINGS_FILE"
  fi
else
  # No settings file — create one
  cat > "$SETTINGS_FILE" << JSONEOF
{
  "PreToolUse": [
    {"matcher": "Bash", "type": "command", "command": "$HOOK_CMD"}
  ]
}
JSONEOF
fi

# Validate the result is parseable JSON
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c "import json; json.load(open('$SETTINGS_FILE'))" 2>/dev/null; then
    echo -e "${RED}Warning:${RESET} The resulting settings file may not be valid JSON."
    echo -e "Please check: ${YELLOW}${SETTINGS_FILE}${RESET}"
    echo ""
  fi
elif command -v node >/dev/null 2>&1; then
  if ! node -e "JSON.parse(require('fs').readFileSync('$SETTINGS_FILE','utf8'))" 2>/dev/null; then
    echo -e "${RED}Warning:${RESET} The resulting settings file may not be valid JSON."
    echo -e "Please check: ${YELLOW}${SETTINGS_FILE}${RESET}"
    echo ""
  fi
fi

echo -e "${GREEN}Hook registered successfully!${RESET}"
echo ""
echo -e "What was changed:"
echo -e "  ${YELLOW}${SETTINGS_FILE}${RESET}"
echo -e "  Added a PreToolUse hook pointing to:"
echo -e "  ${CYAN}${HOOK_SCRIPT}${RESET}"
echo ""
echo -e "Now, every time Claude Code runs a Bash command, you'll see"
echo -e "colorful emoji annotations showing what each command does."
echo ""
echo -e "To remove the hook later, run: ${CYAN}./uninstall.sh${RESET}"
echo ""
