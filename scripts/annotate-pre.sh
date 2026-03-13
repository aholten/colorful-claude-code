#!/usr/bin/env bash
# annotate-pre.sh — PreToolUse hook for Claude Code
# Reads JSON from stdin, annotates Bash commands, emits JSON to stdout
#
# This is the main entry point registered as a Claude Code hook.
# Input:  {"tool_name":"Bash","input":{"command":"..."}, ...}
# Output: {"systemMessage": "<annotated command>"} or empty for non-Bash tools

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/parser.sh"
source "$SCRIPT_DIR/renderer.sh"

# Read all of stdin
input=$(cat)

# Extract tool_name — only annotate Bash tool calls
tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"//')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# Extract the command field from input.command
# Handles: "input":{"command":"..."} with possible whitespace
command_str=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')

# Empty command — no-op
if [[ -z "$command_str" ]]; then
  exit 0
fi

# Unescape JSON string escapes that grep extracted literally
# \" → "  \\ → \  \n → newline  \t → tab
command_str=$(printf '%b' "$command_str" 2>/dev/null | sed 's/\\"/"/g') || command_str="$command_str"

# Parse the command into tokens
tokens=$(parse_command "$command_str")

# Render tokens into annotated ANSI string
annotated=$(echo "$tokens" | render_tokens)

# Escape the annotated string for JSON embedding
# Must escape: backslash, double quotes, and control characters
json_escaped=""
while IFS= read -r -d '' -n 1 ch || [[ -n "$ch" ]]; do
  case "$ch" in
    $'\033') json_escaped+="\\u001b" ;;
    '\'*)    json_escaped+="\\\\" ;;
    '"')     json_escaped+="\\\"" ;;
    $'\n')   json_escaped+="\\n" ;;
    $'\r')   json_escaped+="\\r" ;;
    $'\t')   json_escaped+="\\t" ;;
    *)       json_escaped+="$ch" ;;
  esac
done <<< "$annotated"

# Remove trailing \n added by <<< heredoc
json_escaped="${json_escaped%\\n}"

# Emit the hook response
echo "{\"systemMessage\": \"${json_escaped}\"}"
