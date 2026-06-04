# Agent Guide

This file helps AI coding agents understand the repo structure and constraints.

## What this project is

A Telegram bot that wraps Claude Code (`claude --print`) so the user can send messages from their phone and get full Claude Code responses — including tool use, web search, file edits, and bash commands. The bot runs as a macOS LaunchAgent.

## File map

| File | Purpose |
|------|---------|
| `loop.sh` | Main bot loop — polls Telegram, builds prompts, calls Claude, sends responses |
| `status_watcher.py` | Tails Claude's stream-json output and sends live tool-call updates to Telegram |
| `INSTALL_PROMPT.md` | The copy-paste setup prompt users run inside Claude Code to install the bot |
| `README.md` | User-facing docs |

## How the system works

1. `loop.sh` long-polls the Telegram Bot API (`getUpdates`)
2. On a new message, it builds a prompt: persona + long-term memory + recent history + user message
3. It calls `claude --print --output-format stream-json` and pipes output to a temp file
4. `status_watcher.py` reads that file in real time and sends Telegram messages when it spots tool calls
5. When Claude finishes, `loop.sh` extracts the `result` field from the stream JSON and sends it back

## Critical invariant

**`INSTALL_PROMPT.md` must stay in sync with `loop.sh`.**

- Any new config variable at the top of `loop.sh` needs a corresponding step in the install prompt
- Any new runtime file (e.g. `whisper_model.txt`) needs to be created during setup in the install prompt
- Any new dependency needs to appear in both the Prerequisites table in `README.md` and the install prompt

## Config block

The top of `loop.sh` contains a config block that the install prompt patches with `sed`:

```
AGENT=
CLAUDE_BIN=
NODE_BIN=
PYTHON_BIN=
```

Do not add logic or variable references inside this block — it is patched by literal string replacement.

## Runtime file layout (post-install)

```
~/.claude/telegram/.env                      # AGENTNAME_BOT_TOKEN=...
~/.claude/telegram/<agent>/loop.sh           # patched copy of this repo's loop.sh
~/.claude/telegram/<agent>/status_watcher.py
~/.claude/telegram/<agent>/chat_id.txt       # numeric Telegram chat ID
~/.claude/telegram/<agent>/offset.txt        # Telegram update offset
~/.claude/telegram/<agent>/history.txt       # conversation log
~/.claude/telegram/<agent>/whisper_model.txt # optional: mlx-community/whisper-*
~/.claude/telegram/<agent>/pending.txt       # set when a job runs past 10 min
~/.claude/agents/<agent>.md                  # persona file
~/.claude/memory/<agent>.md                  # persistent long-term memory
~/.claude/logs/telegram-<agent>.log          # stdout + stderr
```

## What to avoid

- Do not add API key requirements — the bot is designed to run on a Claude Pro/Max subscription via `claude --print`
- Do not add npm/pip dependencies to the core loop — `loop.sh` uses only bash, curl, and node (for JSON parsing); `status_watcher.py` uses only stdlib
- Do not break the signal handling — `loop.sh` uses `kill -KILL` and PID tracking to interrupt in-flight Claude calls; changes here need careful testing
