#!/usr/bin/env bash

# Bash Annotator — PreToolUse hook for Claude Code
# Adds colored emoji annotations to Bash commands via systemMessage.
# Zero dependencies. Pure bash. No special fonts needed.

trap 'exit 0' ERR

# --- Read JSON and extract command ---
input=$(cat)
command=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"//')
[ -z "$command" ] && exit 0

# --- Emoji + color lookup ---
# Returns: EMOJI BG FG
# BG/FG are 256-color ANSI palette numbers

_lookup() {
  local cmd="$1"
  case "$cmd" in
    # Version control
    git)                echo "🔀 202 17"  ;;
    gh)                 echo "🐙 238 255" ;;

    # File navigation
    cd)                 echo "📁 33 230"  ;;
    ls|exa|eza|lsd)     echo "📋 33 230"  ;;
    tree)               echo "🌳 33 230"  ;;
    pwd)                echo "📍 33 230"  ;;

    # File reading
    cat|bat)            echo "🐱 252 17"  ;;
    head)               echo "🔝 252 17"  ;;
    tail)               echo "🔚 252 17"  ;;
    less|more)          echo "📖 252 17"  ;;
    wc)                 echo "📄 252 17"  ;;

    # File create/update
    touch)              echo "👆 34 230"  ;;
    mkdir)              echo "📂 34 230"  ;;
    cp)                 echo "📄 34 230"  ;;
    mv)                 echo "📤 34 230"  ;;
    chmod|chown)        echo "🔒 34 230"  ;;
    ln)                 echo "🔗 34 230"  ;;

    # File delete
    rm|rmdir)           echo "🗑 196 230"  ;;

    # Searching
    grep|rg|ag)         echo "🔍 178 17"  ;;
    find|fd)            echo "🔎 178 17"  ;;
    locate)             echo "🔎 178 17"  ;;

    # Text processing
    sed|awk)            echo "✏ 135 230"  ;;
    sort)               echo "📊 135 230" ;;
    uniq|cut|tr)        echo "✏ 135 230"  ;;
    jq|yq)              echo "✏ 135 230"  ;;
    xargs)              echo "✏ 135 230"  ;;

    # Building
    make|cmake|ninja)   echo "🔨 136 230" ;;
    gcc|g++|cc|clang)   echo "⚙ 136 230"  ;;

    # Script execution
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

    # Testing
    pytest|jest|vitest|mocha|playwright|rspec) echo "🧪 34 230" ;;

    # Package management
    npm|npx)            echo "📦 160 230" ;;
    yarn|pnpm)          echo "📦 160 230" ;;
    pip|pip3|pipx)      echo "🐍 160 230" ;;
    poetry|pdm|uv)      echo "🐍 160 230" ;;
    gem|bundle)          echo "💎 160 230" ;;
    gradle|mvn)         echo "☕ 160 230" ;;
    brew)               echo "🍺 160 230" ;;
    apt|apt-get|yum|dnf|pacman) echo "📦 160 230" ;;

    # HTTP
    curl|wget|httpie)   echo "🌐 23 230"  ;;

    # Networking
    ssh|scp|sftp)       echo "🔑 39 17"   ;;
    rsync)              echo "📄 39 17"   ;;
    ping|traceroute)    echo "🌐 39 17"   ;;

    # Archiving
    tar|zip|unzip|gzip|gunzip) echo "🗜 208 17" ;;

    # Output
    echo|printf)        echo "💬 37 230"  ;;

    # Process management
    ps|top|htop)        echo "📊 53 230"  ;;
    kill|killall)       echo "💀 53 230"  ;;
    jobs|fg|bg)         echo "📊 53 230"  ;;

    # Elevated
    sudo)               echo "⚡ 196 230" ;;

    # Containers
    docker|podman)      echo "🐳 62 230"  ;;
    kubectl|k9s|helm)   echo "☸ 62 230"   ;;
    terraform|tofu)     echo "🏛 62 230"   ;;

    # Cloud
    aws)                echo "☁ 208 17"   ;;
    gcloud|gsutil)      echo "☁ 33 230"   ;;
    az)                 echo "☁ 32 230"   ;;

    # System
    systemctl|service)  echo "⚙ 240 255"  ;;
    journalctl)         echo "📜 240 255" ;;
    crontab)            echo "⏰ 240 255" ;;
    df|du|free)         echo "💾 240 255" ;;
    env|export|source)  echo "🌍 240 255" ;;

    # Editors
    vi|vim|nvim)        echo "✏ 28 230"   ;;
    nano)               echo "✏ 240 255"  ;;
    code)               echo "💻 32 230"  ;;
    emacs)              echo "✏ 97 230"   ;;

    # Databases
    psql)               echo "🗄 60 230"   ;;
    mysql|mariadb)      echo "🗄 67 230"   ;;
    redis-cli)          echo "🗄 160 230"  ;;
    sqlite3)            echo "🗄 33 230"   ;;
    mongosh)            echo "🗄 34 230"   ;;

    # Linters
    eslint|prettier|shellcheck|ruff|black|mypy) echo "💡 214 17" ;;

    # Default
    *)                  echo "_ 240 255"  ;;
  esac
}

