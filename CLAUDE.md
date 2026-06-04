# Claude Code Instructions

## Project overview

This repo ships a Telegram bot that wraps Claude Code (`claude --print`) so the user can interact with their Claude Code agent from their phone. The bot runs as a macOS LaunchAgent.

Two runtime files: `loop.sh` (main loop) and `status_watcher.py` (live tool-feed watcher). `INSTALL_PROMPT.md` is the setup prompt users paste into Claude Code to install the bot.

## When making changes

- Read `AGENTS.md` for the full architecture and constraint list before editing
- After any change to `loop.sh`, check if `INSTALL_PROMPT.md` needs updating
- After any change to `README.md`, verify all section links in the Table of Contents still resolve
- Do not commit `.env`, `chat_id.txt`, `history.txt`, `offset.txt`, or `*.pid` files — they are in `.gitignore`

## Testing

There is no automated test suite. Manual verification:
1. Run `bash ~/.claude/telegram/<agentname>/loop.sh` in a terminal
2. Send a message to the bot on Telegram
3. Confirm a reply arrives and the log looks clean (`tail -f ~/.claude/logs/telegram-<agentname>.log`)

## No API key

The bot intentionally uses `claude --print` (Claude Code CLI) rather than the Anthropic API. Do not introduce `ANTHROPIC_API_KEY` requirements.
