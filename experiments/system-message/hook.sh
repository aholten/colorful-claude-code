#!/usr/bin/env bash
# Experiment 1: Use systemMessage to display ANSI-colored command annotation
# BEFORE the permission prompt appears.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/parser.sh"
source "$ROOT_DIR/scripts/renderer.sh"

# --- JSON helpers ---

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

# JSON-escape the ANSI output
json_escaped="$annotated"
json_escaped="${json_escaped//\\/\\\\}"
json_escaped="${json_escaped//\"/\\\"}"
json_escaped="${json_escaped//$'\033'/\\u001b}"
json_escaped="${json_escaped//$'\n'/\\n}"
json_escaped="${json_escaped//$'\r'/\\r}"
json_escaped="${json_escaped//$'\t'/\\t}"

# Return as systemMessage — content appears BEFORE the permission prompt
echo "{\"systemMessage\": \"${json_escaped}\"}"
