# colorful-claude-code

Claude Code plugin that adds emoji + color annotations to Bash commands via a PreToolUse hook. No runtime deps.

## When the user asks to install

Follow `skills/install/SKILL.md`. It begins with a required environment preflight (Step 0) that detects managed policy (`allowManagedHooksOnly`, `disableAllHooks`) and sandboxed sessions, and routes to watcher mode when hooks can't run. Do not skip Step 0 and do not ask the user any setup questions before it completes.

## When the user asks to update

Follow `skills/update/SKILL.md`. The key idea: you don't need the session to be inside the repo. Find the install location from the hook command path in the user's Claude settings (`~/.claude/settings.json`, then project settings) — the `command` field reads `bash <repo>/scripts/annotate-pre.sh`, so the `<repo>` dir is right there. `git -C <repo> pull --ff-only`, then re-run the install smoke test (Step 5 of `skills/install/SKILL.md`) to confirm the hook still fires. The hook path is unchanged by a pull, so never re-register the hook. If no `annotate-pre.sh` hook is found in any settings file, the plugin isn't installed — offer to install instead.

## When the user asks to uninstall

Edit the same settings file. Remove only the matcher entry whose command references `scripts/annotate-pre.sh` in this repo — leave any unrelated hooks alone. If that was the only PreToolUse entry, remove the now-empty `PreToolUse` array (and the `hooks` object if it's empty too). `uninstall.sh` is still available as a non-interactive alternative.

## Customizing command → emoji mappings

All mappings are the `_lookup` and `_lookup_op` case tables in `scripts/annotate-pre.sh` (format: `emoji bg fg`, where `_` means no emoji). If the user asks to add or change a command mapping, edit those tables. Background colors must stay within the Okabe-Ito CVD-safe palette documented in the comment above `_lookup` — pick the category color that matches what the command *does*.

Each palette bg also has dimmed variants in `_depth_style`, used to fade nested delimiter content (quotes, substitutions, subshells) one step per nesting level. If a new category color is ever added, add its depth-1/depth-2 steps there too or nested content in that color won't dim.

## Watcher mode (for restricted environments)

If the user's organization sets `allowManagedHooksOnly=true` (blocking custom user hooks), the watcher script provides the same colorful annotations by tailing Claude Code's JSONL conversation log from a separate terminal. Setup steps are in the **Watcher mode** section of `skills/install/SKILL.md` — the install preflight routes there automatically when hooks are blocked.

## Tuning output width

The hook chunks long segments into multiple styled lines so Claude Code's TUI never wraps within a styled span (the bg only applies to the first visual line of a span, so wrap = lost highlight). Default chunk budget is 60 chars, set via `COLORFUL_CHUNK_WIDTH` env var.

If a user complains that annotations look sparse on a wide terminal, or wrap/lose color on a narrow one, adjust this env var in their shell config:

```bash
export COLORFUL_CHUNK_WIDTH=80  # tune for their terminal width
```

Rough sizing: `terminal_width - 30` (UI prefix + emoji + padding overhead). Don't try to auto-detect — Claude Code does not pass `COLUMNS` or a controlling TTY through to PreToolUse hooks.