# Operator lookup
_lookup_op() {
  case "$1" in
    '&&') echo "✅ 235 250" ;;
    '||') echo "⚠ 235 250"  ;;
    '|')  echo "🔗 235 250" ;;
    ';')  echo "⏩ 235 250" ;;
    *)    echo "_ 235 250"  ;;
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

  while [[ $i -lt $len ]]; do
    local ch="${input:$i:1}"
    local next="${input:$((i+1)):1}"

    # Quote tracking
    if [[ "$ch" == "'" && $in_double_quote -eq 0 ]]; then
      in_single_quote=$(( 1 - in_single_quote ))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ "$ch" == '"' && $in_single_quote -eq 0 ]]; then
      in_double_quote=$(( 1 - in_double_quote ))
      buf+="$ch"; i=$((i + 1)); continue
    fi
    if [[ $in_single_quote -eq 1 || $in_double_quote -eq 1 ]]; then
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
      # Render operator
      local op_info
      op_info=$(_lookup_op "$op")
      local op_emoji="${op_info%% *}"
      local rest="${op_info#* }"
      local op_bg="${rest%% *}"
      local op_fg="${rest##* }"
      output+=" ${ESC}[48;5;${op_bg}m${ESC}[38;5;${op_fg}m ${op_emoji} ${op} ${RESET}"
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

  # Handle command wrappers
  case "$base_cmd" in
    bash|sh)
      # Check for bash -c '...'
      if [[ "$segment" =~ ^(bash|sh)[[:space:]]+-c[[:space:]]+ ]]; then
        local inner="${segment#* -c }"
        inner="${inner#[\'\"]}"
        inner="${inner%[\'\"]}"
        base_cmd="${inner%% *}"
        base_cmd="${base_cmd##*/}"
      fi
      ;;
  esac

  local info
  info=$(_lookup "$base_cmd")
  local emoji="${info%% *}"
  local rest="${info#* }"
  local bg="${rest%% *}"
  local fg="${rest##* }"

  if [[ "$emoji" == "_" ]]; then
    printf ' %s' "${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${segment} ${RESET}"
  else
    printf ' %s' "${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${emoji} ${segment} ${RESET}"
  fi
}

# --- Main ---

# Render the annotated command
annotated=$(render_command "$command")

# JSON-escape: backslash first, then quotes, then ESC bytes, then control chars
json_escaped="$annotated"
json_escaped="${json_escaped//\\/\\\\}"
json_escaped="${json_escaped//\"/\\\"}"
json_escaped="${json_escaped//$'\033'/\\u001b}"
json_escaped="${json_escaped//$'\n'/\\n}"
json_escaped="${json_escaped//$'\r'/\\r}"
json_escaped="${json_escaped//$'\t'/\\t}"

echo "{\"systemMessage\": \"${json_escaped}\"}"

exit 0
