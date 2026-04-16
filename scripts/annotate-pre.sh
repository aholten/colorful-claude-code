#!/usr/bin/env bash

# Bash Annotator — PreToolUse hook for Claude Code
# Adds colored emoji annotations to Bash commands via systemMessage.
# Zero dependencies. Pure bash. No special fonts needed.

trap 'exit 0' ERR

# --- JSON helpers ---

_extract_json_string() {
  local json="$1" key="$2"
  local pattern="\"${key}\"[[:space:]]*:[[:space:]]*\""
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

# --- Read JSON and extract command ---
input=$(cat)
command=$(_extract_json_string "$input" "command") || true
[ -z "$command" ] && exit 0
command=$(_unescape_json_string "$command")

# Collapse whitespace to spaces so the annotation stays on a single visible
# line. The executed command is unaffected — this only shapes the display.
command="${command//[$'\n\r\t']/ }"
while [[ "$command" == *"  "* ]]; do command="${command//  / }"; done

# Chunk budget for styled spans. Claude Code does not pass terminal size or
# a TTY through to hooks (COLUMNS unset, /dev/tty unavailable), so this is
# config, not detected. 60 fits ~85-col setups; wider terminals can raise
# via COLORFUL_CHUNK_WIDTH.
CHUNK_WIDTH="${COLORFUL_CHUNK_WIDTH:-60}"
[[ "$CHUNK_WIDTH" =~ ^[0-9]+$ ]] || CHUNK_WIDTH=60
[[ "$CHUNK_WIDTH" -lt 20 ]] && CHUNK_WIDTH=20

# --- Emoji + color lookup ---
# Returns: EMOJI BG FG
# BG/FG are 256-color ANSI palette numbers

# Okabe-Ito CVD-safe palette (256-color approximations)
# Red       160  — destructive / danger    (FG 230 light)
# Orange    214  — version control         (FG 16 black)
# Yellow    227  — search / inspect / lint (FG 16 black)
# Blu-Green  29  — verify / test           (FG 230 light)
# Sky Blue   81  — network / infra         (FG 16 black)
# Blue       25  — run / build / execute   (FG 230 light)
# Red-Purple 175 — package management      (FG 16 black)
# Purple    135  — shell control flow       (FG 230 light)
# Gray      240  — neutral / read / system (FG 255 white)

_lookup() {
  local cmd="$1"
  case "$cmd" in
    # Shell control flow — Purple 135
    for|while|until|select) echo "🔁 135 230" ;;
    if|case)                echo "❓ 135 230" ;;

    # Version control — Orange 214
    git)                echo "🔀 214 16"  ;;
    gh)                 echo "🐙 214 16"  ;;

    # File navigation — Gray 240 (neutral)
    cd)                 echo "📁 240 255" ;;
    ls|exa|eza|lsd)     echo "📋 240 255" ;;
    tree)               echo "🌳 240 255" ;;
    pwd)                echo "📍 240 255" ;;

    # File reading — Gray 240 (neutral)
    cat|bat)            echo "🐱 240 255" ;;
    head)               echo "🔝 240 255" ;;
    tail)               echo "🔚 240 255" ;;
    less|more)          echo "📖 240 255" ;;
    wc)                 echo "📄 240 255" ;;

    # File create/update — Blue 25 (execute/modify)
    touch)              echo "👆 25 230"  ;;
    mkdir)              echo "📂 25 230"  ;;
    cp)                 echo "📄 25 230"  ;;
    mv)                 echo "📤 25 230"  ;;
    ln)                 echo "🔗 25 230"  ;;

    # Destructive / dangerous — Red 160
    rm|rmdir)           echo "🗑 160 230"  ;;
    chmod|chown)        echo "🔒 160 230"  ;;

    # Searching — Yellow 227
    grep|rg|ag)         echo "🔍 227 16"  ;;
    find|fd)            echo "🔎 227 16"  ;;
    locate)             echo "🔎 227 16"  ;;

    # Text processing — Yellow 227 (inspect/transform)
    sed|awk)            echo "✏ 227 16"   ;;
    sort)               echo "📊 227 16"  ;;
    uniq|cut|tr)        echo "✏ 227 16"   ;;
    jq|yq)              echo "✏ 227 16"   ;;

    # Building — Blue 25 (execute/modify)
    make|cmake|ninja)   echo "🔨 25 230"  ;;
    gcc|g++|cc|clang)   echo "⚙ 25 230"   ;;

    # Script execution — Blue 25 (execute/modify)
    node)               echo "🟢 25 230"  ;;
    python|python3)     echo "🐍 25 230"  ;;
    ruby)               echo "💎 25 230"  ;;
    bash|sh|zsh)        echo "💻 25 230"  ;;
    deno)               echo "🦕 25 230"  ;;
    bun)                echo "🍞 25 230"  ;;
    java|javac)         echo "☕ 25 230"  ;;
    go)                 echo "🔵 25 230"  ;;
    cargo|rustc|rustup) echo "🦀 25 230"  ;;
    kotlin|kotlinc)     echo "🟣 25 230"  ;;

    # Testing — Bluish Green 29 (verify)
    pytest|jest|vitest|mocha|playwright|rspec) echo "🧪 29 230" ;;

    # Package management — Reddish Purple 175
    npm|npx)            echo "📦 175 16"  ;;
    yarn|pnpm)          echo "📦 175 16"  ;;
    pip|pip3|pipx)      echo "🐍 175 16"  ;;
    poetry|pdm|uv)      echo "🐍 175 16"  ;;
    gem|bundle)          echo "💎 175 16"  ;;
    gradle|mvn)         echo "☕ 175 16"  ;;
    brew)               echo "🍺 175 16"  ;;
    apt|apt-get|yum|dnf|pacman) echo "📦 175 16" ;;

    # HTTP — Sky Blue 81 (network)
    curl|wget|httpie)   echo "🌐 81 16"   ;;

    # Networking — Sky Blue 81 (network)
    ssh|scp|sftp)       echo "🔑 81 16"   ;;
    rsync)              echo "📄 81 16"   ;;
    ping|traceroute)    echo "🌐 81 16"   ;;

    # Archiving — Gray 240 (neutral)
    tar|zip|unzip|gzip|gunzip) echo "🗜 240 255" ;;

    # Output — Gray 240 (neutral)
    echo|printf)        echo "💬 240 255" ;;

    # Process management — Gray 240 (neutral)
    ps|top|htop)        echo "📊 240 255" ;;
    kill|killall)       echo "💀 160 230"  ;;
    jobs|fg|bg)         echo "📊 240 255" ;;

    # Elevated — Red 160 (danger)
    sudo)               echo "⚡ 160 230"  ;;

    # Containers — Sky Blue 81 (infra)
    docker|podman)      echo "🐳 81 16"   ;;
    kubectl|k9s|helm)   echo "☸ 81 16"    ;;
    terraform|tofu)     echo "🏛 81 16"    ;;

    # Cloud — Sky Blue 81 (infra)
    aws)                echo "☁ 81 16"    ;;
    gcloud|gsutil)      echo "☁ 81 16"    ;;
    az)                 echo "☁ 81 16"    ;;

    # System — Gray 240 (neutral)
    systemctl|service)  echo "⚙ 240 255"  ;;
    journalctl)         echo "📜 240 255" ;;
    crontab)            echo "⏰ 240 255" ;;
    df|du|free)         echo "💾 240 255" ;;
    env|export|source)  echo "🌍 240 255" ;;

    # Editors — Blue 25 (execute/modify)
    vi|vim|nvim)        echo "✏ 25 230"   ;;
    nano)               echo "✏ 25 230"   ;;
    code)               echo "💻 25 230"  ;;
    emacs)              echo "✏ 25 230"   ;;

    # Databases — Sky Blue 81 (infra)
    psql)               echo "🗄 81 16"    ;;
    mysql|mariadb)      echo "🗄 81 16"    ;;
    redis-cli)          echo "🗄 81 16"    ;;
    sqlite3)            echo "🗄 81 16"    ;;
    mongosh)            echo "🗄 81 16"    ;;

    # Linters — Yellow 227 (inspect)
    eslint|prettier|shellcheck|ruff|black|mypy) echo "💡 227 16" ;;

    # Default — Gray 240
    *)                  echo "_ 240 255"  ;;
  esac
}

