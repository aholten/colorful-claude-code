#!/usr/bin/env bash

# Nerd Font detection — sourced by annotate-pre.sh.
# Sets FONT_ASK=true if no Nerd Fonts are found.

CACHE_DIR="$HOME/.cache/bash-annotator"
FONT_OK_FLAG="$CACHE_DIR/font-check-ok"

check_fonts() {
  # Already verified — skip
  [ -f "$FONT_OK_FLAG" ] && return 0

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
      if ls "$win_fonts"/*[Nn]erd* &>/dev/null 2>&1; then
        font_found=true
      fi
      ;;
  esac

  if [ "$font_found" = true ]; then
    touch "$FONT_OK_FLAG"
  else
    FONT_ASK=true
  fi
}
