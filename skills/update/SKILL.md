---
name: update
description: Update an existing colorful-claude-code install to the latest version. Use when the user asks to update, upgrade, or pull the latest colorful-claude-code / colorful bash plugin. Works from any session — the user does not need to be in the repo directory.
---

# Update colorful-claude-code

The user does not have to be in the repo directory, and you do not need it open as the current project. The installed hook records the absolute path to the repo, so locate it from there, pull, and re-verify.

## Step 1 — Locate the install

Look for the hook command across settings files, most specific last:

1. `~/.claude/settings.json` (global)
2. `./.claude/settings.json` and `./.claude/settings.local.json` (project)

In each, find the `PreToolUse` → `Bash` hook whose `command` references `annotate-pre.sh`. The command looks like `bash /abs/path/to/colorful-claude-code/scripts/annotate-pre.sh` — the repo directory is everything before `/scripts/annotate-pre.sh`.

```bash
grep -rho 'bash [^"]*annotate-pre\.sh' ~/.claude/settings.json ./.claude/settings.json ./.claude/settings.local.json 2>/dev/null
```

- **Found** → the repo dir is the path with `/scripts/annotate-pre.sh` stripped. Continue.
- **Not found anywhere** → this is a marketplace install (updates via `/plugin`, tell the user) or the plugin isn't installed at all. If not installed, offer to run the **install** skill instead. Stop.

If the current session *is* inside the repo (a `scripts/annotate-pre.sh` exists relative to cwd), you can use that path directly.

## Step 2 — Pull the latest

```bash
git -C <repo> pull --ff-only
```

- If the working tree is dirty (local edits to the script/mappings), `git -C <repo> status --short` first and tell the user what's uncommitted rather than clobbering it — let them decide whether to stash.
- If `--ff-only` fails because the branch diverged, report it; don't force anything.
- Note the version change from `<repo>/.claude-plugin/plugin.json` (before vs after) so the user sees what moved.

## Step 3 — Re-verify the hook

The pull may have rewritten `annotate-pre.sh`. Re-run the install smoke test to confirm it still fires:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git status"},"session_id":"t"}' \
  | bash <repo>/scripts/annotate-pre.sh
```

Expect a one-line JSON object with a `systemMessage` field containing an emoji and ANSI color codes.

## Step 4 — Confirm

Tell the user the old → new version, that the hook re-verified, and that **nothing was re-registered** — the hook path is unchanged by a pull, so the existing settings entry keeps working. The update takes effect on the next Bash command Claude Code runs.
