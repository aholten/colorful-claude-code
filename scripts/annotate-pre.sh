#!/usr/bin/env bash

# Bash Annotator — PreToolUse hook for Claude Code
# Adds colored emoji annotations to Bash commands via systemMessage.
# Zero dependencies. Pure bash. No special fonts needed.
#
# Runs main only when executed directly; test.sh sources this file to
# unit-test _lookup, _lookup_op, render_command, and _render_segment.

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

# Chunk budget for styled spans. Claude Code does not pass terminal size or
# a TTY through to hooks (COLUMNS unset, /dev/tty unavailable), so this is
# config, not detected. 60 fits ~85-col setups; wider terminals can raise
# via COLORFUL_CHUNK_WIDTH.
CHUNK_WIDTH="${COLORFUL_CHUNK_WIDTH:-60}"
[[ "$CHUNK_WIDTH" =~ ^[0-9]+$ ]] || CHUNK_WIDTH=60
[[ "$CHUNK_WIDTH" -lt 20 ]] && CHUNK_WIDTH=20

# Color mode: 24-bit truecolor allows exact alpha blends for the nesting
# transparency effect; 256-color is the fallback. Auto-detected from
# COLORTERM, overridable via COLORFUL_COLOR_MODE=truecolor|256.
COLOR_MODE="${COLORFUL_COLOR_MODE:-}"
if [[ "$COLOR_MODE" != "truecolor" && "$COLOR_MODE" != "256" ]]; then
  case "${COLORTERM:-}" in
    *truecolor*|*24bit*) COLOR_MODE=truecolor ;;
    *)                   COLOR_MODE=256 ;;
  esac
fi

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

# --- Nesting-depth dimming ---
# Content inside matched delimiter pairs ("...", '...', `...`, (...), {...})
# renders with the segment's bg stepped toward the terminal background, one
# step per nesting level (capped at two), so pairs and their nesting read at
# a glance. Variants are hand-picked per palette color in the 6x6x6 cube to
# stay CVD-safe; fg flips to a light tone where the dimmed bg would lose
# contrast against the base fg.

# Returns "bg fg" for a base bg/fg at the given depth (0 = full strength)
_depth_style() {
  local bg="$1" fg="$2" depth="$3"
  if [[ "$depth" -le 0 ]]; then
    echo "$bg $fg"
    return 0
  fi
  [[ "$depth" -gt 2 ]] && depth=2
  case "$bg" in
    160) [[ "$depth" -eq 1 ]] && echo "124 230" || echo "88 250"  ;;  # red
    214) [[ "$depth" -eq 1 ]] && echo "172 16"  || echo "130 230" ;;  # orange
    227) [[ "$depth" -eq 1 ]] && echo "184 16"  || echo "142 230" ;;  # yellow
    29)  [[ "$depth" -eq 1 ]] && echo "23 230"  || echo "22 250"  ;;  # blu-green
    81)  [[ "$depth" -eq 1 ]] && echo "38 230"  || echo "24 250"  ;;  # sky blue
    25)  [[ "$depth" -eq 1 ]] && echo "24 230"  || echo "17 250"  ;;  # blue
    175) [[ "$depth" -eq 1 ]] && echo "132 230" || echo "96 250"  ;;  # red-purple
    135) [[ "$depth" -eq 1 ]] && echo "97 230"  || echo "60 250"  ;;  # purple
    240) [[ "$depth" -eq 1 ]] && echo "236 250" || echo "233 247" ;;  # gray
    *)   echo "$bg $fg" ;;
  esac
}

