#!/bin/bash
# ── Configuration ─────────────────────────────────────────────────────────────
# These are set by install.sh. You can also override them as env vars.
AGENT="${AGENT:-myagent}"
TOKEN_VAR="$(echo "${AGENT}" | tr '[:lower:]' '[:upper:]')_BOT_TOKEN"
CLAUDE_BIN="${CLAUDE_BIN:-${HOME}/.local/bin/claude}"
NODE_BIN="${NODE_BIN:-$(which node 2>/dev/null)}"
PYTHON_BIN="${PYTHON_BIN:-$(which python3 2>/dev/null)}"
HOME_DIR="$HOME"
# ──────────────────────────────────────────────────────────────────────────────

BASE="$HOME_DIR/.claude/telegram/$AGENT"
LOG="$HOME_DIR/.claude/logs/telegram-$AGENT.log"
HISTORY="$BASE/history.txt"
MAX_HISTORY=20

source "$HOME_DIR/.claude/telegram/.env"
eval "TOKEN=\$$TOKEN_VAR"
CHAT_ID=$(cat "$BASE/chat_id.txt")

touch "$HISTORY"

PIDFILE="$BASE/.loop.pid"
if [[ -f "$PIDFILE" ]]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [[ -n "$OLD" && "$OLD" != "$$" ]] && kill -0 "$OLD" 2>/dev/null; then
    # PID is live, but the OS recycles PIDs — confirm it's actually this
    # agent's loop before honoring the lock, otherwise it's a stale pidfile
    # whose number got reassigned to an unrelated process.
    if ps -p "$OLD" -o command= 2>/dev/null | grep -q "telegram/$AGENT/loop.sh"; then
      echo "[$(date)] Already running pid=$OLD, exiting" >> "$LOG"
      exit 0
    fi
    echo "[$(date)] Stale pidfile (pid=$OLD is not this loop), taking over" >> "$LOG"
  fi
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

