#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
PRE_HOOK="$SCRIPT_DIR/scripts/annotate-pre.sh"

echo "Installing Bash Annotator..."

# 1. Ensure directories exist
mkdir -p "$CLAUDE_DIR"

# 2. Make scripts executable
chmod +x "$SCRIPT_DIR/scripts/annotate-pre.sh"
chmod +x "$SCRIPT_DIR/scripts/font-check.sh"

# 3. Register hook in settings.json
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  cat > "$CLAUDE_SETTINGS" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "$PRE_HOOK"
      }
    ]
  }
}
EOF
  echo "Created $CLAUDE_SETTINGS with hook."
else
  if grep -q "annotate-pre.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "Hook already registered."
  else
    echo ""
    echo "Add the following to your $CLAUDE_SETTINGS under \"hooks\":"
    echo ""
    echo '  "PreToolUse": ['
    echo "    {\"matcher\": \"Bash\", \"command\": \"$PRE_HOOK\"}"
    echo '  ]'
    echo ""
  fi
fi

# 4. Font check
echo ""
source "$SCRIPT_DIR/scripts/font-check.sh"
check_fonts

echo ""
echo "Bash Annotator installed. Restart Claude Code to activate."
