# agent-daemon

WebSocket daemon for managing Claude Code agent sessions via tmux and git worktrees.

## Development

```bash
nix develop
just build
just CI
```

## Usage

```bash
agent-daemon --port 8080 --base-dir /code
```
