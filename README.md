# telegram-claude-agent

A Telegram bot that gives you a personal Claude Code agent on your phone. Send a message, get a response — including full tool use (web search, bash, file edits, etc.) with live status updates as it works.

## What it does

- **Full Claude Code access** via Telegram — the same model + tools you use in the terminal
- **Live status feed** — see what tool Claude is calling while it works (`🔧 bash`, `🔍 searching`, `✏️ editing file.py`)
- **Voice messages** — sends voice notes, they get transcribed and sent to Claude (requires `mlx-whisper`)
- **Interrupt / cancel** — send a new message mid-task to interrupt, or send `stop`/`cancel` to abort
- **Long tasks** — jobs running over 10 minutes are backgrounded; the bot follows up when done
- **Memory distillation** — every 20 exchanges, key facts are extracted and saved to a persistent memory file
- **Runs as a LaunchAgent** — starts on login, restarts on crash, no terminal needed

## Prerequisites

| Tool | Install |
|------|---------|
| `curl` | Pre-installed on macOS |
| `node` | `brew install node` or [nvm](https://github.com/nvm-sh/nvm) |
| `python3` | `brew install python3` |
| `claude` CLI | `npm install -g @anthropic-ai/claude-code` |

You also need a [Telegram bot token](#getting-a-telegram-bot-token) and to know your [chat ID](#getting-your-chat-id).

## Quick start

```bash
git clone https://github.com/YOUR_USERNAME/telegram-claude-agent.git
cd telegram-claude-agent
bash install.sh
```

The installer will prompt you for:
1. **Agent name** — a short lowercase name (e.g. `hans`, `jarvis`, `mybot`)
2. **Bot token** — from [@BotFather](https://t.me/BotFather)
3. **Chat ID** — your personal Telegram user ID
4. **Binary paths** — auto-detected, confirm or override

After install, send your bot a message on Telegram to confirm it's working.

## Getting a Telegram bot token

1. Open Telegram and search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts
3. Copy the token (looks like `123456:ABC-DEF1234...`)

## Getting your chat ID

1. Send your bot any message (e.g. `/start`)
2. Visit `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Find `"chat": { "id": 123456789 }` in the response — that number is your chat ID

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

## Voice transcription (optional)

Voice messages are supported on Apple Silicon Macs via `mlx-whisper`:

```bash
pip install mlx-whisper
```

The bot returns a graceful error message if `mlx-whisper` is not installed — text messages always work.

## Running multiple agents

Run `install.sh` again with a different agent name. Each agent gets its own directory, token entry in `.env`, and LaunchAgent plist. They run independently.

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
