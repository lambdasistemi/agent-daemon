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

## Browser Client

A web-based terminal client is available at
https://lambdasistemi.github.io/agent-daemon/

Enter your daemon's address in the server field to connect remotely (e.g. via Tailscale).
