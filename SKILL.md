---
name: bash-annotator
description: "Annotate Bash tool commands with brand-colored Nerd Font icons in Claude Code. Use this skill when setting up bash annotation hooks, configuring command-to-icon mappings, customizing PreToolUse display, or troubleshooting missing icons in bash output. Also triggers when the user wants visual feedback on bash commands, wants to add custom tool icons, or asks about making their Claude Code terminal output more readable. Depends on the nerd-fonts skill for glyph rendering."
---

# Bash Annotator

Visual annotation layer for Claude Code's Bash tool. Prepends brand-colored Nerd Font icons to commands before execution.

**Zero dependencies.** Pure bash. No jq, no python, no node. Works on Linux, macOS, WSL, and Git Bash.

**Depends on:** `nerd-fonts` skill (font installation and terminal configuration).

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Claude Code Session                                     │
│                                                          │
│  User prompt → Claude decides to run Bash →              │
│                                                          │
│  ┌─────────────┐       ┌────────────────────────┐       │
│  │ PreToolUse   │──────▶│  annotate-pre.sh       │       │
│  │ Hook (Bash)  │ stdin │  1. grep command from   │       │
│  │              │ JSON  │     JSON stdin           │       │
│  │              │       │  2. resolve icon + color │       │
│  │              │       │  3. build systemMessage  │       │
│  │              │◀──────│  4. emit JSON to stdout  │       │
│  │              │ JSON  └────────────────────────┘       │
│  └─────────────┘                                         │
│         │  {"systemMessage": "<colored icon> command"}    │
│         │  (rendered in Claude Code's output)             │
│         ▼                                                │
│  ┌─────────────┐                                         │
│  │ Bash tool    │  (command executes normally)            │
│  │ executes     │                                         │
│  └─────────────┘                                         │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## Hook I/O Model

This is the critical piece. Claude Code hooks communicate via **JSON on stdin/stdout**, not raw terminal output.

**Input:** Hook receives JSON on stdin describing the tool call:
```json
{"tool_name":"Bash","input":{"command":"git status"},"session_id":"..."}
```

**Output:** Hook emits JSON to stdout with a `systemMessage` field:
```json
{"systemMessage": "\\u001b[38;5;202m\\ue702\\u001b[0m git status"}
```

Claude Code parses the JSON, interprets the unicode escapes, and renders the message with ANSI colors and Nerd Font glyphs inline.

### Escaping rules

All special characters must be JSON unicode escapes:

| What | Raw | In JSON systemMessage |
|------|-----|-----------------------|
| ANSI escape (ESC) | `\033` or `\x1b` | `\\u001b` |
| 256-color start | `\033[38;5;202m` | `\\u001b[38;5;202m` |
| Color reset | `\033[0m` | `\\u001b[0m` |
| Nerd Font glyph | `\ue702` | `\\ue702` |
| Surrogate pair glyph | `\udb82\udc8e` | `\\udb82\\udc8e` |
| Double quote in command | `"` | `\\\"` |
| Backslash in command | `\` | `\\\\` |

Note the double backslash in bash (`\\u001b`) which becomes a single backslash in the JSON output (`\u001b`), which the JSON parser then interprets as the ESC byte.

---

## Color System

Icons use **256-color ANSI escapes** via JSON unicode format:
```
\\u001b[38;5;{N}m{ICON}\\u001b[0m
```

### Brand Color Map

Tools are mapped to their closest 256-color palette match. Color reuse is intentional where brands share similar colors. Non-branded commands use semantic colors: red for anything destructive or privilege-related, gold for search/lint operations, green for test runners, gray for neutral utilities.

| Tool | Brand Hex | 256 Code | Color Name |
|------|-----------|----------|------------|
| **Git** | #F05032 | 202 | orange-red |
| **GitHub CLI** | #24292E | 238 | dark gray |
| **npm** | #CB3837 | 160 | red |
| **Node.js** | #339933 | 34 | green |
| **Yarn** | #2C8EBB | 32 | blue |
| **Bun** | #FBF0DF | 230 | cream |
| **Deno** | #000000 | 240 | dark gray |
| **Python** | #3776AB | 33 | blue |
| **Rust** | #DEA584 | 173 | copper |
| **Go** | #00ADD8 | 38 | cyan |
| **Ruby** | #CC342D | 160 | red |
| **Java** | #ED8B00 | 208 | orange |
| **Kotlin** | #7F52FF | 99 | purple |
| **C/C++** | #00599C | 25 | navy blue |
| **Docker** | #2496ED | 33 | blue |
| **Kubernetes** | #326CE5 | 62 | royal blue |
| **Terraform** | #7B42BC | 97 | purple |
| **AWS** | #FF9900 | 208 | orange |
| **GCP** | #4285F4 | 33 | blue |
| **Azure** | #0078D4 | 32 | blue |
| **Vim** | #019833 | 28 | dark green |
| **VS Code** | #007ACC | 32 | blue |
| **Emacs** | #7F5AB6 | 97 | purple |
| **PostgreSQL** | #336791 | 60 | steel blue |
| **MySQL** | #4479A1 | 67 | blue |
| **Redis** | #DC382D | 160 | red |
| **MongoDB** | #47A248 | 34 | green |
| **Make/build** | — | 245 | gray |
| **curl/network** | — | 39 | light blue |
| **ssh** | — | 245 | gray |
| **grep/search** | — | 214 | gold |
| **destructive (rm, kill)** | — | 160 | red |
| **privilege (sudo)** | — | 160 | red |
| **access (chmod, chown)** | — | 160 | red |
| **file ops** | — | 245 | gray |
| **test runners** | — | 34 | green |
| **linters** | — | 214 | gold |
| **default** | — | 245 | gray |

---

## Initialization: scripts/font-check.sh

One-time Nerd Font detection. Sourced by PreToolUse on first invocation.

```bash
#!/usr/bin/env bash

CACHE_DIR="$HOME/.cache/bash-annotator"
FONT_OK_FLAG="$CACHE_DIR/font-check-ok"
FONT_WARN_FLAG="$CACHE_DIR/font-check-warned"

check_fonts() {
  [ -f "$FONT_OK_FLAG" ] && return 0

  if [ -f "$FONT_WARN_FLAG" ]; then
    local now warn_time age
    now=$(date +%s)
    warn_time=$(stat -c %Y "$FONT_WARN_FLAG" 2>/dev/null || stat -f %m "$FONT_WARN_FLAG" 2>/dev/null || echo 0)
    age=$(( now - warn_time ))
    [ "$age" -lt 86400 ] && return 0
  fi

  mkdir -p "$CACHE_DIR"

  local font_found=false
  case "$(uname -s)" in
    Linux*)
      if command -v fc-list &>/dev/null && fc-list | grep -qi "nerd"; then
        font_found=true
      fi
      ;;
    Darwin*)
      if ls "$HOME/Library/Fonts/"*[Nn]erd* &>/dev/null || ls /Library/Fonts/*[Nn]erd* &>/dev/null; then
        font_found=true
      fi
      ;;
    MINGW*|MSYS*)
      local win_fonts="${LOCALAPPDATA:-/c/Users/$USERNAME/AppData/Local}/Microsoft/Windows/Fonts"
      if ls "$win_fonts"/*[Nn]erd* &>/dev/null; then
        font_found=true
      fi
      ;;
  esac

  if [ "$font_found" = true ]; then
    touch "$FONT_OK_FLAG"
  else
    # Emit warning as a systemMessage so it renders in Claude Code
    echo '{"systemMessage": "\\u26a0 Bash Annotator: Nerd Fonts not detected. Run: claude \\\"install nerd fonts\\\""}'
    touch "$FONT_WARN_FLAG"
  fi
}
```

---

## PreToolUse Hook: scripts/annotate-pre.sh

Fires before every Bash tool call. Extracts the command, resolves a brand-colored icon, emits a `systemMessage` JSON response.

```bash
#!/usr/bin/env bash

# Safety net — never block command execution
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Font check (first run only) ---
source "$SCRIPT_DIR/font-check.sh"
check_fonts

# --- Read JSON and extract command ---
input=$(cat)
command=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"//')
[ -z "$command" ] && exit 0

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

  # For chains, pick the most significant command
  case "$cmd" in
    *"&&"*|*"||"*|*";"*)
      local pattern
      for pattern in "git commit" "git push" "git merge" "npm test" "pytest" "cargo build" "make"; do
        case "$cmd" in
          *"$pattern"*)
            echo "${pattern%% *}"
            return
            ;;
        esac
      done
      cmd="${cmd%%&&*}"
      cmd="${cmd%%||*}"
      cmd="${cmd%%;*}"
      ;;
  esac

  # For pipes, use the first command
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

# --- Check ignore list ---
CONFIG_FILE="$HOME/.claude/bash-annotator.json"
if [ -f "$CONFIG_FILE" ]; then
  local_input="$(<"$CONFIG_FILE")"
  local ignore_section="${local_input#*\"ignore\"}"
  case "$ignore_section" in
    *"\"$BASE_CMD\""*)
      exit 0
      ;;
  esac
fi

# --- Icon + color resolution ---
# ICON = JSON unicode escape for the Nerd Font glyph
# COLOR = 256-color palette number

ICON=""
COLOR=""

# Custom override check
if [ -f "$CONFIG_FILE" ]; then
  local_input="$(<"$CONFIG_FILE")"
  local custom_section="${local_input#*\"custom_icons\"}"
  case "$custom_section" in
    *"\"$BASE_CMD\""*)
      local rest="${custom_section#*\"$BASE_CMD\":\"}"
      ICON="${rest%%\"*}"
      COLOR="245"
      ;;
  esac
fi

if [ -z "$ICON" ]; then

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
        git)                ICON="\\ue702"; COLOR=202 ;;  # orange-red
        gh)                 ICON="\\ue708"; COLOR=238 ;;  # dark gray

        # --- JavaScript / Node ---
        npm|npx)            ICON="\\ue71e"; COLOR=160 ;;  # red
        node)               ICON="\\ue718"; COLOR=34  ;;  # green
        yarn|pnpm)          ICON="\\ue71e"; COLOR=32  ;;  # blue
        bun)                ICON="\\ue76e"; COLOR=230 ;;  # cream
        deno)               ICON="\\ue628"; COLOR=240 ;;  # dark gray

        # --- Python ---
        python|python3)     ICON="\\ue73c"; COLOR=33  ;;  # blue
        pip|pip3|pipx)      ICON="\\ue73c"; COLOR=33  ;;  # blue
        poetry|pdm|uv)      ICON="\\ue73c"; COLOR=33  ;;  # blue
        pytest)             ICON="\\uf0c3"; COLOR=34  ;;  # green
        ruff|black|mypy)    ICON="\\ue73c"; COLOR=33  ;;  # blue

        # --- Rust ---
        cargo|rustc|rustup) ICON="\\ue7a8"; COLOR=173 ;;  # copper

        # --- Go ---
        go)                 ICON="\\ue627"; COLOR=38  ;;  # cyan

        # --- Ruby ---
        ruby|gem|bundle)    ICON="\\ue23e"; COLOR=160 ;;  # red
        rails|rake|rspec)   ICON="\\ue23e"; COLOR=160 ;;  # red

        # --- Java / JVM ---
        java|javac)         ICON="\\ue256"; COLOR=208 ;;  # orange
        gradle|mvn)         ICON="\\ue256"; COLOR=208 ;;  # orange
        kotlin|kotlinc)     ICON="\\ue634"; COLOR=99  ;;  # purple

        # --- C / C++ ---
        gcc|g++|cc|clang)   ICON="\\uf2db"; COLOR=25  ;;  # navy blue
        make|cmake|ninja)   ICON="\\uf085"; COLOR=245 ;;  # gray

        # --- Containers & orchestration ---
        docker|podman)      ICON="\\ue7b0"; COLOR=33  ;;  # blue
        kubectl|k9s|helm)   ICON="\\udb82\\udc8e"; COLOR=62 ;;  # royal blue
        terraform|tofu)     ICON="\\uf1b6"; COLOR=97  ;;  # purple

        # --- Cloud CLIs ---
        aws)                ICON="\\ue7ad"; COLOR=208 ;;  # orange
        gcloud|gsutil)      ICON="\\uf1a0"; COLOR=33  ;;  # blue
        az)                 ICON="\\ufd03"; COLOR=32  ;;  # blue

        # --- Network ---
        curl|wget|httpie)   ICON="\\uf0ac"; COLOR=39  ;;  # light blue
        ssh|scp|sftp)       ICON="\\uf489"; COLOR=245 ;;  # gray
        rsync)              ICON="\\uf0c5"; COLOR=245 ;;  # gray
        ping|traceroute)    ICON="\\uf0ac"; COLOR=39  ;;  # light blue

        # --- Search ---
        grep|rg|ag)         ICON="\\uf002"; COLOR=214 ;;  # gold
        find|fd)            ICON="\\uf002"; COLOR=214 ;;  # gold

        # --- File viewing ---
        cat|bat|less|more)  ICON="\\uf15c"; COLOR=245 ;;  # gray
        head|tail|wc)       ICON="\\uf15c"; COLOR=245 ;;  # gray

        # --- File management ---
        ls|exa|eza|lsd)     ICON="\\uf115"; COLOR=245 ;;  # gray
        cd)                 ICON="\\uf07b"; COLOR=245 ;;  # gray
        rm)                 ICON="\\uf1f8"; COLOR=160 ;;  # red — destructive
        cp|mv)              ICON="\\uf0c5"; COLOR=245 ;;  # gray
        mkdir)              ICON="\\uf07c"; COLOR=245 ;;  # gray
        chmod|chown)        ICON="\\uf023"; COLOR=160 ;;  # red — access control
        tar|zip|unzip|gzip) ICON="\\uf187"; COLOR=245 ;;  # gray

        # --- Editors ---
        vi|vim|nvim)        ICON="\\ue62b"; COLOR=28  ;;  # dark green
        nano)               ICON="\\uf044"; COLOR=245 ;;  # gray
        code)               ICON="\\ue70c"; COLOR=32  ;;  # blue
        emacs)              ICON="\\ue632"; COLOR=97  ;;  # purple

        # --- Text processing ---
        sed|awk|jq|yq)      ICON="\\uf040"; COLOR=245 ;;  # gray
        sort|uniq|cut|tr)   ICON="\\uf040"; COLOR=245 ;;  # gray
        xargs)              ICON="\\uf040"; COLOR=245 ;;  # gray

        # --- Databases ---
        psql)               ICON="\\ue76e"; COLOR=60  ;;  # steel blue
        mysql|mariadb)      ICON="\\ue704"; COLOR=67  ;;  # blue
        redis-cli)          ICON="\\ue76d"; COLOR=160 ;;  # red
        sqlite3)            ICON="\\ue7c4"; COLOR=33  ;;  # blue
        mongosh)            ICON="\\ue7a4"; COLOR=34  ;;  # green

        # --- System ---
        systemctl|service)  ICON="\\uf013"; COLOR=245 ;;  # gray
        journalctl)         ICON="\\uf1da"; COLOR=245 ;;  # gray
        crontab)            ICON="\\uf017"; COLOR=245 ;;  # gray
        ps|top|htop)        ICON="\\uf080"; COLOR=245 ;;  # gray
        kill|killall)       ICON="\\uf1e2"; COLOR=160 ;;  # red — destructive
        df|du|free)         ICON="\\uf0a0"; COLOR=245 ;;  # gray
        env|export|source)  ICON="\\uf462"; COLOR=245 ;;  # gray
        sudo)               ICON="\\uf023"; COLOR=160 ;;  # red — elevated privilege

        # --- Testing ---
        jest|vitest|mocha)  ICON="\\uf0c3"; COLOR=34  ;;  # green
        playwright)         ICON="\\uf0c3"; COLOR=34  ;;  # green

        # --- Linters / formatters ---
        eslint|prettier)    ICON="\\uf0eb"; COLOR=214 ;;  # gold
        shellcheck)         ICON="\\uf0eb"; COLOR=214 ;;  # gold

        # --- Default ---
        *)                  ICON="\\uf489"; COLOR=245 ;;  # gray
      esac
      ;;
  esac
fi

# --- Build and emit systemMessage ---

# Truncate long commands for display
display_cmd="$command"
if [ ${#display_cmd} -gt 80 ]; then
  display_cmd="${display_cmd:0:77}..."
fi

# Escape the command text for safe JSON embedding
# Handle backslashes first, then double quotes
display_cmd="${display_cmd//\\/\\\\}"
display_cmd="${display_cmd//\"/\\\"}"

# Assemble: colored icon + reset + space + command text
# \\u001b[38;5;{N}m  = start 256-color
# {ICON}              = Nerd Font glyph (JSON unicode escape)
# \\u001b[0m          = reset color
message="\\u001b[38;5;${COLOR}m${ICON}\\u001b[0m ${display_cmd}"

echo "{\"systemMessage\": \"${message}\"}"

exit 0
```

---

## Setup: setup.sh

One-time installation. Registers hooks, creates default config. Pure bash.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"

echo "Installing Bash Annotator..."

# 1. Ensure directories exist
mkdir -p "$CLAUDE_DIR"

# 2. Make scripts executable
chmod +x "$SCRIPT_DIR/scripts/annotate-pre.sh"
chmod +x "$SCRIPT_DIR/scripts/font-check.sh"

# 3. Register hooks
PRE_HOOK="$SCRIPT_DIR/scripts/annotate-pre.sh"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
  cat > "$CLAUDE_SETTINGS" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "$PRE_HOOK"
      }
    ]
  }
}
EOF
  echo "Created $CLAUDE_SETTINGS with hook."
else
  if grep -q "$PRE_HOOK" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "Hook already registered."
  else
    echo ""
    echo "Add the following to your $CLAUDE_SETTINGS under \"hooks\":"
    echo ""
    echo '  "PreToolUse": ['
    echo "    {\"matcher\": \"Bash\", \"command\": \"$PRE_HOOK\"}"
    echo '  ]'
    echo ""
    echo "Or run: claude /hooks to configure interactively."
  fi
fi

# 4. Create default config
CONFIG_FILE="$CLAUDE_DIR/bash-annotator.json"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  "custom_icons": {},
  "ignore": []
}
EOF
  echo "Created default config at $CONFIG_FILE"
fi

# 5. Font check
echo ""
source "$SCRIPT_DIR/scripts/font-check.sh"
check_fonts

echo ""
echo "Bash Annotator installed. Restart Claude Code to activate."
```

---

## Configuration

`~/.claude/bash-annotator.json`:

```json
{
  "custom_icons": {
    "mycli": "\\uf135",
    "deploy.sh": "\\uf0e7",
    "wrangler": "\\uf0c2"
  },
  "ignore": [
    "echo",
    "true",
    "false",
    "printf"
  ]
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `custom_icons` | object | `{}` | Command name → Nerd Font glyph as JSON unicode escape. Uses default gray (245). |
| `ignore` | array | `[]` | Commands that produce no annotation. |

---

## Performance

| Metric | Target | How |
|--------|--------|-----|
| Execution time | < 10ms | Pure bash. `grep` + `sed` for JSON parse. Case statement for icon lookup. |
| Dependencies | 0 | Bash only. `grep` and `sed` are bash builtins on all targets. |
| Failure mode | Silent | `trap 'exit 0' ERR` — never blocks command execution. |

---

## Edge Cases

### JSON extraction limitations

The `grep -o '"command":"[^"]*"'` approach breaks if the command value contains escaped quotes:
```json
{"input":{"command":"echo \"hello\""}}
```

This is acceptable for the MVP because:
- Most bash commands don't contain literal escaped quotes
- When they do, the hook silently fails to extract and exits cleanly
- The command still executes — only the annotation is skipped

For a future hardening pass, the char-by-char extractor from earlier iterations can replace the grep.

### Chained / piped commands

For chains, check for high-priority commands first (git commit > npm test > make). Fall back to first command. For pipes, use the first command.

### Long commands

Display truncated at 80 chars with `...` suffix.

### Special characters in commands

Backslashes and double quotes in the command text are escaped before embedding in the JSON systemMessage. This prevents malformed JSON output.

---

## Potential Future Optimizations

- **PostToolUse hook** — status icons (✓/✗) and context-aware output summaries
- **Truecolor mode** — exact brand hex codes via `\\u001b[38;2;R;G;Bm`
- **Custom colors** — per-command color overrides in config
- **Robust JSON extraction** — char-by-char parser for commands with escaped quotes
- **Timing display** — command duration via PostToolUse

---

## File Manifest

```
bash-annotator/
├── SKILL.md                          # This file
├── setup.sh                          # One-time install
└── scripts/
    ├── annotate-pre.sh               # PreToolUse hook
    └── font-check.sh                 # Nerd Font detection (sourced)
```
