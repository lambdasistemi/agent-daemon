# HTTPS via Tailscale

The daemon speaks plain HTTP. For HTTPS (required when the dashboard
runs on `https://`), use [Tailscale Serve](https://tailscale.com/kb/1312/serve)
as a TLS-terminating reverse proxy. No certificates to manage — Tailscale
handles provisioning and renewal automatically.

## Setup

### 1. Enable HTTPS on your tailnet

One-time step in the admin console:

Go to [DNS settings](https://login.tailscale.com/admin/dns) and
enable **HTTPS Certificates**.

### 2. Bind agent-daemon to localhost

Keep the daemon off the public network:

```bash
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
```

### 3. Start Tailscale Serve

Proxy HTTPS on port 8443 to the local HTTP server:

```bash
# Foreground (for testing):
sudo tailscale serve --https 8443 http://127.0.0.1:8080

# Background (persistent across reboots):
sudo tailscale serve --bg --https 8443 http://127.0.0.1:8080
```

### 4. Verify

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

## How it works

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

## Dashboard configuration

In the gh-dashboard, set the agent server URL to:

```
https://<hostname>.tailnet-name.ts.net:8443
```

This ensures both REST API calls and WebSocket connections use TLS,
avoiding mixed-content browser errors.

## Management commands

```bash
tailscale serve status          # show current configuration
tailscale serve reset           # remove all serve rules
tailscale serve --bg --https 8443 http://127.0.0.1:8080   # add rule
```
