---
name: install
description: Install colorful-claude-code or diagnose missing annotations. Use when the user asks to install or set up this plugin, register its hook, or reports that the colorful emoji annotations never appear.
---

# Install colorful-claude-code

Run Step 0 BEFORE asking the user anything (including the local/global scope question) and BEFORE editing any settings file. In managed or sandboxed environments the hook approach is dead on arrival — a hook install would appear to succeed and then silently never fire, and the user would have answered setup questions for nothing.

## Step 0 — Environment preflight (always run first)

### 0a. Managed policy check

Look for a managed settings file at the OS-specific path:

| OS | Path |
|----|------|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux / WSL | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\Program Files\ClaudeCode\managed-settings.json` |

On Windows, also check the legacy path `C:\ProgramData\ClaudeCode\managed-settings.json` — Claude Code versions before 2.1.75 read managed settings from there. On every OS, also check for a `managed-settings.d/` directory next to the managed settings file: policy fragments in it merge into the managed settings and can set the same keys.

If a managed settings file (or fragment) exists, read it:

- `"allowManagedHooksOnly": true` → custom hooks will not run — including this plugin's auto-registered marketplace hook, unless an admin has force-enabled this specific plugin in managed `enabledPlugins` (rare; if unsure, assume blocked). **Go to Watcher mode.**
- `"disableAllHooks": true` → same. **Go to Watcher mode.**

Never attempt to edit the managed settings file — it is IT-controlled and requires admin rights. Don't suggest the user ask IT to change it unless they bring it up; just route them to watcher mode, which needs no policy exception.

### 0b. User/project hook-disable check

Check `~/.claude/settings.json`, `./.claude/settings.json`, and `./.claude/settings.local.json` for `"disableAllHooks": true`. If found, tell the user which file sets it and ask whether they want it removed — it may be intentional. If they keep it → **Watcher mode.**

### 0c. Sandbox check

Watcher mode requires the user to open a second terminal on the same machine that hosts `~/.claude/projects/`. In a web or cloud sandbox (a claude.ai/code remote session, CI, a container the user can't shell into) that's impossible — and hooks are typically restricted there too.

Signals to check: sandbox/remote-flavored environment variables (`env | grep -iE 'sandbox|remote'`), a home directory that clearly isn't the user's machine, or the user mentioning they're on claude.ai. If sandboxed: say plainly that neither the hook nor the watcher can work in this session, and that the plugin works in Claude Code CLI or desktop on their own machine. Stop — don't install anything.

### 0d. All clear

No managed policy, hooks enabled, local machine → proceed to **Hook install**.

## Hook install (normal environments)

First determine how the plugin got here:

- **Marketplace install** (`/plugin install colorful-claude-code`): the hook is already auto-registered via `hooks/hooks.json`. Don't edit any settings file — skip straight to the smoke test (step 5).
- **Source checkout** (this repo cloned locally): follow all steps.

1. **Verify Claude Code version is ≥ 1.0.33.** Run `claude --version`. Older versions don't support the hook format below.

2. **Ask the user: local scope or global scope?**
   - Local = active only inside this project → edit `<repo>/.claude/settings.local.json`
   - Global = active in every project → edit `~/.claude/settings.json`

3. **Read the target settings file first.** If missing, plan to create it. If present, preserve every existing key. If `hooks.PreToolUse` already exists, append a new matcher entry — do not replace the array.

   Merge in this hook entry, using the absolute path to `scripts/annotate-pre.sh` in this repo:

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

4. **Validate JSON.** `python3 -c "import json; json.load(open('<path>'))"` must exit 0. A malformed settings file silently disables all settings from that file.

5. **Smoke-test the hook directly** before declaring success:

   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"git status"},"session_id":"t"}' \
     | bash <absolute-path>/scripts/annotate-pre.sh
   ```

   Note the field is `tool_input` — that is what Claude Code actually sends to PreToolUse hooks.

   Expect a one-line JSON object with a `systemMessage` field containing an emoji and ANSI color codes.

6. **Confirm to the user** which file changed (or, for marketplace installs, that nothing needed changing) and that the hook fires on the next Bash call Claude Code runs.

## Watcher mode (hooks blocked by policy)

The watcher provides the same colorful annotations without touching the hook system: it tails Claude Code's JSONL conversation log from a second terminal and prints the annotated commands there. Managed policy can block hooks, but it can't block reading `~/.claude/projects/`.

1. **Explain the situation** to the user in one or two sentences: their organization's managed settings block custom hooks, so the plugin can't annotate commands inline — but watcher mode shows the same annotations in a separate terminal.

2. **Verify Python 3 is available** (`python3 --version` or `python --version` — the watcher uses whichever exists). It is needed to parse JSONL log entries. If missing, tell the user to install it before continuing.

3. **Give them the command** to run in a second terminal, with the absolute path to this repo:

   ```bash
   bash /absolute/path/to/colorful-claude-code/scripts/watcher.sh
   ```

   Without arguments it auto-detects the most recent JSONL for the current project. It also accepts an explicit session ID: `watcher.sh <session-id>`.

4. **Offer to add a `ccc` alias** to their shell config (`~/.bashrc`, `~/.zshrc`, etc.):

   ```bash
   alias ccc='bash /absolute/path/to/colorful-claude-code/scripts/watcher.sh'
   ```

   After adding, they `source` the file or open a new terminal, then just run `ccc` alongside any Claude Code session.

   Mention that the alias is the only thing watcher mode adds to their system — `uninstall.sh` only removes hook registrations, so undoing watcher mode means deleting this alias line from the shell config by hand.

5. **Do not edit any hook settings** in this path — there's nothing to register, and a dead hook entry would only confuse a future uninstall.
