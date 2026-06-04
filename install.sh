#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}✔${NC} $*"; }
warn()    { echo -e "${YELLOW}!${NC} $*"; }
err()     { echo -e "${RED}✘${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ── Dependency checks ──────────────────────────────────────────────────────────

header "Checking dependencies..."

check_bin() {
  local name="$1" bin
  bin=$(which "$name" 2>/dev/null)
  if [[ -n "$bin" ]]; then
    info "$name → $bin"
    echo "$bin"
  else
    echo ""
  fi
}

CURL_BIN=$(check_bin curl)
NODE_BIN=$(check_bin node)
PYTHON_BIN=$(check_bin python3)
CLAUDE_BIN=""

# Check common claude locations
for candidate in \
  "$(which claude 2>/dev/null)" \
  "$HOME/.local/bin/claude" \
  "/usr/local/bin/claude" \
  "/opt/homebrew/bin/claude"
do
  if [[ -x "$candidate" ]]; then
    CLAUDE_BIN="$candidate"
    info "claude → $CLAUDE_BIN"
    break
  fi
done

MISSING=0
[[ -z "$CURL_BIN" ]]   && { err "curl not found — install via Homebrew: brew install curl"; MISSING=1; }
[[ -z "$NODE_BIN" ]]   && { err "node not found — install via https://nodejs.org or nvm"; MISSING=1; }
[[ -z "$PYTHON_BIN" ]] && { err "python3 not found — install via Homebrew: brew install python3"; MISSING=1; }
[[ -z "$CLAUDE_BIN" ]] && { err "claude CLI not found — install via: npm install -g @anthropic-ai/claude-code"; MISSING=1; }
[[ $MISSING -eq 1 ]] && exit 1

# ── Gather config ──────────────────────────────────────────────────────────────

header "Configuration"

read -rp "Agent name (default: myagent): " AGENT
AGENT="${AGENT:-myagent}"
AGENT="${AGENT,,}"  # lowercase (bash 4+; falls back gracefully on bash 3)

read -rp "Telegram bot token (from @BotFather): " BOT_TOKEN
if [[ -z "$BOT_TOKEN" ]]; then
  err "Bot token is required."
  exit 1
fi

echo ""
echo "To get your chat ID:"
echo "  1. Start a chat with your bot on Telegram"
echo "  2. Send it any message (e.g. /start)"
echo "  3. Visit: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
echo "  4. Find the 'id' field inside 'chat' in the response"
echo ""
read -rp "Your Telegram chat ID: " CHAT_ID
if [[ -z "$CHAT_ID" ]]; then
  err "Chat ID is required."
  exit 1
fi

# Confirm detected paths or override
echo ""
read -rp "Claude binary [$CLAUDE_BIN]: " input
CLAUDE_BIN="${input:-$CLAUDE_BIN}"

read -rp "Node binary [$NODE_BIN]: " input
NODE_BIN="${input:-$NODE_BIN}"

read -rp "Python3 binary [$PYTHON_BIN]: " input
PYTHON_BIN="${input:-$PYTHON_BIN}"

TOKEN_VAR="$(echo "${AGENT}" | tr '[:lower:]' '[:upper:]')_BOT_TOKEN"

# ── Create directories ─────────────────────────────────────────────────────────

header "Creating directories..."

BASE="$HOME/.claude/telegram/$AGENT"
mkdir -p "$BASE"
mkdir -p "$HOME/.claude/logs"
mkdir -p "$HOME/.claude/agents"
mkdir -p "$HOME/.claude/memory"
info "Directories ready"

# ── Write .env ─────────────────────────────────────────────────────────────────

ENV_FILE="$HOME/.claude/telegram/.env"
touch "$ENV_FILE"
if grep -q "^${TOKEN_VAR}=" "$ENV_FILE" 2>/dev/null; then
  warn "${TOKEN_VAR} already in .env — updating"
  sed -i '' "s|^${TOKEN_VAR}=.*|${TOKEN_VAR}=${BOT_TOKEN}|" "$ENV_FILE"
else
  echo "${TOKEN_VAR}=${BOT_TOKEN}" >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
info ".env updated ($ENV_FILE)"

# ── Write chat_id and offset ───────────────────────────────────────────────────

echo -n "$CHAT_ID" > "$BASE/chat_id.txt"
[[ ! -f "$BASE/offset.txt" ]] && echo -n "0" > "$BASE/offset.txt"
info "chat_id.txt written"

# ── Install scripts ────────────────────────────────────────────────────────────

header "Installing scripts..."

# Patch and install loop.sh
sed \
  -e "s|AGENT=\"\${AGENT:-myagent}\"|AGENT=\"${AGENT}\"|" \
  -e "s|CLAUDE_BIN=\"\${CLAUDE_BIN:-\${HOME}/.local/bin/claude}\"|CLAUDE_BIN=\"${CLAUDE_BIN}\"|" \
  -e "s|NODE_BIN=\"\${NODE_BIN:-\$(which node 2>/dev/null)}\"|NODE_BIN=\"${NODE_BIN}\"|" \
  -e "s|PYTHON_BIN=\"\${PYTHON_BIN:-\$(which python3 2>/dev/null)}\"|PYTHON_BIN=\"${PYTHON_BIN}\"|" \
  "$REPO_DIR/loop.sh" > "$BASE/loop.sh"
chmod +x "$BASE/loop.sh"
info "loop.sh → $BASE/loop.sh"

cp "$REPO_DIR/status_watcher.py" "$BASE/status_watcher.py"
chmod +x "$BASE/status_watcher.py"
info "status_watcher.py → $BASE/status_watcher.py"

# ── Install persona file ───────────────────────────────────────────────────────

PERSONA_FILE="$HOME/.claude/agents/${AGENT}.md"
if [[ -f "$PERSONA_FILE" ]]; then
  warn "Persona file already exists — skipping ($PERSONA_FILE)"
else
  sed "s/MyAgent/${AGENT^}/g; s/myagent/${AGENT}/g" \
    "$REPO_DIR/agent.md.example" > "$PERSONA_FILE"
  info "Persona → $PERSONA_FILE (edit this to customize your agent)"
fi

# ── Install LaunchAgent (macOS) ────────────────────────────────────────────────

if [[ "$(uname)" == "Darwin" ]]; then
  header "Installing LaunchAgent..."

  PLIST_LABEL="com.claude.telegram.${AGENT}"
  PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${BASE}/loop.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/.claude/logs/telegram-${AGENT}.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.claude/logs/telegram-${AGENT}.log</string>
</dict>
</plist>
PLIST

  info "Plist → $PLIST_PATH"

  # Unload old instance if running
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load -w "$PLIST_PATH"
  info "LaunchAgent loaded — ${AGENT} is running"
else
  warn "Non-macOS detected — LaunchAgent skipped."
  warn "Start manually with: bash $BASE/loop.sh"
  warn "Or add to your init system (systemd, etc.) to run on startup."
fi

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}All done!${NC}"
echo ""
echo "  Bot name:    $AGENT"
echo "  Loop script: $BASE/loop.sh"
echo "  Persona:     $PERSONA_FILE"
echo "  Log:         $HOME/.claude/logs/telegram-${AGENT}.log"
echo ""
echo "Test it: send your bot a message on Telegram."
echo "Watch the log: tail -f $HOME/.claude/logs/telegram-${AGENT}.log"
echo ""
echo "Voice transcription (optional):"
echo "  pip install mlx-whisper   # Apple Silicon only"
echo "  # The bot will return a graceful error until this is installed."