# Truecolor variant: real Okabe-Ito RGB values, alpha-blended toward an
# assumed dark terminal background (18,18,18) so nested content reads as
# partially transparent — depth 1 at 55% opacity, depth 2 at 30%. Terminals
# can't render actual transparency or dithering behind glyphs (one solid bg
# per cell), so the blend bakes the effect into the color itself.
# Returns "r g b fg", or "" when the bg has no RGB mapping (caller falls
# back to the 256-color table).
_depth_rgb() {
  local bg="$1" fg="$2" depth="$3"
  local rgb
  case "$bg" in
    160) rgb="213 94 0"    ;;  # vermillion
    214) rgb="230 159 0"   ;;  # orange
    227) rgb="240 228 66"  ;;  # yellow
    29)  rgb="0 158 115"   ;;  # bluish green
    81)  rgb="86 180 233"  ;;  # sky blue
    25)  rgb="0 114 178"   ;;  # blue
    175) rgb="204 121 167" ;;  # reddish purple
    135) rgb="154 91 210"  ;;  # purple
    240) rgb="88 88 88"    ;;  # gray
    236) rgb="48 48 48"    ;;  # operator gray
    *)   echo ""; return 0 ;;
  esac
  local r g b
  read -r r g b <<< "$rgb"
  if [[ "$depth" -le 0 ]]; then
    echo "$r $g $b $fg"
    return 0
  fi
  local a=55 df=230 tb=18
  if [[ "$depth" -ge 2 ]]; then a=30; df=250; fi
  echo "$(( (tb * (100 - a) + r * a) / 100 )) \
$(( (tb * (100 - a) + g * a) / 100 )) \
$(( (tb * (100 - a) + b * a) / 100 )) ${df}"
}

# Emits the ANSI style sequence for a base bg/fg at the given depth,
# preferring truecolor alpha blends when the terminal supports them
_span_style() {
  local s
  if [[ "$COLOR_MODE" == "truecolor" ]]; then
    s=$(_depth_rgb "$1" "$2" "$3")
    if [[ -n "$s" ]]; then
      local r g b f
      read -r r g b f <<< "$s"
      printf '%s' "${ESC}[48;2;${r};${g};${b}m${ESC}[38;5;${f}m"
      return 0
    fi
  fi
  s=$(_depth_style "$1" "$2" "$3")
  printf '%s' "${ESC}[48;5;${s%% *}m${ESC}[38;5;${s##* }m"
}

# The two helpers below run inside _render_segment's word-walk and rely on
# bash dynamic scoping to share its locals: out, line_len, wbuf, wlen,
# wstart_style, budget.

# Append the buffered word to the current line, breaking the line first when
# it doesn't fit. Claude Code's TUI only applies bg to the first visual line
# of a styled span, so no span may wrap — every line is opened with the style
# active at its first word and closed with RESET before the newline.
_flush_word() {
  [[ "$wlen" -eq 0 ]] && return 0
  if [[ "$line_len" -gt 0 && $((line_len + 1 + wlen)) -gt "$budget" ]]; then
    out+=" ${RESET}"$'\n'" ${wstart_style}"
    line_len=0
  fi
  out+=" $wbuf"
  line_len=$((line_len + wlen + 1))
  wbuf=""
  wlen=0
  return 0
}

