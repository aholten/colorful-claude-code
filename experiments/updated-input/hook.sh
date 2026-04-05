#!/usr/bin/env bash
# annotate-pre-prompt.sh — Alternative hook that shows annotations
# INSIDE the permission prompt using updatedInput.
#
# Trade-off: forces a permission prompt on every Bash command.
# Use this if you prefer seeing the annotation before approving.
#
# To use: replace the hook command in settings.local.json with this script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/parser.sh"
source "$ROOT_DIR/scripts/renderer.sh"

# --- JSON helpers (same as annotate-pre.sh) ---

_extract_json_string() {
  local json="$1" key="$2"
  local pattern="\"${key}\"[[:space:]]*:[[:space:]]*\""
  if [[ ! "$json" =~ $pattern ]]; then
    return 1
  fi
  local after="${json#*${BASH_REMATCH[0]}}"
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

_unescape_json_string() {
  local s="$1"
  s="${s//\\\\/\\}"
  s="${s//\\\"/\"}"
  s="${s//\\n/$'\n'}"
  s="${s//\\t/$'\t'}"
  s="${s//\\r/$'\r'}"
  s="${s//\\\/\//\/}"
  printf '%s' "$s"
}

# --- Main ---

input=$(cat)

tool_name=$(_extract_json_string "$input" "tool_name") || true
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

command_str=$(_extract_json_string "$input" "command") || true
if [[ -z "$command_str" ]]; then
  exit 0
fi

command_str=$(_unescape_json_string "$command_str")

# Parse and render
tokens=$(parse_multiline_command "$command_str")
annotated=$(echo "$tokens" | render_tokens)

# Prepend "#" to every line of the annotation
annotated_commented="#${annotated}"
annotated_commented="${annotated_commented//$'\n'/$'\n#'}"

# JSON-escape the annotation
json_annotation="$annotated_commented"
json_annotation="${json_annotation//\\/\\\\}"
json_annotation="${json_annotation//\"/\\\"}"
json_annotation="${json_annotation//$'\033'/\\u001b}"
json_annotation="${json_annotation//$'\n'/\\n}"
json_annotation="${json_annotation//$'\r'/\\r}"
json_annotation="${json_annotation//$'\t'/\\t}"

# JSON-escape the original command
json_command="$command_str"
json_command="${json_command//\\/\\\\}"
json_command="${json_command//\"/\\\"}"
json_command="${json_command//$'\n'/\\n}"
json_command="${json_command//$'\r'/\\r}"
json_command="${json_command//$'\t'/\\t}"

# Annotation inside the prompt via updatedInput + permissionDecision: "ask".
# Forces a prompt on every command. Annotation on line 1, original command below.
echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"ask\", \"updatedInput\": {\"command\": \"${json_annotation}\\n${json_command}\"}}}"
