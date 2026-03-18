#!/usr/bin/env bash
# renderer.sh — Token stream → ANSI-colored emoji-annotated string
#
# every token gets correct emoji + category colors from command-map.json.
# Unknown commands degrade to neutral gray, never error.
# Every rendered line must end with ANSI reset + erase-to-EOL to prevent background bleed.

COMMAND_MAP="${COMMAND_MAP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/command-map.json}"

# Cache for parsed map entries (avoids re-reading file per lookup)
declare -A _CMD_EMOJI_CACHE 2>/dev/null || true
declare -A _CMD_BG_CACHE 2>/dev/null || true
declare -A _CMD_FG_CACHE 2>/dev/null || true
_MAP_LOADED=0

# lazy-load and cache command-map.json once. No external JSON parser (no jq).
# Commands inherit bg/fg from their category; operators inherit from "operators" category.
_load_map() {
  [[ "$_MAP_LOADED" -eq 1 ]] && return 0
  [[ ! -f "$COMMAND_MAP" ]] && return 1

  local section=""
  local depth=0
  # Temporary storage for category colors
  declare -A _cat_bg
  declare -A _cat_fg

  while IFS= read -r line; do
    # Track brace depth to distinguish top-level keys from nested ones.
    # Count opening/closing braces on each line.
    local opens="${line//[^\{]/}"
    local closes="${line//[^\}]/}"
    depth=$(( depth + ${#opens} - ${#closes} ))

    # Detect top-level section headers (depth was 1 before this line's braces)
    # A top-level key appears at depth 1 (inside the root object)
    if (( depth >= 2 )) && [[ "$section" == "" || $(( depth - ${#opens} + ${#closes} )) -le 1 ]]; then
      if [[ "$line" =~ \"categories\"[[:space:]]*: ]]; then
        section="categories"
        continue
      elif [[ "$line" =~ \"commands\"[[:space:]]*: ]]; then
        section="commands"
        continue
      elif [[ "$line" =~ \"operators\"[[:space:]]*: ]]; then
        section="operators"
        continue
      fi
    fi

    # Reset section when we return to depth 1 (closing brace of a section)
    if (( depth <= 1 )) && [[ -n "$section" ]]; then
      section=""
    fi

    # Parse default (single-line): "default": { "emoji": "...", "bg": N, "fg": N }
    if [[ "$line" =~ \"default\"[[:space:]]*:[[:space:]]*\{.*\"bg\":[[:space:]]*([0-9]+).*\"fg\":[[:space:]]*([0-9]+) ]]; then
      _CMD_EMOJI_CACHE["_default"]=""
      _CMD_BG_CACHE["_default"]="${BASH_REMATCH[1]}"
      _CMD_FG_CACHE["_default"]="${BASH_REMATCH[2]}"
      continue
    fi

    # Parse category entries like:  "version_control": { "bg": 202, "fg": 17, "label": "..." }
    if [[ "$section" == "categories" ]]; then
      if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"bg\":[[:space:]]*([0-9]+),[[:space:]]*\"fg\":[[:space:]]*([0-9]+) ]]; then
        _cat_bg["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        _cat_fg["${BASH_REMATCH[1]}"]="${BASH_REMATCH[3]}"
      fi
    # Parse command entries like:  "git": { "emoji": "🔀", "cat": "version_control" }
    elif [[ "$section" == "commands" ]]; then
      if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"emoji\":[[:space:]]*\"([^\"]*)\",[[:space:]]*\"cat\":[[:space:]]*\"([^\"]*)\" ]]; then
        local key="${BASH_REMATCH[1]}"
        local emoji="${BASH_REMATCH[2]}"
        local cat="${BASH_REMATCH[3]}"
        _CMD_EMOJI_CACHE["$key"]="$emoji"
        _CMD_BG_CACHE["$key"]="${_cat_bg[$cat]}"
        _CMD_FG_CACHE["$key"]="${_cat_fg[$cat]}"
      fi
    # Parse operator entries like:  "&&": { "emoji": "✅" }
    elif [[ "$section" == "operators" ]]; then
      if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"emoji\":[[:space:]]*\"([^\"]*)\" ]]; then
        local key="op:${BASH_REMATCH[1]}"
        _CMD_EMOJI_CACHE["$key"]="${BASH_REMATCH[2]}"
        _CMD_BG_CACHE["$key"]="${_cat_bg[operators]}"
        _CMD_FG_CACHE["$key"]="${_cat_fg[operators]}"
      fi
    fi
  done < "$COMMAND_MAP"

  _MAP_LOADED=1
}

# _lookup <cache_key>
# Returns: "<emoji> <bg> <fg>" or "_default <bg> <fg>" for unknown keys
_lookup() {
  local key="$1"
  _load_map

  if [[ -n "${_CMD_EMOJI_CACHE[$key]+x}" ]]; then
    echo "${_CMD_EMOJI_CACHE[$key]} ${_CMD_BG_CACHE[$key]} ${_CMD_FG_CACHE[$key]}"
  else
    echo "_default ${_CMD_BG_CACHE[_default]} ${_CMD_FG_CACHE[_default]}"
  fi
}

# lookup_command <base_command>
# Returns: "<emoji> <bg> <fg>" or "_default <bg> <fg>" for unknown commands
lookup_command() { _lookup "$1"; }

# lookup_operator <operator>
# Returns: "<emoji> <bg> <fg>"
lookup_operator() { _lookup "op:$1"; }

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
        # Inline base command extraction (trim leading whitespace, take first word)
        local base_cmd="${cmd_str#"${cmd_str%%[![:space:]]*}"}"
        base_cmd="${base_cmd%% *}"

        # Inline lookup (avoids subshell fork per token)
        local emoji bg fg
        if [[ -n "${_CMD_EMOJI_CACHE[$base_cmd]+x}" ]]; then
          emoji="${_CMD_EMOJI_CACHE[$base_cmd]}"
          bg="${_CMD_BG_CACHE[$base_cmd]}"
          fg="${_CMD_FG_CACHE[$base_cmd]}"
        else
          emoji="_default"
          bg="${_CMD_BG_CACHE[_default]}"
          fg="${_CMD_FG_CACHE[_default]}"
        fi

        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi

        if [[ "$emoji" != "_default" && -n "$emoji" ]]; then
          output+="${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${emoji} ${cmd_str} ${RESET}"
        else
          output+="${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${cmd_str} ${RESET}"
        fi
        need_space=1
        ;;

      OP:*)
        local op="${token#OP:}"
        local key="op:${op}"

        # Inline lookup (avoids subshell fork per token)
        local emoji bg fg
        if [[ -n "${_CMD_EMOJI_CACHE[$key]+x}" ]]; then
          emoji="${_CMD_EMOJI_CACHE[$key]}"
          bg="${_CMD_BG_CACHE[$key]}"
          fg="${_CMD_FG_CACHE[$key]}"
        else
          emoji="_default"
          bg="${_CMD_BG_CACHE[_default]}"
          fg="${_CMD_FG_CACHE[_default]}"
        fi

        if [[ $need_space -eq 1 ]]; then
          output+=" "
        fi

        output+="${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${emoji} ${op} ${RESET}"
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

      NEWLINE)
        output+="${RESET}${ESC}[K"
        output+=$'\n'
        need_space=0
        ;;
    esac
  done

  # Ensure we end with a reset + erase-to-EOL to prevent background bleed
  output+="${RESET}${ESC}[K"
  printf '%s' "$output"
}
