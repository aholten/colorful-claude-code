#!/usr/bin/env bash
set -euo pipefail

# Install FiraCode Nerd Font and auto-configure the terminal.
# Cross-platform: Linux, macOS, WSL, Git Bash.

FONT_NAME="FiraCode"
FONT_DISPLAY="FiraCode Nerd Font"
FONT_DISPLAY_MONO="FiraCode Nerd Font Mono"
CACHE_DIR="$HOME/.cache/bash-annotator"

echo "Installing ${FONT_DISPLAY}..."

# --- Detect platform and terminal ---
OS="$(uname -s)"
case "$OS" in
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      PLATFORM="wsl"
    else
      PLATFORM="linux"
    fi
    ;;
  Darwin*)       PLATFORM="macos" ;;
  MINGW*|MSYS*)  PLATFORM="gitbash" ;;
  *)             PLATFORM="unknown" ;;
esac

# --- Download ---
VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": "//;s/".*//')
VERSION="${VERSION:-v3.3.0}"

DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${VERSION}/${FONT_NAME}.zip"
TMP_DIR=$(mktemp -d)

echo "Downloading ${FONT_NAME} Nerd Font ${VERSION}..."
if ! curl -fLo "${TMP_DIR}/${FONT_NAME}.zip" "$DOWNLOAD_URL"; then
  echo "ERROR: Download failed."
  rm -rf "$TMP_DIR"
  exit 1
fi

unzip -o "${TMP_DIR}/${FONT_NAME}.zip" -d "${TMP_DIR}/${FONT_NAME}/" -x "LICENSE*" "README*" "*.md" > /dev/null

