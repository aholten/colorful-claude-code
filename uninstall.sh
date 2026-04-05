#!/usr/bin/env bash
# uninstall.sh — Remove the hook from Claude Code settings
#
# fully remove the hook entry without leaving orphaned JSON.
# Must not delete plugin files — only the hook reference in settings.

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
echo -e "${BOLD}Colorful Bash for Claude Code — Uninstall${RESET}"
echo -e "============================================"
echo ""

# --- Check both locations for the hook ---

LOCAL_SETTINGS="$SCRIPT_DIR/.claude/settings.local.json"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

found_local=0
found_global=0

if [[ -f "$LOCAL_SETTINGS" ]] && grep -q "$HOOK_SCRIPT" "$LOCAL_SETTINGS" 2>/dev/null; then
  found_local=1
fi

if [[ -f "$GLOBAL_SETTINGS" ]] && grep -q "$HOOK_SCRIPT" "$GLOBAL_SETTINGS" 2>/dev/null; then
  found_global=1
fi

if [[ $found_local -eq 0 && $found_global -eq 0 ]]; then
  echo -e "${YELLOW}No hook registration found.${RESET}"
  echo "The Colorful Bash hook doesn't appear to be installed."
  echo ""
  echo "Checked:"
  echo "  $LOCAL_SETTINGS"
  echo "  $GLOBAL_SETTINGS"
  echo ""
  exit 0
fi

# --- Show what was found and confirm ---

echo "Found hook registration in:"
if [[ $found_local -eq 1 ]]; then
  echo -e "  ${YELLOW}${LOCAL_SETTINGS}${RESET} (local)"
fi
if [[ $found_global -eq 1 ]]; then
  echo -e "  ${YELLOW}${GLOBAL_SETTINGS}${RESET} (global)"
fi
echo ""

read -r -p "Remove the hook? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Uninstall cancelled."
  exit 0
fi

echo ""

# --- Remove hook from settings files ---

_remove_hook() {
  local settings_file="$1"
  local label="$2"

  if [[ ! -f "$settings_file" ]]; then
    return
  fi

  # Remove the line containing our hook script path
  # This handles the JSON entry regardless of formatting
  local escaped_path
  escaped_path=$(echo "$HOOK_SCRIPT" | sed 's/[\/&]/\\&/g')

  # Remove lines containing the hook script reference
  local temp_file="${settings_file}.tmp"
  grep -v "$HOOK_SCRIPT" "$settings_file" > "$temp_file" 2>/dev/null || true

  # Clean up trailing commas that may be left behind
  # Remove lines that are just a comma
  sed -i 's/,\([[:space:]]*\]\)/\1/g' "$temp_file" 2>/dev/null || true
  sed -i 's/,\([[:space:]]*\}\)/\1/g' "$temp_file" 2>/dev/null || true

  # Check if the PreToolUse array is now empty [], and remove it if so
  if grep -q '"PreToolUse"[[:space:]]*:[[:space:]]*\[\]' "$temp_file" 2>/dev/null; then
    grep -v '"PreToolUse"' "$temp_file" > "${temp_file}.2" 2>/dev/null || true
    mv "${temp_file}.2" "$temp_file"
    # Clean up trailing commas again after removal
    sed -i 's/,\([[:space:]]*\]\)/\1/g' "$temp_file" 2>/dev/null || true
    sed -i 's/,\([[:space:]]*\}\)/\1/g' "$temp_file" 2>/dev/null || true
  fi

  mv "$temp_file" "$settings_file"

  echo -e "${GREEN}Removed${RESET} hook from ${label}: ${YELLOW}${settings_file}${RESET}"
}

if [[ $found_local -eq 1 ]]; then
  _remove_hook "$LOCAL_SETTINGS" "local"
fi

if [[ $found_global -eq 1 ]]; then
  _remove_hook "$GLOBAL_SETTINGS" "global"
fi

echo ""
echo -e "The hook has been removed. Claude Code will no longer annotate"
echo -e "Bash commands with emoji and colors."
echo ""
echo -e "The plugin files are still on disk. To completely remove them:"
echo -e "  ${CYAN}rm -rf ${SCRIPT_DIR}${RESET}"
echo ""
echo -e "To reinstall later: ${CYAN}./setup.sh${RESET}"
echo ""
