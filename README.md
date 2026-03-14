# agent-daemon

[![CI](https://github.com/lambdasistemi/agent-daemon/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdasistemi/agent-daemon/actions/workflows/ci.yml)

WebSocket daemon for managing Claude Code agent sessions via tmux and git worktrees.

## Documentation

See the [full documentation](https://lambdasistemi.github.io/agent-daemon/docs/).

- [Design](https://lambdasistemi.github.io/agent-daemon/docs/design/) — architecture, API reference, data model
- [Deployment](https://lambdasistemi.github.io/agent-daemon/docs/deployment/) — NixOS module, systemd, direct binary
- [Tailscale HTTPS](https://lambdasistemi.github.io/agent-daemon/docs/tailscale/) — TLS setup via `tailscale serve`

## Quick start

```bash
nix develop
just build
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
```
