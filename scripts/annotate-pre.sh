#!/usr/bin/env bash

# Bash Annotator — PreToolUse hook for Claude Code
# Prepends brand-colored Nerd Font icons to Bash commands.
# Zero dependencies. Pure bash.

# Safety net — never block command execution
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Read JSON and extract command first (needed for updatedInput) ---
input=$(cat)
command=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"//')
[ -z "$command" ] && exit 0

# --- Font check (first run only) ---
FONT_ASK=""
source "$SCRIPT_DIR/font-check.sh"
check_fonts

# If fonts are missing, ask user to install (replaces the original command)
if [ "$FONT_ASK" = "true" ]; then
  install_cmd="bash ${SCRIPT_DIR}/install-font.sh"

  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Bash Annotator: Nerd Fonts not detected. Install FiraCode Nerd Font and configure your terminal?","updatedInput":{"command":"%s"}}}\n' "$install_cmd"
  exit 0
fi

# --- Parse base command ---

parse_base_command() {
  local cmd="$1"

  # Unwrap bash -c '...' / sh -c '...'
  case "$cmd" in
    bash\ -c\ *|sh\ -c\ *)
      cmd="${cmd#* -c }"
      cmd="${cmd#[\'\"]}"
      cmd="${cmd%[\'\"]}"
      ;;
  esac

  # For chains and pipes, use the first command
  cmd="${cmd%%&&*}"
  cmd="${cmd%%||*}"
  cmd="${cmd%%;*}"
  cmd="${cmd%%|*}"

  # Trim whitespace
  cmd="${cmd#"${cmd%%[! ]*}"}"
  cmd="${cmd%"${cmd##*[! ]}"}"

  # Extract binary name
  local bin="${cmd%% *}"
  echo "${bin##*/}"
}

parse_full_command() {
  local cmd="$1"
  cmd="${cmd%%&&*}"
  cmd="${cmd%%||*}"
  cmd="${cmd%%;*}"
  cmd="${cmd%%|*}"
  cmd="${cmd#"${cmd%%[! ]*}"}"
  echo "$cmd" | { read -r a b _; echo "$a $b"; }
}

BASE_CMD=$(parse_base_command "$command")
FULL_CMD=$(parse_full_command "$command")

# --- Icon + color resolution ---
# ICON = JSON unicode escape for the Nerd Font glyph
# COLOR = 256-color palette number

ICON=""
COLOR=""

