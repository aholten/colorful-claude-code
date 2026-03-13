#!/usr/bin/env bash
# parser.sh — Command parser for claude-code-colorful-bash
# Tokenizes bash commands into: CMD, OP, SUBCMD_START/END, SUBSHELL_START/END
#
# Usage: source this file, then call parse_command "<command_string>"
# Output: newline-delimited tokens to stdout
#
# Token types:
#   CMD:<command_text>     — a command segment (trimmed)
#   OP:<operator>          — an operator (&&, ||, |, ;)
#   SUBCMD_START           — start of $(...) or backtick command substitution
#   SUBCMD_END             — end of command substitution
#   SUBSHELL_START         — start of (...) subshell
#   SUBSHELL_END           — end of subshell

# _trim — remove leading/trailing whitespace
_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  echo "$s"
}

# _emit_cmd — emit a CMD token if buffer is non-empty
_emit_cmd() {
  local buf="$1"
  buf=$(_trim "$buf")
  if [[ -n "$buf" ]]; then
    echo "CMD:${buf}"
  fi
}

# parse_command <command_string>
# Parses a bash command string into a token stream on stdout
parse_command() {
  local input="$1"
  local len=${#input}

  # Empty input
  if [[ $len -eq 0 ]]; then
    return 0
  fi

  local buf=""           # Current command buffer
  local i=0              # Position
  local in_single_quote=0
  local in_double_quote=0
  local in_backtick=0

  # Stack to track nesting context: 's' = subcmd $(), 'b' = backtick, 'p' = subshell ()
  local -a context_stack=()

  while [[ $i -lt $len ]]; do
    local ch="${input:$i:1}"
    local next="${input:$((i+1)):1}"

    # --- Quote handling ---

    # Single quote toggle (not inside double quotes or backticks)
    if [[ "$ch" == "'" && $in_double_quote -eq 0 ]]; then
      in_single_quote=$(( 1 - in_single_quote ))
      buf+="$ch"
      i=$((i + 1))
      continue
    fi

    # Double quote toggle (not inside single quotes)
    if [[ "$ch" == '"' && $in_single_quote -eq 0 ]]; then
      in_double_quote=$(( 1 - in_double_quote ))
      buf+="$ch"
      i=$((i + 1))
      continue
    fi

    # Inside quotes — everything is literal
    if [[ $in_single_quote -eq 1 || $in_double_quote -eq 1 ]]; then
      # Exception: $() inside double quotes is still a substitution
      if [[ $in_double_quote -eq 1 && "$ch" == '$' && "$next" == '(' ]]; then
        _emit_cmd "$buf"
        buf=""
        echo "SUBCMD_START"
        context_stack+=("s")
        i=$((i + 2))
        continue
      fi
      buf+="$ch"
      i=$((i + 1))
      continue
    fi

    # --- Command substitution: $( ---
    if [[ "$ch" == '$' && "$next" == '(' ]]; then
      _emit_cmd "$buf"
      buf=""
      echo "SUBCMD_START"
      context_stack+=("s")
      i=$((i + 2))
      continue
    fi

    # --- Backtick substitution ---
    if [[ "$ch" == '`' ]]; then
      if [[ $in_backtick -eq 0 ]]; then
        _emit_cmd "$buf"
        buf=""
        echo "SUBCMD_START"
        context_stack+=("b")
        in_backtick=1
      else
        _emit_cmd "$buf"
        buf=""
        echo "SUBCMD_END"
        # Pop backtick from stack
        unset 'context_stack[${#context_stack[@]}-1]'
        in_backtick=0
      fi
      i=$((i + 1))
      continue
    fi

    # --- Closing parenthesis: end of $() or () ---
    if [[ "$ch" == ')' ]]; then
      local stack_len=${#context_stack[@]}
      if [[ $stack_len -gt 0 ]]; then
        local top="${context_stack[$((stack_len - 1))]}"
        if [[ "$top" == "s" || "$top" == "p" ]]; then
          _emit_cmd "$buf"
          buf=""
          if [[ "$top" == "s" ]]; then
            echo "SUBCMD_END"
          else
            echo "SUBSHELL_END"
          fi
          unset 'context_stack[${#context_stack[@]}-1]'
          i=$((i + 1))
          continue
        fi
      fi
      # Not in a context — treat as literal
      buf+="$ch"
      i=$((i + 1))
      continue
    fi

    # --- Opening parenthesis: subshell (not preceded by $) ---
    if [[ "$ch" == '(' ]]; then
      # Check if this is a subshell at command position
      # (preceded by nothing, whitespace, or an operator)
      local prev_char=""
      if [[ $i -gt 0 ]]; then
        prev_char="${input:$((i-1)):1}"
      fi
      if [[ "$prev_char" != '$' ]]; then
        _emit_cmd "$buf"
        buf=""
        echo "SUBSHELL_START"
        context_stack+=("p")
        i=$((i + 1))
        continue
      fi
      buf+="$ch"
      i=$((i + 1))
      continue
    fi

    # --- Operators (only at top level or inside nesting contexts) ---

    # && operator
    if [[ "$ch" == '&' && "$next" == '&' ]]; then
      _emit_cmd "$buf"
      buf=""
      echo "OP:&&"
      i=$((i + 2))
      continue
    fi

    # || operator
    if [[ "$ch" == '|' && "$next" == '|' ]]; then
      _emit_cmd "$buf"
      buf=""
      echo "OP:||"
      i=$((i + 2))
      continue
    fi

    # | pipe (single)
    if [[ "$ch" == '|' ]]; then
      _emit_cmd "$buf"
      buf=""
      echo "OP:|"
      i=$((i + 1))
      continue
    fi

    # ; semicolon
    if [[ "$ch" == ';' ]]; then
      _emit_cmd "$buf"
      buf=""
      echo "OP:;"
      i=$((i + 1))
      continue
    fi

    # --- Default: accumulate into buffer ---
    buf+="$ch"
    i=$((i + 1))
  done

  # Emit any remaining buffer
  _emit_cmd "$buf"
}
