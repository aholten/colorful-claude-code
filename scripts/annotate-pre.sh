#!/usr/bin/env bash
# annotate-pre.sh — PreToolUse hook entry point
#
# extract command from hook JSON → parse → render → re-escape → emit valid JSON
# Must be a no-op for non-Bash tools. Output must always be parseable JSON.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/parser.sh"
source "$SCRIPT_DIR/renderer.sh"

# Read all of stdin
input=$(cat)

# extract JSON string values without external deps (no jq).
# Must handle escaped quotes correctly.
_extract_json_string() {
  local json="$1" key="$2"
  local pattern="\"${key}\"[[:space:]]*:[[:space:]]*\""

  # Find where the value starts
  if [[ ! "$json" =~ $pattern ]]; then
    return 1
  fi
  local after="${json#*${BASH_REMATCH[0]}}"

  # Walk forward, respecting \" escapes, until unescaped closing "
  local value="" i=0 len=${#after}
  while [[ $i -lt $len ]]; do
    local ch="${after:$i:1}"
    if [[ "$ch" == '\' ]]; then
      value+="${after:$i:2}"
      i=$((i + 2))
    elif [[ "$ch" == '"' ]]; then
      break
    else
      value+="$ch"
      i=$((i + 1))
    fi
  done
  printf '%s' "$value"
}

# faithfully convert all JSON escapes to literal chars. Backslash must be first.
_unescape_json_string() {
  local s="$1"
  s="${s//\\\\/\\}"       # \\ → \  (must be first)
  s="${s//\\\"/\"}"       # \" → "
  s="${s//\\n/$'\n'}"     # \n → newline
  s="${s//\\t/$'\t'}"     # \t → tab
  s="${s//\\r/$'\r'}"     # \r → CR
  s="${s//\\\/\//\/}"     # \/ → /
  printf '%s' "$s"
}

# Detect hook event type (PreToolUse or PermissionRequest)
hook_event=$(_extract_json_string "$input" "hook_event_name") || true
if [[ -z "$hook_event" ]]; then
  hook_event="PreToolUse"
fi

# Extract tool_name — only annotate Bash tool calls
tool_name=$(_extract_json_string "$input" "tool_name") || true

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# Extract and unescape the command field
command_str=$(_extract_json_string "$input" "command") || true

# Empty command — no-op
if [[ -z "$command_str" ]]; then
  exit 0
fi

command_str=$(_unescape_json_string "$command_str")

# Parse the command into tokens (supports multi-line commands)
tokens=$(parse_multiline_command "$command_str")

# Render tokens into annotated ANSI string
annotated=$(echo "$tokens" | render_tokens)

# every special char (\ " ESC \n \r \t) must be escaped for valid JSON.
# Backslash must be escaped first to avoid double-escaping.
json_escaped="$annotated"
json_escaped="${json_escaped//\\/\\\\}"             # \ → \\  (must be first)
json_escaped="${json_escaped//\"/\\\"}"             # " → \"
json_escaped="${json_escaped//$'\033'/\\u001b}"     # ESC → \u001b
json_escaped="${json_escaped//$'\n'/\\n}"           # newline → \n
json_escaped="${json_escaped//$'\r'/\\r}"           # CR → \r
json_escaped="${json_escaped//$'\t'/\\t}"           # tab → \t

# Emit the hook response
echo "{\"systemMessage\": \"${json_escaped}\", \"hookSpecificOutput\": {\"hookEventName\": \"${hook_event}\"}}"
