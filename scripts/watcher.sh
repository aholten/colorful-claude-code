#!/usr/bin/env bash

# colorful-claude-code debug-log watcher
# Workaround for environments where allowManagedHooksOnly=true blocks user hooks.
# Tails the JSONL conversation log and prints colored emoji annotations
# to the terminal whenever Claude Code executes a Bash command.
#
# Usage:
#   bash scripts/watcher.sh [session-id]
#
# If no session-id is given, watches the most recent JSONL in the current
# project directory (~/.claude/projects/<project>/).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

JSONL_FILE=$(find_jsonl "${1:-}")
echo "## Watching: $JSONL_FILE"
echo "   Press Ctrl-C to stop."
echo ""

# --- Source rendering functions from annotate-pre.sh ---
# We extract just the rendering parts - _lookup, _lookup_op, render_command, _render_segment

# Re-source the core rendering. The annotate-pre.sh reads from stdin and outputs
# JSON, but we only need its internal functions. We'll source it in a subshell-safe way.

# Instead of sourcing (which would run main), we extract the functions we need.
# The simplest approach: pipe a fake empty input so it exits early, but define the
# functions inline here by copying the essentials.

# Actually, the cleanest approach: call annotate-pre.sh as-is for each command,
# feeding it the JSON it expects, and just grab the systemMessage to print.

# --- JSON helpers ---
_extract_system_message() {
  local json="$1"
  # Extract value of "systemMessage" key
  local pattern="\"systemMessage\"[[:space:]]*:[[:space:]]*\""
  [[ "$json" =~ $pattern ]] || return 1
  local after="${json#*${BASH_REMATCH[0]}}"
  local value="" i=0 len=${#after}
  while [[ $i -lt $len ]]; do
    local ch="${after:$i:1}"
    if [[ "$ch" == '\' ]]; then
      value+="${after:$i:2}"; i=$((i + 2))
    elif [[ "$ch" == '"' ]]; then
      break
    else
      value+="$ch"; i=$((i + 1))
    fi
  done
  printf '%s' "$value"
}

# --- Main tail loop ---
# Use tail -f to follow the JSONL. For each new line containing a Bash tool_use,
# extract the command, feed it to annotate-pre.sh, and print the annotation.

last_processed=""

tail -n 0 -f "$JSONL_FILE" | while IFS= read -r line; do
  # Quick filter: only care about lines with Bash tool_use
  [[ "$line" == *'"name":"Bash"'* ]] || [[ "$line" == *'"name": "Bash"'* ]] || \
  [[ "$line" == *'"tool_use"'* ]] || continue

  # Extract all Bash commands from the JSON line (a single assistant message
  # can contain multiple tool_use blocks when calls are made in parallel).
  cmds=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    msg = data.get('message', data)
    for block in msg.get('content', []):
        if isinstance(block, dict) and block.get('type') == 'tool_use' and block.get('name') == 'Bash':
            cmd = block.get('input', {}).get('command', '')
            if cmd:
                print(cmd)
except:
    pass
" <<< "$line" 2>/dev/null) || continue

  [[ -z "$cmds" ]] && continue

  # Process each command found in this JSONL line
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue

    # Deduplicate - skip if we just processed this exact command
    [[ "$cmd" == "$last_processed" ]] && continue
    last_processed="$cmd"

    # Feed it to annotate-pre.sh and capture the output
    hook_input=$(printf '{"tool_name":"Bash","input":{"command":"%s"}}' \
      "$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')")

    result=$(echo "$hook_input" | bash "$REPO_DIR/scripts/annotate-pre.sh" 2>/dev/null) || continue
    [[ -z "$result" ]] && continue

    # Extract the systemMessage and decode ANSI escapes
    msg=$(_extract_system_message "$result") || continue
    [[ -z "$msg" ]] && continue

    # Decode \u001b back to actual ESC characters for terminal rendering
    decoded=$(printf '%s' "$msg" | sed 's/\\u001b/\x1b/g' | sed 's/\\n/\n/g')

    # Print to terminal via /dev/tty so it shows up even if stdout is redirected
    printf '%b\n' "$decoded" > /dev/tty 2>/dev/null || printf '%b\n' "$decoded"
  done <<< "$cmds"
done
