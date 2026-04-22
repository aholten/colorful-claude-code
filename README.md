# Colorful Claude Code

Enhanced understanding at a glance.

When Claude Code runs terminal commands on your behalf, it can be hard to follow what's happening — especially if you're not familiar with the command line. Commands flash by, and unless you already know what `grep`, `sed`, or `chmod` means, you're left wondering what just happened on your computer.

Colorful Claude Code fixes this. It adds emoji and color-coded backgrounds to every command Claude Code runs, turning cryptic terminal text into something you can actually read at a glance.

Before:

```
cd /my-project && npm install && npm test
```

After:

```
📁 cd /my-project ✅ && 📦 npm install ✅ && 📦 npm test
```

Each command gets its own color and emoji. Operators like `&&` and `|` get annotated too. Even commands nested inside `$(...)` are highlighted. If you don't recognize a command, the emoji gives you an immediate visual hint about what category it falls into — file operations, network requests, package management, destructive actions, and so on.

## Why this matters

There are a lot of people who want to use Claude Code. There aren't a lot of people who are intimately familiar with all of the bash commands it runs. Even seasoned software engineers and command line experts can learn something from these visual reinforcements.

This plugin is an educational tool. It draws from the same principle as highlighting parts of speech while learning a language — color and symbols create visual contrast that helps your brain categorize and retain what you're seeing.

Over time, you'll start recognizing commands by their colors before you even read the text.

## What you'll see

| Emoji | Category | Examples |
|-------|----------|----------|
| 🔀 | Version control | `git` |
| 📦 | Package managers | `npm`, `npx`, `pnpm` |
| 🧶 | Yarn | `yarn` |
| 🐳 | Containers | `docker` |
| 🐍 | Python | `python`, `pip` |
| 🦀 | Rust | `cargo`, `rustc` |
| 🔵 | Go | `go` |
| ☕ | Java | `java`, `javac` |
| 💎 | Ruby | `ruby`, `gem` |
| 🔨 | Build tools | `make`, `cmake` |
| 🌐 | Network | `curl`, `wget` |
| 🔑 | Remote access | `ssh`, `scp` |
| 📁 | Navigation | `cd` |
| 📋 | Listing | `ls` |
| 🐱 | Reading files | `cat` |
| 🔍 | Searching | `grep`, `find` |
| 💬 | Output | `echo` |
| 🗑️ | Deleting | `rm` |
| ⚡ | Elevated privileges | `sudo` |
| 💀 | Stopping processes | `kill` |
| 🔒 | Permissions | `chmod`, `chown` |
| ✏️ | Text processing | `sed`, `awk` |
| 🗜️ | Archives | `tar`, `zip` |

Operators between commands are also annotated:

| Emoji | Operator | Meaning |
|-------|----------|---------|
| ✅ | `&&` | Run next command only if previous succeeded |
| ⚠️ | `\|\|` | Run next command only if previous failed |
| 🔗 | `\|` | Pipe output to next command |
| ⏩ | `;` | Run next command regardless |

Commands that aren't in the map still get a neutral background color so the full command remains visually consistent.

## How it works

