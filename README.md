# Telegram Claude Agent - Your AI Assistant in your pocket

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AgentReady Score](https://agentready.davidcjw.com/api/badge/davidcjw/telegram-claude-agent)](https://agentready.davidcjw.com/results/davidcjw/telegram-claude-agent)

A Telegram bot that gives you a personal Claude Code agent on your phone. Send a message, get a response — including full tool use (web search, bash, file edits, etc.) with live status updates as it works.

<p align="center">
  <img src="docs/demo.gif" alt="Telegram Claude Agent demo" width="640">
</p>

## No API key required — works with your Claude subscription

This bot runs on top of `claude --print` (the Claude Code CLI in headless mode), which means it uses your existing **Claude Pro or Max subscription** — not the Anthropic API. No separate billing, no usage caps beyond what your plan already includes.

> **Update (June 15):** Anthropic is **pausing** the previously announced changes to Claude Agent SDK billing. For now, nothing has changed — Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription's usage limits. The previously announced monthly credit (which would have been available to eligible claimants in connection with these changes) isn't available. Anthropic is reworking the plan to better support how users build with Claude subscriptions and will share an update before anything takes effect. See [Anthropic's announcement](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) for details.

## What it does

- **Full Claude Code access** via Telegram — the same model + tools you use in the terminal
- **Live status feed** — see what tool Claude is calling while it works (`🔧 bash`, `🔍 searching`, `✏️ editing file.py`)
- **Voice messages** — sends voice notes, they get transcribed and sent to Claude (requires `mlx-whisper`)
- **Interrupt / cancel** — send a new message mid-task to interrupt, or send `stop`/`cancel` to abort
- **Long tasks** — jobs running over 10 minutes are backgrounded; the bot follows up when done
- **Memory distillation** — every 20 exchanges, key facts are extracted and saved to a persistent memory file
- **Runs as a LaunchAgent** — starts on login, restarts on crash, no terminal needed

## Table of Contents

- [No API key required](#no-api-key-required--works-with-your-claude-subscription)
- [What it does](#what-it-does)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Getting a Telegram bot token](#getting-a-telegram-bot-token)
- [Getting your chat ID](#getting-your-chat-id)
- [Customising your agent](#customising-your-agent)
- [Installed file layout](#installed-file-layout)
- [Useful commands](#useful-commands)
- [Voice transcription](#voice-transcription-optional-apple-silicon-only)
- [Running multiple agents](#running-multiple-agents)
- [Non-macOS (Linux)](#non-macos-linux)
- [How it works](#how-it-works)
- [Security note](#security-note)
- [Contributing](#contributing)
- [Code of Conduct](#code-of-conduct)
- [License](#license)

## Prerequisites

| Tool | Install |
|------|---------|
| `curl` | Pre-installed on macOS |
| `node` | `brew install node` or [nvm](https://github.com/nvm-sh/nvm) |
| `python3` | `brew install python3` |
| `claude` CLI | `npm install -g @anthropic-ai/claude-code` |

You also need a [Telegram bot token](#getting-a-telegram-bot-token) and to know your [chat ID](#getting-your-chat-id).

## Quick start

Setup runs entirely inside Claude Code — no cloning required.

1. Open [INSTALL_PROMPT.md](INSTALL_PROMPT.md) and copy the prompt inside the code block
2. Open a new Claude Code session (`claude` in your terminal)
3. Paste and send — Claude will ask for your agent name, bot token, and chat ID, then set everything up

That's it. Claude handles path detection, file creation, and LaunchAgent registration interactively.

## Getting a Telegram bot token

1. Open [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow the prompts
3. Copy the token (looks like `123456:ABC-DEF1234...`)

## Getting your chat ID

1. Open [@UserInfoBot](https://t.me/userinfobot) on Telegram
2. Press the start button and you should receive a message containing your chat ID

## Customising your agent

Edit `~/.claude/agents/<agentname>.md` to change the persona, tone, and instructions. The file is plain text — just describe who the agent is and how it should behave.

## Installed file layout

```
~/.claude/
├── telegram/
│   ├── .env                        # bot token(s)
│   └── <agentname>/
│       ├── loop.sh                 # main bot loop
│       ├── status_watcher.py       # live tool-feed watcher
│       ├── chat_id.txt
│       ├── offset.txt
│       └── history.txt
├── agents/
│   └── <agentname>.md              # persona
├── memory/
│   └── <agentname>.md              # persistent memory (auto-created)
└── logs/
    └── telegram-<agentname>.log
```

## Useful commands

```bash
# Watch the log
tail -f ~/.claude/logs/telegram-<agentname>.log

# Restart the bot
launchctl unload ~/Library/LaunchAgents/com.claude.telegram.<agentname>.plist
launchctl load -w ~/Library/LaunchAgents/com.claude.telegram.<agentname>.plist

# Stop the bot
launchctl unload ~/Library/LaunchAgents/com.claude.telegram.<agentname>.plist
```

## Voice transcription (optional, Apple Silicon only)

Voice messages are transcribed locally via `mlx-whisper`. Step 9 of the install prompt walks you through it — you choose between two models:

| Model | Size | Best for |
|-------|------|----------|
| `whisper-small` | ~500MB | Everyday English, fast |
| `whisper-large-v3-turbo` *(recommended)* | ~800MB | Accents, mixed languages |

The model is pre-downloaded during setup so the first voice message is instant. Text messages always work regardless.

## Running multiple agents

Run the `INSTALL_PROMPT.md` in a new `claude` session with a different agent name. Each agent gets its own directory, token entry in `.env`, and LaunchAgent plist. They run independently.

## Non-macOS (Linux)

The installer skips the LaunchAgent step on non-macOS. Start the bot manually:

```bash
bash ~/.claude/telegram/<agentname>/loop.sh
```

Or create a systemd service pointing to that script.

## How it works

- `loop.sh` — polls Telegram for messages, builds a prompt (persona + memory + history + message), calls `claude --print` in streaming mode, and sends the response back
- `status_watcher.py` — tails the stream-json output and sends live Telegram messages when it sees tool calls
- Memory is stored in a plain markdown file and appended by Claude itself when instructed
- The LaunchAgent keeps `loop.sh` running and restarts it if it crashes

## Security note

The bot only responds to the single `CHAT_ID` you configure — all other senders are silently ignored. Keep your `.env` file private (it's in `.gitignore`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. The short version: open an issue before starting significant work, keep `INSTALL_PROMPT.md` in sync with any `loop.sh` changes, and test manually before submitting a PR.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating you agree to uphold a welcoming, harassment-free environment.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
