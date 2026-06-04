# Contributing

Contributions are welcome! Please open an issue first to discuss what you'd like to change.

## Getting started

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test manually — send messages to your bot and confirm the behaviour is correct
5. Push and open a pull request

## Key things to keep in sync

- If you change `loop.sh`, check whether `INSTALL_PROMPT.md` needs updating (e.g. new config values, new dependencies)
- If you change the voice transcription logic, update both `loop.sh` and the Step 9 instructions in `INSTALL_PROMPT.md`

## Code style

- `loop.sh` — bash, POSIX-compatible where possible; avoid bashisms that don't work on macOS's default bash 3.2 unless clearly documented
- `status_watcher.py` — standard library only (plus `mlx_whisper` for transcription); no third-party deps in the watcher

## Reporting issues

Please include:
- macOS version and chip (Intel / Apple Silicon)
- Output of `tail -20 ~/.claude/logs/telegram-<agentname>.log`
- What you expected vs what happened
