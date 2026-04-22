# colorful-claude-code

Claude Code plugin that adds emoji + color annotations to Bash commands via a PreToolUse hook. No runtime deps.

## When the user asks to install

Handle install directly — there is no `setup.sh`.

1. **Verify Claude Code version is ≥ 1.0.33.** Run `claude --version`. Older versions don't support the hook format below.

2. **Ask the user: local scope or global scope?**
   - Local = active only inside this project → edit `<repo>/.claude/settings.local.json`
   - Global = active in every project → edit `~/.claude/settings.json`

3. **Read the target settings file first.** If missing, plan to create it. If present, preserve every existing key. If `hooks.PreToolUse` already exists, append a new matcher entry — do not replace the array.

4. **Merge in this hook entry**, using the absolute path to `scripts/annotate-pre.sh` in this repo:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "bash <absolute-path>/scripts/annotate-pre.sh" }
           ]
         }
       ]
     }
   }
   ```

5. **Validate JSON.** `python3 -c "import json; json.load(open('<path>'))"` must exit 0. A malformed settings file silently disables all settings from that file.

6. **Smoke-test the hook directly** before declaring success:

   ```bash
   echo '{"tool_name":"Bash","input":{"command":"git status"},"session_id":"t"}' \
     | bash <absolute-path>/scripts/annotate-pre.sh
   ```

   Expect a one-line JSON object with a `systemMessage` field containing an emoji and ANSI color codes.

7. **Confirm to the user** which file changed and that the hook fires on the next Bash call Claude Code runs.

## When the user asks to uninstall

Edit the same settings file. Remove only the matcher entry whose command references `scripts/annotate-pre.sh` in this repo — leave any unrelated hooks alone. If that was the only PreToolUse entry, remove the now-empty `PreToolUse` array (and the `hooks` object if it's empty too). `uninstall.sh` is still available as a non-interactive alternative.

## Customizing command → emoji mappings

All mappings live in `command-map.json`. Changes take effect immediately — no reinstall. If the user asks to add a command, edit that file; don't touch the hook script.

## Watcher mode (for restricted environments)

If the user's organization sets `allowManagedHooksOnly=true` (blocking custom user hooks), the watcher script provides the same colorful annotations by tailing Claude Code's JSONL conversation log from a separate terminal.

### Usage

```bash
bash scripts/watcher.sh [session-id]
```

Without a session ID, it auto-detects the most recent JSONL for the current working directory's project.

### Adding a `ccc` alias

To make the watcher easy to launch, suggest adding an alias to the user's shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
alias ccc='bash /absolute/path/to/colorful-Claude-code/scripts/watcher.sh'
```

Replace `/absolute/path/to` with the actual path to the cloned repo. After adding, run `source ~/.bashrc` (or `~/.zshrc`) or open a new terminal. Then just run `ccc` in a separate terminal while using Claude Code.

## Tuning output width

The hook chunks long segments into multiple styled lines so Claude Code's TUI never wraps within a styled span (the bg only applies to the first visual line of a span, so wrap = lost highlight). Default chunk budget is 60 chars, set via `COLORFUL_CHUNK_WIDTH` env var.

If a user complains that annotations look sparse on a wide terminal, or wrap/lose color on a narrow one, adjust this env var in their shell config:

```bash
export COLORFUL_CHUNK_WIDTH=80  # tune for their terminal width
```

Rough sizing: `terminal_width - 30` (UI prefix + emoji + padding overhead). Don't try to auto-detect — Claude Code does not pass `COLUMNS` or a controlling TTY through to PreToolUse hooks.