# --- Install fonts (platform-specific) ---
case "$PLATFORM" in
  linux)
    INSTALL_DIR="$HOME/.local/share/fonts/${FONT_NAME}"
    mkdir -p "$INSTALL_DIR"
    cp "${TMP_DIR}/${FONT_NAME}"/*.ttf "$INSTALL_DIR/" 2>/dev/null || true
    if command -v fc-cache &>/dev/null; then
      fc-cache -f > /dev/null 2>&1
    fi
    echo "Installed to $INSTALL_DIR"
    ;;
  macos)
    INSTALL_DIR="$HOME/Library/Fonts"
    mkdir -p "$INSTALL_DIR"
    cp "${TMP_DIR}/${FONT_NAME}"/*.ttf "$INSTALL_DIR/" 2>/dev/null || true
    echo "Installed to $INSTALL_DIR"
    ;;
  wsl)
    WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
    WIN_FONT_DIR="/mnt/c/Users/${WIN_USER}/AppData/Local/Microsoft/Windows/Fonts"
    mkdir -p "$WIN_FONT_DIR"
    cp "${TMP_DIR}/${FONT_NAME}"/*.ttf "$WIN_FONT_DIR/" 2>/dev/null || true
    echo "Installed to $WIN_FONT_DIR"

    # Register fonts in Windows Registry from WSL
    WIN_FONT_DIR_WIN=$(wslpath -w "$WIN_FONT_DIR" 2>/dev/null)
    if [ -n "$WIN_FONT_DIR_WIN" ]; then
      BAT_FILE=$(mktemp /tmp/regfonts.XXXXXX.bat)
      cat > "$BAT_FILE" << BATEOF
@echo off
set "FONTDIR=${WIN_FONT_DIR_WIN}"
set "REGKEY=HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
for %%f in ("%FONTDIR%\\${FONT_NAME}*.ttf") do (
    reg add "%REGKEY%" /v "%%~nf (TrueType)" /t REG_SZ /d "%%f" /f
)
BATEOF
      BAT_WIN=$(wslpath -w "$BAT_FILE")
      cmd.exe /c "$BAT_WIN" > /dev/null 2>&1 || true
      rm -f "$BAT_FILE"
    fi
    echo "Registered fonts in Windows Registry."
    ;;
  gitbash)
    WIN_FONT_DIR="${LOCALAPPDATA}/Microsoft/Windows/Fonts"
    if [ -z "$WIN_FONT_DIR" ] || [ "$WIN_FONT_DIR" = "/Microsoft/Windows/Fonts" ]; then
      WIN_FONT_DIR="/c/Users/$(whoami)/AppData/Local/Microsoft/Windows/Fonts"
    fi
    mkdir -p "$WIN_FONT_DIR"
    cp "${TMP_DIR}/${FONT_NAME}"/*.ttf "$WIN_FONT_DIR/" 2>/dev/null || true
    echo "Installed to $WIN_FONT_DIR"

    # Register fonts in Windows Registry via .bat to avoid Git Bash escaping issues
    WIN_FONT_DIR_WIN=$(cygpath -w "$WIN_FONT_DIR")
    BAT_FILE=$(mktemp /tmp/regfonts.XXXXXX.bat)
    cat > "$BAT_FILE" << BATEOF
@echo off
set "FONTDIR=${WIN_FONT_DIR_WIN}"
set "REGKEY=HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
for %%f in ("%FONTDIR%\\${FONT_NAME}*.ttf") do (
    reg add "%REGKEY%" /v "%%~nf (TrueType)" /t REG_SZ /d "%%f" /f
)
BATEOF
    cmd.exe //c "$(cygpath -w "$BAT_FILE")" > /dev/null 2>&1 || true
    rm -f "$BAT_FILE"
    echo "Registered fonts in Windows Registry."
    ;;
  *)
    echo "Unknown platform: $OS. Copy fonts manually from ${TMP_DIR}/${FONT_NAME}/"
    rm -rf "$TMP_DIR"
    exit 1
    ;;
esac

rm -rf "$TMP_DIR"
echo "Font files installed."

# --- Auto-configure terminal ---
echo "Configuring terminal..."

configure_mintty() {
  local rc="$HOME/.minttyrc"
  if [ -f "$rc" ]; then
    cp "$rc" "${rc}.bak"
  else
    touch "$rc"
  fi
  if grep -q "^Font=" "$rc"; then
    sed -i "s/^Font=.*/Font=$FONT_DISPLAY/" "$rc"
  else
    echo "Font=$FONT_DISPLAY" >> "$rc"
  fi
  if grep -q "^FontHeight=" "$rc"; then
    sed -i "s/^FontHeight=.*/FontHeight=12/" "$rc"
  else
    echo "FontHeight=12" >> "$rc"
  fi
  if grep -q "^Charwidth=" "$rc"; then
    sed -i "s/^Charwidth=.*/Charwidth=ambig-wide/" "$rc"
  else
    echo "Charwidth=ambig-wide" >> "$rc"
  fi
  echo "Configured Git Bash (.minttyrc)."
}

configure_windows_terminal() {
  # Find Windows Terminal settings.json
  local wt_settings=""
  local wt_base="${LOCALAPPDATA}/Packages"
  if [ -z "$wt_base" ] || [ ! -d "$wt_base" ]; then
    wt_base="/c/Users/$(whoami)/AppData/Local/Packages"
  fi
  # Check both stable and preview
  for pkg in "Microsoft.WindowsTerminal_8wekyb3d8bbwe" "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe"; do
    local candidate="$wt_base/$pkg/LocalState/settings.json"
    if [ -f "$candidate" ]; then
      wt_settings="$candidate"
      break
    fi
  done

  if [ -n "$wt_settings" ]; then
    cp "$wt_settings" "${wt_settings}.bak"
    if command -v python3 &>/dev/null || command -v python &>/dev/null; then
      local py_cmd
      py_cmd=$(command -v python3 || command -v python)
      "$py_cmd" -c "
import json, sys
with open(r'''$wt_settings''', 'r') as f:
    s = json.load(f)
for p in s.get('profiles', {}).get('list', []):
    p.setdefault('font', {})['face'] = '$FONT_DISPLAY'
with open(r'''$wt_settings''', 'w') as f:
    json.dump(s, f, indent=4)
print('Configured Windows Terminal.')
"
    else
      echo "Windows Terminal: Set font manually — Settings > Profile > Appearance > Font face > $FONT_DISPLAY"
    fi
  fi
}