# Append visible characters to the word buffer, hard-flushing words that
# exceed the chunk budget on their own (URLs, long paths)
_wput() {
  wbuf+="$1"
  wlen=$((wlen + ${#1}))
  [[ "$wlen" -ge "$budget" ]] && _flush_word
  return 0
}

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

  local prefix=""
  [[ "$emoji" != "_" ]] && prefix=" ${emoji}"

  # Walk the segment character by character, dimming the bg one step per
  # nested delimiter level (see _depth_style) and flushing word by word so
  # no styled span wraps within a visual line. Quote semantics follow bash:
  # nothing nests inside '...' or `...`; inside "..." only $( and ${ open a
  # level. Unbalanced closers are rendered literally.
  local depth=0 in_single=0 in_double=0 in_backtick=0 dq_base=0
  local budget=$CHUNK_WIDTH
  local cur_style
  cur_style=$(_span_style "$bg" "$fg" 0)
  local out=" ${cur_style}${prefix}"
  local line_len=${#prefix}
  local wbuf="" wlen=0 wstart_style="$cur_style"
  local i=0 len=${#segment} ch prev

  while [[ $i -lt $len ]]; do
    ch="${segment:$i:1}"
    [[ "$wlen" -eq 0 ]] && wstart_style="$cur_style"

    # Word boundary
    if [[ "$ch" == ' ' ]]; then
      _flush_word
      i=$((i + 1))
      continue
    fi

    # Backslash escape — copy both characters, no state change
    if [[ "$ch" == '\' && $i -lt $((len - 1)) ]]; then
      _wput "${segment:$i:2}"
      i=$((i + 2))
      continue
    fi

    # Inside single quotes / backticks everything is literal until the closer
    if [[ $in_single -eq 1 ]]; then
      _wput "$ch"
      if [[ "$ch" == "'" ]]; then
        in_single=0
        depth=$((depth - 1))
        cur_style=$(_span_style "$bg" "$fg" "$depth")
        wbuf+="$cur_style"
      fi
      i=$((i + 1))
      continue
    fi
    if [[ $in_backtick -eq 1 ]]; then
      _wput "$ch"
      if [[ "$ch" == '`' ]]; then
        in_backtick=0
        depth=$((depth - 1))
        cur_style=$(_span_style "$bg" "$fg" "$depth")
        wbuf+="$cur_style"
      fi
      i=$((i + 1))
      continue
    fi

    prev=""
    [[ $i -gt 0 ]] && prev="${segment:$((i-1)):1}"

    case "$ch" in
      "'")
        if [[ $in_double -eq 1 ]]; then
          _wput "$ch"   # literal inside double quotes
        else
          depth=$((depth + 1))
          cur_style=$(_span_style "$bg" "$fg" "$depth")
          wbuf+="$cur_style"
          _wput "$ch"
          in_single=1
        fi
        ;;
      '"')
        if [[ $in_double -eq 1 ]]; then
          _wput "$ch"
          in_double=0
          depth=$((depth - 1))
          cur_style=$(_span_style "$bg" "$fg" "$depth")
          wbuf+="$cur_style"
        else
          depth=$((depth + 1))
          cur_style=$(_span_style "$bg" "$fg" "$depth")
          wbuf+="$cur_style"
          _wput "$ch"
          in_double=1
          dq_base=$depth
        fi
        ;;
      '`')
        depth=$((depth + 1))
        cur_style=$(_span_style "$bg" "$fg" "$depth")
        wbuf+="$cur_style"
        _wput "$ch"
        in_backtick=1
        ;;
      '('|'{')
        # Inside double quotes only $( and ${ open a level
        if [[ $in_double -eq 1 && "$prev" != '$' ]]; then
          _wput "$ch"
        else
          depth=$((depth + 1))
          cur_style=$(_span_style "$bg" "$fg" "$depth")
          wbuf+="$cur_style"
          _wput "$ch"
        fi
        ;;
      ')'|'}')
        if [[ $depth -gt 0 ]] && [[ $in_double -eq 0 || $depth -gt $dq_base ]]; then
          _wput "$ch"
          depth=$((depth - 1))
          cur_style=$(_span_style "$bg" "$fg" "$depth")
          wbuf+="$cur_style"
        else
          _wput "$ch"
        fi
        ;;
      *)
        _wput "$ch"
        ;;
    esac
    i=$((i + 1))
  done

  _flush_word
  out+=" ${RESET}"
  printf '%s' "$out"
}

# --- Main ---

main() {
  local input command annotated json_escaped

  # Read JSON and extract command
  input=$(cat)
  command=$(_extract_json_string "$input" "command") || true
  [ -z "$command" ] && exit 0
  command=$(_unescape_json_string "$command")

  # Collapse whitespace to spaces so the annotation stays on a single visible
  # line. The executed command is unaffected — this only shapes the display.
  command="${command//[$'\n\r\t']/ }"
  while [[ "$command" == *"  "* ]]; do command="${command//  / }"; done

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
}

# Execute only when run directly (not sourced). Never break the tool call:
# any unexpected error exits 0 so the hook stays invisible on failure.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap 'exit 0' ERR
  main
fi
