# tmux-ws

`tmux-ws` is a local daemon that serves both the browser SPA and the
REST/WebSocket API used to manage tmux sessions. The supported browser-control
entry point is the SPA served by the daemon itself.

## What it does

- Serves the tmux-ws SPA from `--static-dir`
- Lists and recovers running tmux sessions after daemon restart
- Provides browser-based terminal access via xterm.js and WebSockets
- Switches tmux windows from touch-first browsers
- Manages the session lifecycle: attach, detach, stop, refresh

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
| `--static-dir` | `static` | Directory for the SPA files served by the daemon |

## Prerequisites

The following must be available in `PATH`:

- **tmux** — session management
- **git** — worktree operations
- **ssh** — git authentication (agent forwarding or deploy keys)

The user running the daemon needs permission to inspect and control the tmux
sessions it exposes.

## Browser client

Open the daemon URL in your browser. On the same machine, use localhost:

```
http://127.0.0.1:8080/
```

For a tablet or another machine, expose the same daemon origin through a reverse
proxy such as Tailscale Serve and open that proxied URL directly:

```
https://<hostname>.tailnet-name.ts.net:8443/
```

In both cases, the browser loads the SPA and calls the API from the same origin.

The GitHub Pages build at
[lambdasistemi.github.io/tmux-ws](https://lambdasistemi.github.io/tmux-ws/) is
a public static copy. It is useful for inspection, but browsers may block it
from controlling a localhost or Tailscale daemon because that crosses from a
public origin into a local/private network address space.
