# Pain Points

Issues encountered during development and testing, and how they were addressed.

## 1. Nerd Font glyphs render as rectangles

**Problem:** Icons display as small outlined rectangles when the terminal font doesn't include Nerd Font glyphs.

**Root cause:** The user's terminal font (e.g. default Git Bash Consolas) doesn't have the Nerd Font codepoints.

**Attempted solutions:**
- Warning via `systemMessage` — user may not notice it, and the warning itself used a unicode emoji (`⚠`) that also doesn't render without the font.
- Changed to ASCII-only warning (`[!]`) — renders correctly but still easy to miss in Claude Code output.
- Auto-install without permission — downloads ~26MB without user consent, not acceptable.
- `"ask"` permission prompt + `updatedInput` to prepend install to original command — font installs but terminal needs restart for the font to load, so original command still shows rectangles.
- **Current approach:** `"ask"` prompt that replaces the original command entirely with the font install script. User approves, font installs and terminal is auto-configured, user is told to restart. On next session, icons work.

**Remaining issue:** The first command the user runs gets replaced by the font install. This is the right tradeoff — running it with broken icons is pointless and the terminal restart is mandatory.

## 2. Hook output conflicts with JSON protocol

**Problem:** Font-check.sh was emitting its own `systemMessage` JSON line, then annotate-pre.sh was emitting a second one. Claude Code only parses one JSON object from stdout.

**Fix:** Font check sets a variable (`FONT_ASK` or `FONT_WARNING`) instead of emitting JSON directly. The main hook script is the single point of JSON output.

## 3. Backslash escaping in JSON output

**Problem:** Bash string replacement `${var//\\/\\\\}` produced trailing backslashes on Git Bash/MINGW, creating malformed commands like `rm -rf \` in the `updatedInput`.

**Fix:** Use `printf '...%s...\n' "$var"` instead of bash string interpolation for JSON construction. The `%s` format specifier passes the value through without bash re-interpreting escape sequences.

## 4. Environment variables empty in hook context

**Problem:** `$LOCALAPPDATA`, `$USERNAME` were empty in early testing, causing font detection paths to resolve incorrectly on Git Bash. Font check silently passed (no fonts found, no warning emitted).

**Status:** Resolved itself — env vars are populated when hooks run via Claude Code's actual hook system. The initial empty vars were from testing the script in an isolated `bash` invocation without the parent shell's exported env.

## 5. Hook caching prevents re-testing

**Problem:** Font check caches results in `~/.cache/bash-annotator/font-check-ok`. During development, this meant changes to font-check logic were invisible until the cache was manually cleared.

**Workaround:** `rm -rf ~/.cache/bash-annotator` before each test iteration. Could add a `--force` flag or dev mode in the future.

## 6. Live hook catches its own test commands

**Problem:** With the hook registered in `settings.local.json`, every Bash tool call — including our own test/debug commands — triggers the hook. When the hook had the install bug, it created a loop where we couldn't run any bash command without triggering the broken install flow.

**Fix:** Disable the hook in `settings.local.json` (set to `{}`), fix the script, re-enable, restart Claude Code. For future development: test scripts in isolation via pipe (`echo '...' | bash script.sh`) with the hook disabled.

## 7. `"ask"` blocks the original command

**Problem:** Returning `permissionDecision: "ask"` pauses the tool call for user approval. Initially we tried to use this as a "confirm before install" gate, but the original command was lost — the user approved, the font installed as a side effect during the hook, and the command they wanted never ran.

**Fix:** Use `updatedInput` to replace the command entirely with the install script. The ask dialog clearly states what will happen. The original command is intentionally sacrificed because it would render with broken icons anyway.