# Operator lookup
_lookup_op() {
  case "$1" in
    '&&') echo "✅ 236 250" ;;
    '||') echo "⚠ 236 250"  ;;
    '|')  echo "🔗 236 250" ;;
    ';')  echo "⏩ 236 250" ;;
    *)    echo "_ 236 250"  ;;
  esac
}

# --- Parse and render ---

ESC=$'\033'
RESET="${ESC}[0m"

# Split command on operators, render each segment with colors
render_command() {
  local input="$1"
  local output=""
  local buf=""
  local i=0
  local len=${#input}
  local in_single_quote=0
  local in_double_quote=0
  local in_backtick=0
  local paren_depth=0
  local brace_depth=0

  while [[ $i -lt $len ]]; do
    local ch="${input:$i:1}"
    local next="${input:$((i+1)):1}"

    # Backslash escape — skip next character entirely
    if [[ "$ch" == '\' && $i -lt $((len - 1)) ]]; then
      buf+="${input:$i:2}"; i=$((i + 2)); continue
    fi

    # Quote tracking
    if [[ "$ch" == "'" && $in_double_quote -eq 0 && $in_backtick -eq 0 ]]; then
      in_single_quote=$(( 1 - in_single_quote ))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ "$ch" == '"' && $in_single_quote -eq 0 && $in_backtick -eq 0 ]]; then
      in_double_quote=$(( 1 - in_double_quote ))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ $in_single_quote -eq 1 || $in_double_quote -eq 1 ]]; then
      buf+="$ch"; i=$((i + 1)); continue
    fi

    # Backtick command substitution
    if [[ "$ch" == '`' ]]; then
      in_backtick=$(( 1 - in_backtick ))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ $in_backtick -eq 1 ]]; then
      buf+="$ch"; i=$((i + 1)); continue
    fi

    # Subshell / command substitution tracking: $( ) and ( )
    if [[ "$ch" == '(' ]]; then
      paren_depth=$((paren_depth + 1))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ "$ch" == ')' && $paren_depth -gt 0 ]]; then
      paren_depth=$((paren_depth - 1))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ $paren_depth -gt 0 ]]; then
      buf+="$ch"; i=$((i + 1)); continue
    fi

    # Brace group tracking: { ...; }
    if [[ "$ch" == '{' ]]; then
      brace_depth=$((brace_depth + 1))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ "$ch" == '}' && $brace_depth -gt 0 ]]; then
      brace_depth=$((brace_depth - 1))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ $brace_depth -gt 0 ]]; then
      buf+="$ch"; i=$((i + 1)); continue
    fi

    # Operators
    local op=""
    if [[ "$ch" == '&' && "$next" == '&' ]]; then
      op="&&"; i=$((i + 2))
    elif [[ "$ch" == '|' && "$next" == '|' ]]; then
      op="||"; i=$((i + 2))
    elif [[ "$ch" == '|' ]]; then
      op="|"; i=$((i + 1))
    elif [[ "$ch" == ';' ]]; then
      op=";"; i=$((i + 1))
    fi

    if [[ -n "$op" ]]; then
      # Render buffered command
      if [[ -n "${buf// /}" ]]; then
        output+="$(_render_segment "$buf")"
      fi
      buf=""
      # Put the operator on its own visual line, and the next segment on the
      # line after. Claude Code's TUI only applies bg to the first visual
      # line of a styled span, so any span that shares a line with another
      # (e.g. operator + first chunk of next segment) risks wrapping and
      # losing styling on the wrapped portion. One span per line avoids this.
      output+=$'\n'
      local op_info
      op_info=$(_lookup_op "$op")
      local op_emoji="${op_info%% *}"
      local rest="${op_info#* }"
      local op_bg="${rest%% *}"
      local op_fg="${rest##* }"
      output+="${ESC}[48;5;${op_bg}m${ESC}[38;5;${op_fg}m ${op_emoji} ${op} ${RESET}"
      output+=$'\n'
      continue
    fi

    buf+="$ch"
    i=$((i + 1))
  done

  # Render remaining buffer
  if [[ -n "${buf// /}" ]]; then
    output+="$(_render_segment "$buf")"
  fi

  output+="${RESET}${ESC}[K"
  printf '%s' "$output"
}

