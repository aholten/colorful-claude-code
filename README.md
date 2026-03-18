# Claude Code Emoji Explainer

Enhanced understanding at a glance.

When Claude Code runs terminal commands on your behalf, it can be hard to follow what's happening — especially if you're not familiar with the command line. Commands flash by, and unless you already know what `grep`, `sed`, or `chmod` means, you're left wondering what just happened on your computer.

Claude Code Emoji Explainer fixes this. It adds emoji and color-coded backgrounds to every command Claude Code runs, turning cryptic terminal text into something you can actually read at a glance.

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

This is a [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) — a script that runs automatically before Claude Code executes a Bash command. It does not change what the command does. It only adds a visual annotation so you can see what's happening.

The plugin:

1. Receives the command Claude Code is about to run
2. Parses it into individual commands, operators, and nested expressions
3. Looks up each command in a mapping file (`command-map.json`)
4. Displays the annotated version with emoji and colors

It handles compound commands (`cd /app && npm install`), pipes (`cat file | grep error`), command substitutions (`echo $(date)`), and subshells (`(git add . && git commit)`).

## Requirements

- Claude Code
- Bash (included with macOS, Linux, Git Bash on Windows, and WSL)
- A terminal that supports emoji and 256-color ANSI codes (most modern terminals do)

No other dependencies. No Node.js, no Python, nothing to download.

## Install

1. Clone this repository to wherever you keep your projects:

```bash
git clone https://github.com/your-username/claude-code-emoji-explainer.git
cd claude-code-emoji-explainer
```

2. Run the setup script:

```bash
./setup.sh
```

3. The script will ask you to choose between two options:

   - **Local install** — The hook only runs when Claude Code is working inside this project folder. This modifies the file `.claude/settings.local.json` inside this project directory.

   - **Global install** — The hook runs in every project you open with Claude Code. This modifies the file `~/.claude/settings.json`, which is **outside this project directory** in your home folder. The script will ask you to confirm before making this change.

4. That's it. The next time Claude Code runs a Bash command, you'll see the annotations.

### What the setup script changes

The setup script adds a hook entry to one Claude Code settings file (your choice of local or global). Here is exactly what gets added:

```json
{
  "hooks": {
    "PreToolUse": [
      {"type": "command", "command": "bash /path/to/scripts/annotate-pre.sh"}
    ]
  }
}
```

The path will be the actual location of the script on your computer. No other files outside this project are modified.

## Update

To update to the latest version:

```bash
cd claude-code-emoji-explainer
git pull
```

That's it. The setup script registered the hook using an absolute path to the scripts in this directory, so pulling new changes takes effect immediately. No need to run setup again.

## Uninstall

To stop the hook from running:

```bash
./uninstall.sh
```

This removes the hook entry from your Claude Code settings file (local or global, depending on where it was installed). The script will show you which files it found the hook in and ask for confirmation before making changes.

The plugin files stay on disk after uninstalling. If you want to remove everything completely, delete the project folder:

```bash
rm -rf claude-code-emoji-explainer
```

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
claude-code-emoji-explainer/
├── scripts/
│   ├── annotate-pre.sh   # Main hook — entry point called by Claude Code
│   ├── parser.sh         # Splits commands into tokens
│   └── renderer.sh       # Applies emoji and colors to tokens
├── command-map.json      # Emoji and color mapping for ~40 commands
├── setup.sh              # Install the hook
├── uninstall.sh          # Remove the hook
├── test.sh               # Test suite
├── LICENSE               # MIT
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

## Author

Anthony Holten @aholten on GitHub

