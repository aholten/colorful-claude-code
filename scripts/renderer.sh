#!/usr/bin/env bash
# renderer.sh — ANSI renderer for claude-code-colorful-bash
# Takes parsed tokens on stdin, outputs colorized annotated string
#
# Usage: source this file, then pipe tokens into render_tokens
#   echo "CMD:git status" | render_tokens
#
# Also provides: lookup_command, lookup_operator

COMMAND_MAP="${COMMAND_MAP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/command-map.json}"

# Cache for parsed map entries (avoids re-reading file per lookup)
declare -A _CMD_EMOJI_CACHE 2>/dev/null || true
declare -A _CMD_BG_CACHE 2>/dev/null || true
declare -A _CMD_FG_CACHE 2>/dev/null || true
_MAP_LOADED=0

# _load_map — Parse the JSON mapping file into bash associative arrays
_load_map() {
  [[ "$_MAP_LOADED" -eq 1 ]] && return 0
  [[ ! -f "$COMMAND_MAP" ]] && return 1

  local section=""
  local current_key=""

  while IFS= read -r line; do
    # Detect section
    if [[ "$line" =~ \"commands\" ]]; then
      section="commands"
      continue
    elif [[ "$line" =~ \"operators\" ]]; then
      section="operators"
      continue
    elif [[ "$line" =~ \"_default\" ]]; then
      section="_default"
      continue
    fi

    # Parse key-value entries like:  "git": { "emoji": "🔀", "bg": 202, "fg": 17 }
    if [[ "$section" == "commands" || "$section" == "operators" ]]; then
      if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"emoji\":[[:space:]]*\"([^\"]*)\",[[:space:]]*\"bg\":[[:space:]]*([0-9]+),[[:space:]]*\"fg\":[[:space:]]*([0-9]+) ]]; then
        local key="${BASH_REMATCH[1]}"
        local emoji="${BASH_REMATCH[2]}"
        local bg="${BASH_REMATCH[3]}"
        local fg="${BASH_REMATCH[4]}"

        if [[ "$section" == "operators" ]]; then
          key="op:${key}"
        fi

        _CMD_EMOJI_CACHE["$key"]="$emoji"
        _CMD_BG_CACHE["$key"]="$bg"
        _CMD_FG_CACHE["$key"]="$fg"
      fi
    elif [[ "$section" == "_default" ]]; then
      if [[ "$line" =~ \"emoji\":[[:space:]]*\"([^\"]*)\" ]]; then
        _CMD_EMOJI_CACHE["_default"]="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ \"bg\":[[:space:]]*([0-9]+) ]]; then
        _CMD_BG_CACHE["_default"]="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ \"fg\":[[:space:]]*([0-9]+) ]]; then
        _CMD_FG_CACHE["_default"]="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$COMMAND_MAP"

  _MAP_LOADED=1
}

# lookup_command <base_command>
# Returns: "<emoji> <bg> <fg>" or "_default <bg> <fg>" for unknown commands
lookup_command() {
  local cmd="$1"
  _load_map

  if [[ -n "${_CMD_EMOJI_CACHE[$cmd]+x}" ]]; then
    echo "${_CMD_EMOJI_CACHE[$cmd]} ${_CMD_BG_CACHE[$cmd]} ${_CMD_FG_CACHE[$cmd]}"
  else
    echo "_default ${_CMD_BG_CACHE[_default]} ${_CMD_FG_CACHE[_default]}"
  fi
}

# lookup_operator <operator>
# Returns: "<emoji> <bg> <fg>"
lookup_operator() {
  local op="$1"
  local key="op:${op}"
  _load_map

  if [[ -n "${_CMD_EMOJI_CACHE[$key]+x}" ]]; then
    echo "${_CMD_EMOJI_CACHE[$key]} ${_CMD_BG_CACHE[$key]} ${_CMD_FG_CACHE[$key]}"
  else
    echo "_default ${_CMD_BG_CACHE[_default]} ${_CMD_FG_CACHE[_default]}"
  fi
}

# _extract_base_command <command_string>
# Extracts the first word (the binary name) from a command string
_extract_base_command() {
  local cmd_str="$1"
  # Trim leading whitespace
  cmd_str="${cmd_str#"${cmd_str%%[![:space:]]*}"}"
  # Get first word
  echo "${cmd_str%% *}"
}

# render_tokens — reads token stream from stdin, outputs ANSI-colored string
# Token format (one per line):
#   CMD:<command_string>
#   OP:<operator>
#   SUBCMD_START
#   SUBCMD_END
#   SUBSHELL_START
#   SUBSHELL_END
render_tokens() {
  _load_map

  local ESC=$'\033'
  local RESET="${ESC}[0m"
  local output=""
  local need_space=0

  while IFS= read -r token; do
    case "$token" in
      CMD:*)
        local cmd_str="${token#CMD:}"
        local base_cmd
        base_cmd=$(_extract_base_command "$cmd_str")
        local lookup_result
        lookup_result=$(lookup_command "$base_cmd")

        local emoji bg fg
        read -r emoji bg fg <<< "$lookup_result"

        local bg_code="${ESC}[48;5;${bg}m"
        local fg_code="${ESC}[38;5;${fg}m"

        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi

        if [[ "$emoji" != "_default" && -n "$emoji" ]]; then
          # Append variation selector U+FE0F after emoji
          output+="${bg_code}${fg_code} ${emoji}$(printf '\xEF\xB8\x8F') ${cmd_str} ${RESET}"
        else
          output+="${bg_code}${fg_code} ${cmd_str} ${RESET}"
        fi
        need_space=1
        ;;

      OP:*)
        local op="${token#OP:}"
        local lookup_result
        lookup_result=$(lookup_operator "$op")

        local emoji bg fg
        read -r emoji bg fg <<< "$lookup_result"

        local bg_code="${ESC}[48;5;${bg}m"
        local fg_code="${ESC}[38;5;${fg}m"

        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi

        # Operator: emoji + color spans only operator chars
        output+="${bg_code}${fg_code} ${emoji}$(printf '\xEF\xB8\x8F') ${op} ${RESET}"
        need_space=1
        ;;

      SUBCMD_START)
        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi
        output+="\$("
        need_space=0
        ;;

      SUBCMD_END)
        output+=")"
        need_space=1
        ;;

      SUBSHELL_START)
        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi
        output+="("
        need_space=0
        ;;

      SUBSHELL_END)
        output+=")"
        need_space=1
        ;;
    esac
  done

  # Ensure we end with a reset
  output+="${RESET}"
  printf '%s' "$output"
}
