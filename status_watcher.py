#!/usr/bin/env python3
"""Tail claude's stream-json output and send live status updates via Telegram."""
import sys, json, subprocess, time, os

def main():
    stream_file, token, chat_id, claude_pid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

    def send(msg):
        subprocess.run([
            'curl', '-sf',
            f'https://api.telegram.org/bot{token}/sendMessage',
            '-d', f'chat_id={chat_id}',
            '--data-urlencode', f'text={msg}',
        ], capture_output=True)

    def is_running(pid):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    seen = 0
    start = time.time()
    last_heartbeat = start
    last_send = 0
    MIN_GAP = 8  # seconds between updates to avoid spam

    def maybe_send(msg):
        nonlocal last_send
        now = time.time()
        if now - last_send >= MIN_GAP:
            send(msg)
            last_send = now

    while is_running(claude_pid):
        try:
            with open(stream_file) as f:
                lines = f.readlines()

            for line in lines[seen:]:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if event.get('type') == 'assistant':
                        for item in event.get('message', {}).get('content', []):
                            if item.get('type') != 'tool_use':
                                continue
                            name = item.get('name', '')
                            inp = item.get('input', {})
                            if name == 'Skill':
                                maybe_send(f"⚡ Skill: {inp.get('skill', '')}")
                            elif name == 'Agent':
                                desc = inp.get('description', '')[:50]
                                maybe_send(f"🤖 Agent: {desc}")
                            elif name == 'Bash':
                                cmd = inp.get('command', '').split('\n')[0][:50]
                                maybe_send(f"🔧 `{cmd}`")
                            elif name == 'WebSearch':
                                maybe_send(f"🔍 {inp.get('query', '')[:50]}")
                            elif name == 'WebFetch':
                                maybe_send(f"🌐 Fetching page…")
                            elif name in ('Write', 'Edit'):
                                p = os.path.basename(inp.get('file_path', ''))
                                maybe_send(f"✏️ Editing {p}")
                            elif name == 'Workflow':
                                maybe_send(f"🔀 Running workflow…")
                            elif name and name not in ('Read', 'mcp__ccd_session__mark_chapter'):
                                maybe_send(f"🔧 {name}")
                except (json.JSONDecodeError, KeyError):
                    pass

            seen = len(lines)
        except FileNotFoundError:
            pass

        now = time.time()
        if now - last_heartbeat >= 60:
            elapsed = int(now - start)
            maybe_send(f"⏳ Still working… {elapsed // 60}m{elapsed % 60:02d}s")
            last_heartbeat = now

        time.sleep(3)

if __name__ == '__main__':
    main()
