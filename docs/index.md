# Agent Daemon

WebSocket daemon for managing Claude Code agent sessions via tmux and git worktrees.

## What it does

- Launches Claude Code sessions tied to GitHub issues
- Creates git worktrees and tmux sessions automatically
- Provides browser-based terminal access via xterm.js and WebSockets
- Recovers running sessions after daemon restart
- Manages the full session lifecycle: create, attach, detach, stop

## Quick start

```bash
# Build
nix develop
just build

# Run
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
```

## CLI options

| Flag | Default | Description |
|------|---------|-------------|
| `--host` | `*` (all interfaces) | Address to bind to |
| `--port` | `8080` | HTTP port |
| `--base-dir` | `/code` | Root directory for git worktrees |
| `--static-dir` | `static` | Directory for web UI files |

## Prerequisites

The following must be available in `PATH`:

- **tmux** — session management
- **git** — worktree operations
- **ssh** — git authentication (agent forwarding or deploy keys)

The user running the daemon needs write access to `--base-dir` and
permission to clone/fetch the repositories it will manage.

## Browser client

A web-based terminal client is available at
[lambdasistemi.github.io/agent-daemon](https://lambdasistemi.github.io/agent-daemon/)

Enter your daemon's address in the server field to connect remotely (e.g. via Tailscale).