configure_vscode() {
  local settings=""
  if [ -f "$HOME/.config/Code/User/settings.json" ]; then
    settings="$HOME/.config/Code/User/settings.json"
  elif [ -f "$HOME/Library/Application Support/Code/User/settings.json" ]; then
    settings="$HOME/Library/Application Support/Code/User/settings.json"
  elif [ -n "$APPDATA" ] && [ -f "$APPDATA/Code/User/settings.json" ]; then
    settings="$APPDATA/Code/User/settings.json"
  fi

  if [ -n "$settings" ]; then
    cp "$settings" "${settings}.bak"
    if grep -q 'terminal.integrated.fontFamily' "$settings"; then
      sed -i.tmp "s/\"terminal.integrated.fontFamily\".*/\"terminal.integrated.fontFamily\": \"$FONT_DISPLAY_MONO\",/" "$settings"
      rm -f "${settings}.tmp"
    else
      sed -i.tmp "s/^{/{\\n  \"terminal.integrated.fontFamily\": \"$FONT_DISPLAY_MONO\",/" "$settings"
      rm -f "${settings}.tmp"
    fi
    echo "Configured VS Code terminal."
  fi
}

configure_alacritty() {
  local conf="$HOME/.config/alacritty/alacritty.toml"
  if [ -f "$conf" ]; then
    cp "$conf" "${conf}.bak"
    if grep -q '^\[font\.normal\]' "$conf"; then
      sed -i.tmp '/^\[font\.normal\]/,/^family/ s/^family.*/family = "'"$FONT_DISPLAY_MONO"'"/' "$conf"
    else
      printf '\n[font.normal]\nfamily = "%s"\n' "$FONT_DISPLAY_MONO" >> "$conf"
    fi
    rm -f "${conf}.tmp"
    echo "Configured Alacritty."
  fi
}

configure_kitty() {
  local conf="$HOME/.config/kitty/kitty.conf"
  if [ -f "$conf" ]; then
    cp "$conf" "${conf}.bak"
    if grep -q '^font_family' "$conf"; then
      sed -i.tmp "s/^font_family.*/font_family $FONT_DISPLAY_MONO/" "$conf"
    else
      echo "font_family $FONT_DISPLAY_MONO" >> "$conf"
    fi
    rm -f "${conf}.tmp"
    echo "Configured Kitty."
  fi
}

configure_ghostty() {
  local conf="$HOME/.config/ghostty/config"
  if [ -f "$conf" ]; then
    cp "$conf" "${conf}.bak"
    if grep -q '^font-family' "$conf"; then
      sed -i.tmp "s/^font-family.*/font-family = $FONT_DISPLAY_MONO/" "$conf"
    else
      echo "font-family = $FONT_DISPLAY_MONO" >> "$conf"
    fi
    rm -f "${conf}.tmp"
    echo "Configured Ghostty."
  fi
}

# Run all applicable terminal configs
case "$PLATFORM" in
  gitbash)
    configure_mintty
    configure_windows_terminal
    configure_vscode
    ;;
  wsl)
    configure_windows_terminal
    configure_vscode
    ;;
  linux)
    configure_alacritty
    configure_kitty
    configure_ghostty
    configure_vscode
    ;;
  macos)
    configure_alacritty
    configure_kitty
    configure_ghostty
    configure_vscode
    ;;
esac

# --- Clear font-check cache ---
rm -f "$CACHE_DIR/font-check-ok" "$CACHE_DIR/font-check-warned" "$CACHE_DIR/font-install-pending"

echo ""
echo "${FONT_DISPLAY} installed and terminal configured."
