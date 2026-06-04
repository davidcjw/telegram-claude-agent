# Setup Prompt

Copy everything inside the code block below and paste it into a new **Claude Code** session (`claude` in your terminal). Claude will walk you through the rest interactively.

````
I want to install a Telegram bot that lets me chat with Claude Code from my phone.
Source repo: https://github.com/davidcjw/telegram-claude-agent

Please set it up by following these steps in order:

## Step 1 — Check dependencies
Run `which curl node python3` and check for the claude CLI at `~/.local/bin/claude`,
`/usr/local/bin/claude`, and `$(which claude)`.
Tell me what you found. If anything is missing, tell me how to install it before continuing.

## Step 2 — Gather info (ask me one at a time, wait for my answer each time)
1. Agent name — short lowercase word, e.g. `jarvis` (this becomes the bot's identity)
2. Telegram bot token — create one at @BotFather if you don't have one (send /newbot)
3. Telegram chat ID — if you're unsure, tell me and explain how to find it

## Step 3 — Create directory structure
mkdir -p ~/.claude/telegram/<agentname>
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/memory
mkdir -p ~/.claude/logs

## Step 4 — Download scripts
curl -fsSL https://raw.githubusercontent.com/davidcjw/telegram-claude-agent/master/loop.sh \
  -o ~/.claude/telegram/<agentname>/loop.sh

curl -fsSL https://raw.githubusercontent.com/davidcjw/telegram-claude-agent/master/status_watcher.py \
  -o ~/.claude/telegram/<agentname>/status_watcher.py

chmod +x ~/.claude/telegram/<agentname>/loop.sh \
         ~/.claude/telegram/<agentname>/status_watcher.py

Then edit the top of loop.sh to replace the four default values with the actual paths found in Step 1:
- AGENT → the agent name from Step 2
- CLAUDE_BIN → actual path to the claude binary
- NODE_BIN → actual path to node
- PYTHON_BIN → actual path to python3

## Step 5 — Write config files
- Add <AGENTNAME_UPPERCASE>_BOT_TOKEN=<token> to ~/.claude/telegram/.env
  (create the file if it doesn't exist, then chmod 600 it)
- Write the chat ID (just the number, no newline) to ~/.claude/telegram/<agentname>/chat_id.txt
- Write 0 to ~/.claude/telegram/<agentname>/offset.txt

## Step 6 — Create persona file
If ~/.claude/agents/<agentname>.md does not exist, ask me how I want the agent to
behave (tone, focus, any special instructions), then create the file.

## Step 7 — Install LaunchAgent (macOS only)
Create ~/Library/LaunchAgents/com.claude.telegram.<agentname>.plist with this content
(substituting real values for <agentname>, <loop_path>, and <you>):

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.claude.telegram.<agentname></string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string><loop_path></string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/<you>/.claude/logs/telegram-<agentname>.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/<you>/.claude/logs/telegram-<agentname>.log</string>
</dict>
</plist>

Then load it:
launchctl load -w ~/Library/LaunchAgents/com.claude.telegram.<agentname>.plist

## Step 8 — Verify
- Run `launchctl list | grep com.claude.telegram` — confirm a PID appears in the first column
- Show me the last 5 lines of ~/.claude/logs/telegram-<agentname>.log
- Tell me to send the bot a message on Telegram to confirm it replies

## Step 9 — Voice transcription (optional, Apple Silicon Mac only)
Ask me: "Do you want to send voice messages to the bot?"

If yes:
1. Ask me which model to use:
   - (1) Fast — whisper-small (~500MB), good for everyday English
   - (2) Accurate (recommended) — whisper-large-v3-turbo (~800MB), better for accents and mixed languages

2. Install mlx-whisper if not already installed:
   pip install mlx-whisper

3. Write the chosen model name to ~/.claude/telegram/<agentname>/whisper_model.txt:
   - Option 1: mlx-community/whisper-small
   - Option 2: mlx-community/whisper-large-v3-turbo

4. Pre-download the model now (first use would otherwise trigger a silent multi-minute download):
   python3 -c "from huggingface_hub import snapshot_download; snapshot_download('<model-name>')"
   Wait for this to complete before continuing.

5. Confirm with me that the download finished. Voice messages are now ready.

If no, skip this step. Voice messages will return a graceful error until set up.
````
