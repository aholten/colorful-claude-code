#!/usr/bin/env bash

# colorful-claude-code debug-log watcher
# Workaround for environments where allowManagedHooksOnly=true blocks user hooks.
# Tails the JSONL conversation log and prints colored emoji annotations
# to the terminal whenever Claude Code executes a Bash command.
#
# Pure bash, zero dependencies — JSONL parsing reuses the hook's own
# escape-aware JSON scanner from annotate-pre.sh.
#
# Usage:
#   bash scripts/watcher.sh [session-id]
#
# If no session-id is given, watches the most recent JSONL in the current
# project directory (~/.claude/projects/<project>/).
#
# Runs main only when executed directly; test.sh sources this file to
# unit-test _extract_bash_commands and _extract_system_message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Reuse the hook's JSON helpers (_extract_json_string, _unescape_json_string).
# annotate-pre.sh only runs its main entry point when executed directly, so
# sourcing it here is side-effect free.
source "$SCRIPT_DIR/annotate-pre.sh"

# --- Resolve the JSONL to tail ---

# Find the project directory - Claude Code uses the cwd path with / replaced by -
PROJECT_DIR="$HOME/.claude/projects"

find_jsonl() {
  local session_id="${1:-}"

  if [[ -n "$session_id" ]]; then
    # Direct session ID
    local matches
    matches=$(find "$PROJECT_DIR" -name "${session_id}.jsonl" 2>/dev/null | head -1)
    if [[ -n "$matches" ]]; then
      echo "$matches"
      return
    fi
    echo "Error: no JSONL found for session $session_id" >&2
    return 1
  fi

  # Try to find the project dir for the current working directory.
  # Claude Code encodes the cwd as path-with-slashes-replaced-by-dashes.
  local cwd_key
  cwd_key=$(pwd | sed 's|/|-|g')
  local project_subdir="$PROJECT_DIR/$cwd_key"

  if [[ -d "$project_subdir" ]]; then
    local latest
    latest=$(ls -t "$project_subdir"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
      echo "$latest"
      return
    fi
  fi

  # Fallback: most recently modified JSONL across all project dirs
  local latest
  latest=$(find "$PROJECT_DIR" -name '*.jsonl' -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    echo "$latest"
    return
  fi

  echo "Error: no JSONL files found in $PROJECT_DIR" >&2
  return 1
}

# --- JSON helpers ---

# Extract the value of "systemMessage" from the hook's JSON output
_extract_system_message() {
  _extract_json_string "$1" "systemMessage"
}

# Extract every Bash tool_use command from a JSONL line, one per line,
# still JSON-escaped (an assistant message can contain multiple tool_use
# blocks when calls are made in parallel). Scans for "name":"Bash" markers
# and pulls the command string that follows each, using the hook's
# escape-aware scanner — no Python needed.
_extract_bash_commands() {
  local rest="$1" cmd
  while [[ "$rest" == *'"name"'* ]]; do
    rest="${rest#*\"name\"}"
    [[ "$rest" =~ ^[[:space:]]*:[[:space:]]*\"Bash\" ]] || continue
    cmd=$(_extract_json_string "$rest" "command") || continue
    [[ -n "$cmd" ]] && printf '%s\n' "$cmd"
  done
  return 0
}

# --- Main tail loop ---
# Use tail -f to follow the JSONL. For each new line containing a Bash
# tool_use, extract the command, feed it to annotate-pre.sh, and print
# the annotation.

watcher_main() {
  local jsonl_file last_processed line cmds cmd hook_input result msg decoded

  jsonl_file=$(find_jsonl "${1:-}")
  echo "## Watching: $jsonl_file"
  echo "   Press Ctrl-C to stop."
  echo ""

  last_processed=""

  tail -n 0 -f "$jsonl_file" | while IFS= read -r line; do
    # Quick filter: only care about lines with Bash tool_use
    [[ "$line" == *'"name":"Bash"'* ]] || [[ "$line" == *'"name": "Bash"'* ]] || continue

    cmds=$(_extract_bash_commands "$line")
    [[ -z "$cmds" ]] && continue

    # Process each command found in this JSONL line
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue

      # Deduplicate - skip if we just processed this exact command
      [[ "$cmd" == "$last_processed" ]] && continue
      last_processed="$cmd"

      # cmd is still JSON-escaped from the log, so it can be embedded
      # directly in the same tool_input shape Claude Code sends to
      # PreToolUse hooks.
      hook_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${cmd}\"}}"

      result=$(echo "$hook_input" | bash "$SCRIPT_DIR/annotate-pre.sh" 2>/dev/null) || continue
      [[ -z "$result" ]] && continue

      # Extract the systemMessage and decode ANSI escapes
      msg=$(_extract_system_message "$result") || continue
      [[ -z "$msg" ]] && continue

      # Decode the JSON unicode escapes back to actual ESC characters for rendering
      decoded=$(printf '%s' "$msg" | sed 's/\\u001b/\x1b/g' | sed 's/\\n/\n/g')

      # Print to terminal via /dev/tty so it shows up even if stdout is redirected
      printf '%b\n' "$decoded" > /dev/tty 2>/dev/null || printf '%b\n' "$decoded"
    done <<< "$cmds"
  done
}

# Execute only when run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  watcher_main "${1:-}"
fi