This is a [Claude Code plugin](https://code.claude.com/docs/en/plugins) that uses a [hook](https://code.claude.com/docs/en/hooks) — a script that runs automatically before Claude Code executes a Bash command. It does not change what the command does. It only adds a visual annotation so you can see what's happening.

The plugin:

1. Receives the command Claude Code is about to run
2. Parses it into individual commands, operators, and nested expressions
3. Looks up each command in a mapping file (`command-map.json`)
4. Displays the annotated version with emoji and colors

It handles compound commands (`cd /app && npm install`), pipes (`cat file | grep error`), command substitutions (`echo $(date)`), and subshells (`(git add . && git commit)`).

## Requirements

- Claude Code v1.0.33 or later
- Bash (included with macOS, Linux, Git Bash on Windows, and WSL)
- A terminal that supports emoji and 256-color ANSI codes (most modern terminals do)

No other dependencies. No Node.js, no Python, nothing to download.

## Install

### From the Claude Code plugin marketplace

Once listed on the marketplace, install directly from Claude Code:

```
/plugin install colorful-claude-code
```

### Manual install (from source)

1. Clone this repository:

```bash
git clone https://github.com/aholten/colorful-claude-code.git
cd colorful-claude-code
```

2. Load it as a local plugin for a single session:

```bash
claude --plugin-dir .
```

3. Or, for a persistent install, open Claude Code in this directory and just ask:

> "install this plugin"

`CLAUDE.md` tells Claude how to register the hook — it will ask whether you want local (this project only) or global (all projects), edit the right settings file, validate it, and smoke-test the hook.

## Update

If installed via the plugin marketplace, updates happen automatically.

If installed from source:

```bash
cd colorful-claude-code
git pull
```

## Uninstall

If installed via the plugin marketplace:

```
/plugin uninstall colorful-claude-code
```

If installed from source, either ask Claude ("uninstall this plugin") or run:

```bash
./uninstall.sh
```

## Watcher mode (hooks blocked by corp policy?)

Some organizations set `allowManagedHooksOnly=true`, which prevents custom user hooks from running. The watcher script is a workaround — it tails Claude Code's JSONL conversation log from a separate terminal and prints the same colorful emoji annotations whenever a Bash command is executed.

### Quick start

Open a second terminal in your project directory and run:

```bash
bash /path/to/colorful-claude-code/scripts/watcher.sh
```

It auto-detects the most recent conversation log for the current project. You can also pass a specific session ID:

```bash
bash /path/to/colorful-claude-code/scripts/watcher.sh <session-id>
```

### Set up a `ccc` alias

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
alias ccc='bash /path/to/colorful-claude-code/scripts/watcher.sh'
```

Then just run `ccc` in a separate terminal while using Claude Code.

### Requirements

- Python 3 (for JSON parsing of JSONL log entries)
- Everything else from the base requirements above

## Testing

The project includes a test suite to verify everything works:

```bash
./test.sh
```

You can also run tests for specific components:

```bash
./test.sh parser     # test command parsing
./test.sh mapping    # test emoji/color lookups
./test.sh renderer   # test colored output
./test.sh hook       # test the full hook pipeline
```

## Project structure

```
colorful-claude-code/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── hooks/
│   └── hooks.json           # Hook configuration
├── scripts/
│   ├── annotate-pre.sh      # Main hook — entry point called by Claude Code
│   ├── parser.sh            # Splits commands into tokens
│   ├── renderer.sh          # Applies emoji and colors to tokens
│   └── watcher.sh           # Standalone log watcher for restricted environments
├── command-map.json         # Emoji and color mapping for ~40 commands
├── CLAUDE.md                # Onboarding instructions Claude reads when you ask it to install
├── uninstall.sh             # Non-interactive uninstall
├── test.sh                  # Test suite
├── LICENSE                  # MIT
└── README.md
```

## Adding or changing command mappings

The file `command-map.json` contains every command-to-emoji mapping. Each entry looks like this:

```json
"git": { "emoji": "🔀", "bg": 202, "fg": 17 }
```

- `emoji` — The emoji shown before the command
- `bg` — Background color (256-color ANSI code)
- `fg` — Foreground text color, chosen to contrast with the background

You can edit this file to add new commands, change emoji, or adjust colors. Changes take effect immediately — no need to reinstall.

## Tuning output width

Long segments are broken at word boundaries into chunks of at most 60 characters so each styled span fits on one visual line. If you run a wider terminal and want denser output, set `COLORFUL_CHUNK_WIDTH` in your shell config:

```bash
export COLORFUL_CHUNK_WIDTH=80
```

Rough sizing guide (accounting for UI overhead):

| Terminal width | Suggested `COLORFUL_CHUNK_WIDTH` |
|----------------|----------------------------------|
| 80             | 50                               |
| 100            | 70                               |
| 120            | 90                               |
| 140+           | 110                              |

Too high and long segments wrap visually, losing the bg highlight on the overflow. Too low wastes horizontal space. The hook doesn't auto-detect because Claude Code doesn't pass terminal size or a TTY through to PreToolUse hooks.

## Author

Anthony Holten [@aholten](https://github.com/aholten) on GitHub