# Render a single command segment with emoji + bg/fg colors
_render_segment() {
  local segment="$1"
  # Trim whitespace
  segment="${segment#"${segment%%[![:space:]]*}"}"
  segment="${segment%"${segment##*[![:space:]]}"}"
  [[ -z "$segment" ]] && return

  # Extract base command
  local base_cmd="${segment%% *}"
  base_cmd="${base_cmd##*/}"

  # Unwrap command wrappers to find the "real" command
  local unwrapped=true
  while $unwrapped; do
    unwrapped=false
    case "$base_cmd" in
      # Shell keywords that precede the real command in a compound statement
      do|then|else|elif)
        local rest="${segment#$base_cmd}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        if [[ -n "$rest" ]]; then
          segment="$rest"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
      bash|sh)
        if [[ "$segment" =~ ^(bash|sh)[[:space:]]+-c[[:space:]]+ ]]; then
          segment="${segment#* -c }"
          segment="${segment#[\'\"]}"
          segment="${segment%[\'\"]}"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
      sudo|doas)
        local rest="${segment#$base_cmd}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        while [[ "$rest" == -* ]]; do
          case "$rest" in
            -u\ *|-g\ *|-C\ *)
              rest="${rest#* }"; rest="${rest#* }" ;;
            *)
              rest="${rest#* }" ;;
          esac
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        while [[ "$rest" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
          rest="${rest#* }"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        if [[ -n "$rest" ]]; then
          segment="$rest"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
      env)
        local rest="${segment#env}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        while [[ "$rest" == -* ]]; do
          rest="${rest#* }"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        while [[ "$rest" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
          rest="${rest#* }"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        if [[ -n "$rest" ]]; then
          segment="$rest"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
      time|nice|ionice|nohup|strace|ltrace|xargs|caffeinate|exec|command)
        local rest="${segment#$base_cmd}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        while [[ "$rest" == -* ]]; do
          rest="${rest#* }"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        if [[ -n "$rest" ]]; then
          segment="$rest"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
      watch|timeout)
        # These take flags + a positional arg before the command
        # watch -n 5 df -h → skip "watch", flags, then the interval/duration
        local rest="${segment#$base_cmd}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        while [[ "$rest" == -* ]]; do
          case "$rest" in
            -n\ *|-s\ *|--interval\ *|--signal\ *)
              rest="${rest#* }"; rest="${rest#* }" ;;
            *)
              rest="${rest#* }" ;;
          esac
          rest="${rest#"${rest%%[![:space:]]*}"}"
        done
        # Skip the positional arg (interval for watch, duration for timeout)
        if [[ "$rest" =~ ^[0-9] ]]; then
          rest="${rest#* }"
          rest="${rest#"${rest%%[![:space:]]*}"}"
        fi
        if [[ -n "$rest" ]]; then
          segment="$rest"
          base_cmd="${segment%% *}"
          base_cmd="${base_cmd##*/}"
          unwrapped=true
        fi
        ;;
    esac
  done

  local info
  info=$(_lookup "$base_cmd")
  local emoji="${info%% *}"
  local rest="${info#* }"
  local bg="${rest%% *}"
  local fg="${rest##* }"

  # Chunk long segments into per-line styled spans. Claude Code's TUI only
  # applies bg to the first visual line of a styled span, so a wrap-within-
  # span loses styling on the overflow. Emitting each chunk on its own line
  # keeps every span self-contained and fully highlighted.
  local prefix=""
  [[ "$emoji" != "_" ]] && prefix=" ${emoji}"
  local style="${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m"
  local first_budget=$((CHUNK_WIDTH - ${#prefix} - 1))
  local out="" sep=" " pfx="$prefix" budget=$first_budget
  local remaining="$segment" chunk
  while [[ -n "$remaining" ]]; do
    if [[ ${#remaining} -le $budget ]]; then
      chunk="$remaining"
      remaining=""
    else
      chunk="${remaining:0:$budget}"
      [[ "$chunk" == *" "* ]] && chunk="${chunk% *}"
      remaining="${remaining:${#chunk}}"
      remaining="${remaining# }"
    fi
    out+="${sep}${style}${pfx} ${chunk} ${RESET}"
    sep=$'\n '
    pfx=""
    budget=$CHUNK_WIDTH
  done
  printf '%s' "$out"
}

# --- Main ---

# Render the annotated command
annotated=$(render_command "$command")

# JSON-escape: backslash first, then quotes, then control chars (RFC 8259)
json_escaped="$annotated"
json_escaped="${json_escaped//\\/\\\\}"
json_escaped="${json_escaped//\"/\\\"}"
json_escaped="${json_escaped//$'\033'/\\u001b}"
json_escaped="${json_escaped//$'\n'/\\n}"
json_escaped="${json_escaped//$'\r'/\\r}"
json_escaped="${json_escaped//$'\t'/\\t}"
# Strip remaining control chars U+0000-U+001F (except those already escaped above)
json_escaped=$(printf '%s' "$json_escaped" | tr -d '\000-\010\013\014\016-\032\034-\037')

echo "{\"systemMessage\": \"${json_escaped}\"}"