tg_send() {
  local text="$1"
  local r
  r=$(curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=Markdown" 2>/dev/null)
  if ! echo "$r" | grep -q '"ok":true'; then
    curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
      -d "chat_id=${CHAT_ID}" \
      --data-urlencode "text=${text}" >/dev/null 2>&1 || true
  fi
}

send_chunked() {
  local text="$1"
  while [[ ${#text} -gt 0 ]]; do
    tg_send "${text:0:4000}"
    text="${text:4000}"
    [[ ${#text} -gt 0 ]] && sleep 1
  done
}

typing_loop() {
  while true; do
    curl -sf "https://api.telegram.org/bot${TOKEN}/sendChatAction" \
      -d "chat_id=${CHAT_ID}" -d "action=typing" >/dev/null 2>&1 || true
    sleep 4
  done
}

tg_receive() {
  local tg_timeout="${1:-30}"
  local curl_max=$(( tg_timeout + 5 ))
  [[ $curl_max -lt 5 ]] && curl_max=5
  local offset
  offset=$(cat "$BASE/offset.txt")
  local resp
  resp=$(curl -sf --max-time "$curl_max" \
    "https://api.telegram.org/bot${TOKEN}/getUpdates?offset=${offset}&limit=10&timeout=${tg_timeout}" \
    2>/dev/null) || return 0
  echo "$resp" | "$NODE_BIN" -e "
let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  const d = JSON.parse(raw);
  const allowed = '$CHAT_ID';
  const f = '$BASE/offset.txt';
  if (!d.ok || !d.result.length) return;
  let max = parseInt(require('fs').readFileSync(f, 'utf8')) || 0;
  d.result.forEach(u => {
    if (u.update_id >= max) max = u.update_id + 1;
    if (u.message && String(u.message.chat.id) === allowed) {
      if (u.message.text)
        process.stdout.write(u.message.text + '\n');
      else if (u.message.voice)
        process.stdout.write('__VOICE__:' + u.message.voice.file_id + '\n');
    }
  });
  require('fs').writeFileSync(f, String(max));
});
" 2>/dev/null || true
}

is_cancel() {
  local lower
  lower=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  [[ "$1" == "/stop" || "$lower" == "cancel" || "$lower" == "stop" ]]
}

transcribe_voice() {
  local file_id="$1"
  local whisper_model file_info file_path audio_file transcript
  whisper_model=$(cat "$BASE/whisper_model.txt" 2>/dev/null)
  [[ -z "$whisper_model" ]] && { echo ""; return; }
  file_info=$(curl -sf "https://api.telegram.org/bot${TOKEN}/getFile?file_id=${file_id}" 2>/dev/null) \
    || { echo ""; return; }
  file_path=$(echo "$file_info" | "$NODE_BIN" -e '
const d = JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));
if (d.ok) process.stdout.write(d.result.file_path || "");
' 2>/dev/null) || { echo ""; return; }
  [[ -z "$file_path" ]] && { echo ""; return; }
  audio_file=$(mktemp /tmp/${AGENT}_voice.XXXXXX.ogg)
  curl -sf "https://api.telegram.org/file/bot${TOKEN}/${file_path}" -o "$audio_file" 2>/dev/null \
    || { rm -f "$audio_file"; echo ""; return; }
  transcript=$("$PYTHON_BIN" -c '
import mlx_whisper, sys
result = mlx_whisper.transcribe(sys.argv[1], path_or_hf_repo=sys.argv[2])
print(result["text"].strip())
' "$audio_file" "$whisper_model" 2>/dev/null) || transcript=""
  rm -f "$audio_file"
  echo "$transcript"
}

extract_response() {
  "$PYTHON_BIN" -c '
import sys, json
result = ""
try:
    for line in open(sys.argv[1]):
        try:
            e = json.loads(line)
            if e.get("type") == "result":
                result = e.get("result", "")
                break
        except json.JSONDecodeError:
            pass
except Exception:
    pass
print(result, end="")
' "$1"
}

check_and_deliver_pending() {
  [[ ! -f "$BASE/pending.txt" ]] && return 0
  local pid tmpout user_msg
  { read -r pid; read -r tmpout; user_msg=$(cat); } < "$BASE/pending.txt"
  if kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  rm -f "$BASE/pending.txt"
  local response
  response=$(cat "$tmpout" 2>/dev/null); rm -f "$tmpout"
  if [[ -n "$response" ]]; then
    echo "[$(date)] >> pending job $pid delivered" >> "$LOG"
    send_chunked "$response"
    printf 'User: %s\n%s: %s\n' "$user_msg" "$AGENT" "$response" >> "$HISTORY"
  fi
  return 0
}

kill_pending() {
  [[ ! -f "$BASE/pending.txt" ]] && return 1
  local pid tmpout
  { read -r pid; read -r tmpout; } < "$BASE/pending.txt"
  echo "[$(date)] kill pending job $pid" >> "$LOG"
  kill -KILL "$pid" 2>/dev/null || true
  rm -f "$tmpout" "$BASE/pending.txt"
  return 0
}

RESPONSE=""
NEXT_MSG=""
EXCHANGE_COUNT=0

invoke_claude() {
  local prompt="$1"
  local user_msg="$2"
  local tmpout stream_file
  tmpout=$(mktemp /tmp/${AGENT}_out.XXXXXX)
  stream_file=$(mktemp /tmp/${AGENT}_stream.XXXXXX)

  typing_loop &
  local typing_pid=$!

  "$CLAUDE_BIN" --dangerously-skip-permissions --no-session-persistence --print --verbose \
    --output-format stream-json \
    --model claude-sonnet-4-6 <<< "$prompt" > "$stream_file" 2>>"$LOG" &
  local claude_pid=$!

  "$PYTHON_BIN" "$BASE/status_watcher.py" "$stream_file" "$TOKEN" "$CHAT_ID" "$claude_pid" &
  local watcher_pid=$!

  local waited=0

  while kill -0 "$claude_pid" 2>/dev/null; do
    if (( waited >= 600 )); then
      (
        wait "$claude_pid" 2>/dev/null
        extract_response "$stream_file" > "$tmpout" 2>/dev/null
        rm -f "$stream_file"
      ) &
      local extractor_pid=$!
      printf '%s\n%s\n%s' "$extractor_pid" "$tmpout" "$user_msg" > "$BASE/pending.txt"
      kill "$typing_pid" 2>/dev/null
      kill "$watcher_pid" 2>/dev/null; wait "$watcher_pid" 2>/dev/null
      echo "[$(date)] timeout — claude=$claude_pid → pending extractor=$extractor_pid" >> "$LOG"
      tg_send "Still thinking — I'll follow up when done..."
      return 1
    fi

    local interrupt
    interrupt=$(tg_receive 0)
    if [[ -n "$interrupt" ]]; then
      kill "$typing_pid" 2>/dev/null
      kill "$watcher_pid" 2>/dev/null; wait "$watcher_pid" 2>/dev/null
      kill -KILL "$claude_pid" 2>/dev/null
      rm -f "$stream_file" "$tmpout"
      if is_cancel "$interrupt"; then
        echo "[$(date)] cancelled by user" >> "$LOG"
        tg_send "Cancelled."
      else
        echo "[$(date)] interrupted by new message" >> "$LOG"
        NEXT_MSG="$interrupt"
        tg_send "Interrupted — starting new task..."
      fi
      return 1
    fi

    sleep 2; waited=$(( waited + 2 ))
  done

  wait "$claude_pid" 2>/dev/null
  kill "$typing_pid" 2>/dev/null
  kill "$watcher_pid" 2>/dev/null; wait "$watcher_pid" 2>/dev/null

  RESPONSE=$(extract_response "$stream_file")
  rm -f "$stream_file" "$tmpout"
  return 0
}

echo "[$(date)] $AGENT starting (claude=$CLAUDE_BIN)" >> "$LOG"
unset CLAUDECODE

while true; do
  check_and_deliver_pending || true

  cur_msg=""
  if [[ -n "$NEXT_MSG" ]]; then
    cur_msg="$NEXT_MSG"
    NEXT_MSG=""
  elif [[ -f "$BASE/pending.txt" ]]; then
    cur_msg=$(tg_receive 2)
  else
    cur_msg=$(tg_receive 30)
  fi

  [[ -z "$cur_msg" ]] && continue

  if [[ "$cur_msg" == __VOICE__:* ]]; then
    file_id="${cur_msg#__VOICE__:}"
    echo "[$(date)] <- [voice: $file_id]" >> "$LOG"
    tg_send "_Transcribing voice note..._"
    cur_msg=$(transcribe_voice "$file_id")
    if [[ -z "$cur_msg" ]]; then
      tg_send "Couldn't transcribe — voice not set up or mlx_whisper not installed (see README)."
      continue
    fi
    echo "[$(date)] transcribed: $cur_msg" >> "$LOG"
    cur_msg="[Voice] $cur_msg"
  fi

  echo "[$(date)] <- $cur_msg" >> "$LOG"

  if is_cancel "$cur_msg"; then
    if kill_pending; then
      tg_send "Cancelled."
    else
      tg_send "Nothing to cancel."
    fi
    continue
  fi

  kill_pending && tg_send "Interrupted — starting new task..." || true

  cur_persona=$(cat "$HOME_DIR/.claude/agents/$AGENT.md" 2>/dev/null)
  cur_memory=$(cat "$HOME_DIR/.claude/memory/$AGENT.md" 2>/dev/null)
  cur_hist=$(tail -n $((MAX_HISTORY * 2)) "$HISTORY" 2>/dev/null)
  cur_now=$(date '+%A, %d %B %Y %H:%M %Z')
  cur_prompt=$(printf '%s\n\nDate/time: %s\n\n## Long-term memory\n%s\n\n## Recent conversation\n%s\n\n---\nUser: %s\n---\n\nReply as %s. Keep it concise and mobile-friendly. Markdown is OK.\n\nHEADLESS MODE: never run blocking commands (OAuth flows, sudo prompts, vim/nano, REPLs, foreground servers). If auth is needed, tell the user what to run themselves — do not retry.\n\nTo remember something long-term, append it to %s/.claude/memory/%s.md.' \
    "$cur_persona" "$cur_now" "$cur_memory" "$cur_hist" "$cur_msg" "$AGENT" "$HOME_DIR" "$AGENT")

  RESPONSE=""
  NEXT_MSG=""

  if invoke_claude "$cur_prompt" "$cur_msg"; then
    if [[ -n "$RESPONSE" ]]; then
      send_chunked "$RESPONSE"
      printf 'User: %s\n%s: %s\n' "$cur_msg" "$AGENT" "$RESPONSE" >> "$HISTORY"
      EXCHANGE_COUNT=$(( EXCHANGE_COUNT + 1 ))
      if (( EXCHANGE_COUNT % 20 == 0 )); then
        echo "[$(date)] Distilling memory at exchange $EXCHANGE_COUNT" >> "$LOG"
        mem_prompt="Review this conversation history and extract key facts, preferences, and context worth remembering long-term. Append new items only to $HOME_DIR/.claude/memory/$AGENT.md — do not rewrite existing lines.\n\n$cur_hist"
        printf '%s' "$mem_prompt" | "$CLAUDE_BIN" --dangerously-skip-permissions \
          --no-session-persistence --print --model claude-sonnet-4-6 >> "$LOG" 2>&1 &
      fi
    else
      tg_send "Something went wrong — try again."
    fi
  fi
done