# Tier 1: Full command match
case "$FULL_CMD" in
  "git commit"*|"git merge"*|"git rebase"*)  ICON="\\ue702"; COLOR=202 ;;
  "git push"*|"git pull"*|"git fetch"*)       ICON="\\ue702"; COLOR=202 ;;
  "npm test"*|"npm run test"*)                 ICON="\\uf0c3"; COLOR=34  ;;
  "npm install"*|"npm ci"*)                    ICON="\\ue71e"; COLOR=160 ;;
  "docker build"*|"docker compose"*)           ICON="\\ue7b0"; COLOR=33  ;;
  "kubectl apply"*|"kubectl delete"*)          ICON="\\udb82\\udc8e"; COLOR=62 ;;
  "cargo test"*|"cargo build"*)                ICON="\\ue7a8"; COLOR=173 ;;
  "pip install"*|"pip3 install"*)              ICON="\\ue73c"; COLOR=33  ;;
  *)
    # Tier 2: Base command match
    case "$BASE_CMD" in

      # --- Version control ---
      git)                ICON="\\ue702"; COLOR=202 ;;
      gh)                 ICON="\\ue708"; COLOR=238 ;;

      # --- JavaScript / Node ---
      npm|npx)            ICON="\\ue71e"; COLOR=160 ;;
      node)               ICON="\\ue718"; COLOR=34  ;;
      yarn|pnpm)          ICON="\\ue71e"; COLOR=32  ;;
      bun)                ICON="\\ue76e"; COLOR=230 ;;
      deno)               ICON="\\ue628"; COLOR=240 ;;

      # --- Python ---
      python|python3)     ICON="\\ue73c"; COLOR=33  ;;
      pip|pip3|pipx)      ICON="\\ue73c"; COLOR=33  ;;
      poetry|pdm|uv)      ICON="\\ue73c"; COLOR=33  ;;
      pytest)             ICON="\\uf0c3"; COLOR=34  ;;
      ruff|black|mypy)    ICON="\\ue73c"; COLOR=33  ;;

      # --- Rust ---
      cargo|rustc|rustup) ICON="\\ue7a8"; COLOR=173 ;;

      # --- Go ---
      go)                 ICON="\\ue627"; COLOR=38  ;;

      # --- Ruby ---
      ruby|gem|bundle)    ICON="\\ue23e"; COLOR=160 ;;
      rails|rake|rspec)   ICON="\\ue23e"; COLOR=160 ;;

      # --- Java / JVM ---
      java|javac)         ICON="\\ue256"; COLOR=208 ;;
      gradle|mvn)         ICON="\\ue256"; COLOR=208 ;;
      kotlin|kotlinc)     ICON="\\ue634"; COLOR=99  ;;

      # --- C / C++ ---
      gcc|g++|cc|clang)   ICON="\\uf2db"; COLOR=25  ;;
      make|cmake|ninja)   ICON="\\uf085"; COLOR=245 ;;

      # --- Containers & orchestration ---
      docker|podman)      ICON="\\ue7b0"; COLOR=33  ;;
      kubectl|k9s|helm)   ICON="\\udb82\\udc8e"; COLOR=62 ;;
      terraform|tofu)     ICON="\\uf1b6"; COLOR=97  ;;

      # --- Cloud CLIs ---
      aws)                ICON="\\ue7ad"; COLOR=208 ;;
      gcloud|gsutil)      ICON="\\uf1a0"; COLOR=33  ;;
      az)                 ICON="\\ufd03"; COLOR=32  ;;

      # --- Network ---
      curl|wget|httpie)   ICON="\\uf0ac"; COLOR=39  ;;
      ssh|scp|sftp)       ICON="\\uf489"; COLOR=245 ;;
      rsync)              ICON="\\uf0c5"; COLOR=245 ;;
      ping|traceroute)    ICON="\\uf0ac"; COLOR=39  ;;

      # --- Search ---
      grep|rg|ag)         ICON="\\uf002"; COLOR=214 ;;
      find|fd)            ICON="\\uf002"; COLOR=214 ;;

      # --- File viewing ---
      cat|bat|less|more)  ICON="\\uf15c"; COLOR=245 ;;
      head|tail|wc)       ICON="\\uf15c"; COLOR=245 ;;

      # --- File management ---
      ls|exa|eza|lsd)     ICON="\\uf115"; COLOR=245 ;;
      cd)                 ICON="\\uf07b"; COLOR=245 ;;
      rm)                 ICON="\\uf1f8"; COLOR=160 ;;
      cp|mv)              ICON="\\uf0c5"; COLOR=245 ;;
      mkdir)              ICON="\\uf07c"; COLOR=245 ;;
      chmod|chown)        ICON="\\uf023"; COLOR=160 ;;
      tar|zip|unzip|gzip) ICON="\\uf187"; COLOR=245 ;;

      # --- Editors ---
      vi|vim|nvim)        ICON="\\ue62b"; COLOR=28  ;;
      nano)               ICON="\\uf044"; COLOR=245 ;;
      code)               ICON="\\ue70c"; COLOR=32  ;;
      emacs)              ICON="\\ue632"; COLOR=97  ;;

      # --- Text processing ---
      sed|awk|jq|yq)      ICON="\\uf040"; COLOR=245 ;;
      sort|uniq|cut|tr)   ICON="\\uf040"; COLOR=245 ;;
      xargs)              ICON="\\uf040"; COLOR=245 ;;

      # --- Databases ---
      psql)               ICON="\\ue76e"; COLOR=60  ;;
      mysql|mariadb)      ICON="\\ue704"; COLOR=67  ;;
      redis-cli)          ICON="\\ue76d"; COLOR=160 ;;
      sqlite3)            ICON="\\ue7c4"; COLOR=33  ;;
      mongosh)            ICON="\\ue7a4"; COLOR=34  ;;

      # --- System ---
      systemctl|service)  ICON="\\uf013"; COLOR=245 ;;
      journalctl)         ICON="\\uf1da"; COLOR=245 ;;
      crontab)            ICON="\\uf017"; COLOR=245 ;;
      ps|top|htop)        ICON="\\uf080"; COLOR=245 ;;
      kill|killall)       ICON="\\uf1e2"; COLOR=160 ;;
      df|du|free)         ICON="\\uf0a0"; COLOR=245 ;;
      env|export|source)  ICON="\\uf462"; COLOR=245 ;;
      sudo)               ICON="\\uf023"; COLOR=160 ;;

      # --- Testing ---
      jest|vitest|mocha)  ICON="\\uf0c3"; COLOR=34  ;;
      playwright)         ICON="\\uf0c3"; COLOR=34  ;;

      # --- Linters / formatters ---
      eslint|prettier)    ICON="\\uf0eb"; COLOR=214 ;;
      shellcheck)         ICON="\\uf0eb"; COLOR=214 ;;

      # --- Default ---
      *)                  ICON="\\uf489"; COLOR=245 ;;
    esac
    ;;
esac

# --- Build and emit systemMessage ---

# Truncate long commands for display
display_cmd="$command"
if [ ${#display_cmd} -gt 80 ]; then
  display_cmd="${display_cmd:0:77}..."
fi

# Escape the command text for safe JSON embedding
display_cmd="${display_cmd//\\/\\\\}"
display_cmd="${display_cmd//\"/\\\"}"

# Assemble: colored icon + reset + space + command text
message="\\u001b[38;5;${COLOR}m${ICON}\\u001b[0m ${display_cmd}"

echo "{\"systemMessage\": \"${message}\"}"

exit 0
