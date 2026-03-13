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
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code --static-dir static
```

| Flag | Default | Description |
|------|---------|-------------|
| `--host` | `*` (all interfaces) | Address to bind to |
| `--port` | `8080` | HTTP port |
| `--base-dir` | `/code` | Root directory for git worktrees |
| `--static-dir` | `static` | Directory for web UI files |

## Browser Client

A web-based terminal client is available at
https://lambdasistemi.github.io/agent-daemon/

Enter your daemon's address in the server field to connect remotely (e.g. via Tailscale).

## Deployment

### Prerequisites

The following must be available in `PATH`:

- **tmux** — session management
- **git** — worktree operations
- **ssh** — git authentication (agent forwarding or deploy keys)

The user running the daemon needs write access to `--base-dir` and
permission to clone/fetch the repositories it will manage.

### NixOS module

The flake exposes a NixOS module:

```nix
# flake.nix
{
  inputs.agent-daemon.url = "github:lambdasistemi/agent-daemon";

  outputs = { nixpkgs, agent-daemon, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        agent-daemon.nixosModules.default
        {
          services.agent-daemon = {
            enable = true;
            host = "127.0.0.1";
            port = 8080;
            baseDir = "/code";
          };
        }
      ];
    };
  };
}
```

By default the module creates a dedicated `agent-daemon` system user.
To run as an existing user instead:

```nix
services.agent-daemon = {
  enable = true;
  host = "127.0.0.1";
  port = 8080;
  baseDir = "/code";
  user = "paolino";
  group = "users";
  createUser = false;
};
```

### Systemd (manual)

If you're not on NixOS, create a unit file:

```ini
# /etc/systemd/system/agent-daemon.service
[Unit]
Description=Agent daemon — Claude Code session manager
After=network.target

[Service]
Type=simple
User=paolino
Group=users
WorkingDirectory=/code
ExecStart=/usr/local/bin/agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code --static-dir /usr/local/share/agent-daemon/static
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now agent-daemon
journalctl -u agent-daemon -f   # watch logs
```

### Docker / direct binary

Build with nix and copy the binary:

```bash
nix build .#default
# result/bin/agent-daemon is a statically-usable binary

# Or run directly:
nix run .#default -- --host 127.0.0.1 --port 8080 --base-dir /code
```

## HTTPS via Tailscale

The daemon speaks plain HTTP. For HTTPS (required when the dashboard
runs on `https://`), use [Tailscale Serve](https://tailscale.com/kb/1312/serve)
as a TLS-terminating reverse proxy. No certificates to manage — Tailscale
handles provisioning and renewal automatically.

### Setup

1. **Enable HTTPS on your tailnet** (one-time, admin console):

   Go to [DNS settings](https://login.tailscale.com/admin/dns) and
   enable "HTTPS Certificates".

2. **Bind agent-daemon to localhost** so it's not directly exposed:

   ```bash
   agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
   ```

3. **Start Tailscale Serve** to proxy HTTPS on port 8443 to local HTTP:

   ```bash
   # Foreground (for testing):
   sudo tailscale serve --https 8443 http://127.0.0.1:8080

   # Background (persistent across reboots):
   sudo tailscale serve --bg --https 8443 http://127.0.0.1:8080
   ```

4. **Verify**:

   ```bash
   # Check serve status
   tailscale serve status

   # Should show:
   # https://<hostname>.tailnet-name.ts.net:8443 (tailnet only)
   # |-- / proxy http://127.0.0.1:8080

   # Test HTTPS access
   curl https://<hostname>.tailnet-name.ts.net:8443/sessions
   # → []
   ```

### How it works

```
Browser (HTTPS)
    │
    ▼
Tailscale Serve (TLS termination)
    https://<hostname>.ts.net:8443
    │
    ▼ (plain HTTP, localhost only)
agent-daemon
    http://127.0.0.1:8080
    │
    ▼
tmux sessions + git worktrees
```

- The browser connects to `wss://<hostname>.ts.net:8443/sessions/<id>/terminal`
- Tailscale terminates TLS and forwards to `ws://127.0.0.1:8080/...`
- Only machines on your tailnet can reach the service
- Certificates are Let's Encrypt, auto-renewed by Tailscale

### Dashboard configuration

In the gh-dashboard, set the agent server URL to:

```
https://<hostname>.tailnet-name.ts.net:8443
```

This ensures both REST API calls and WebSocket connections use TLS,
avoiding mixed-content browser errors.

### Tailscale Serve management

```bash
tailscale serve status          # show current configuration
tailscale serve reset           # remove all serve rules
tailscale serve --bg --https 8443 http://127.0.0.1:8080   # add rule (persistent)
```
