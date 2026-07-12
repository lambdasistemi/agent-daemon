# HTTPS via Tailscale

The daemon serves the SPA and API over plain HTTP. When the browser runs on the
same machine, open `http://127.0.0.1:8080/` directly.

For another device, use [Tailscale Serve](https://tailscale.com/kb/1312/serve)
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
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /path/to/worktrees
```

### 3. Start Tailscale Serve

Choose an HTTPS port and proxy it to the daemon's localhost port. The values
below are generic examples:

```bash
# Foreground (for testing):
sudo tailscale serve --https 8443 http://127.0.0.1:8080

# Background; tailscaled stores the route and restores it after reboot:
sudo tailscale serve --bg --https 8443 http://127.0.0.1:8080
```

Use the `--bg` form for an unattended deployment. It records the Serve route in
Tailscale's node state, so the route returns when `tailscaled` restarts; a
foreground command exists only for as-long-as-that-process testing. Enable both
the daemon service and `tailscaled` at boot. You do not need a separate wrapper
service that reruns `tailscale serve` on every boot.

### 4. Open the SPA

```bash
# Check serve status
tailscale serve status

# Should show:
# https://<host>.<tailnet>.ts.net:8443 (tailnet only)
# |-- / proxy http://127.0.0.1:8080

# Test HTTPS API access
curl https://<host>.<tailnet>.ts.net:8443/sessions
# → []
```

Then open the same HTTPS origin in the browser:

```
https://<host>.<tailnet>.ts.net:8443/
```

That page is the tmux-ws SPA served by the daemon through Tailscale. It is the
supported tablet control surface because the SPA and API share the same proxied
origin.

## How it works

```
Browser (HTTPS)
    │
    ▼
Tailscale Serve (TLS termination)
    https://<host>.<tailnet>.ts.net:8443
    │
    ▼ (plain HTTP, localhost only)
tmux-ws daemon
    http://127.0.0.1:8080
    │
    ▼
tmux sessions + git worktrees
```

- The browser loads the SPA from `https://<host>.<tailnet>.ts.net:8443/`
- The SPA calls REST endpoints on the same origin, such as `/sessions`
- The browser connects to
  `wss://<host>.<tailnet>.ts.net:8443/sessions/<id>/terminal`
- Tailscale terminates TLS and forwards to `ws://127.0.0.1:8080/...`
- Only machines on your tailnet can reach the service
- Certificates are Let's Encrypt, auto-renewed by Tailscale

## Public static build

The GitHub Pages build is a public static copy. It is useful for inspection and
documentation, but browsers may block it from calling a localhost or Tailscale
daemon because that crosses from a public origin into a local/private network
address space. For real browser control, open the Tailscale URL above.

## Dashboard configuration

If another dashboard needs to call tmux-ws directly, set the agent server URL
to:

```
https://<host>.<tailnet>.ts.net:8443
```

This ensures both REST API calls and WebSocket connections use TLS,
avoiding mixed-content browser errors.

## Management commands

```bash
tailscale serve status          # show current configuration
tailscale serve reset           # remove all serve rules
tailscale serve --bg --https 8443 http://127.0.0.1:8080   # add rule
```

`tailscale serve status` is the reboot check: it should still show the HTTPS
listener and localhost proxy before a tablet connects.
