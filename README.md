# tmux-ws

[![CI](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml)

`tmux-ws` is a local daemon that serves the browser SPA and the
REST/WebSocket API from the same origin. Open the SPA from the daemon URL
itself to manage local tmux sessions from a browser.

## Documentation

See the [full documentation](https://lambdasistemi.github.io/tmux-ws/docs/).

## Quick start

```bash
nix develop
just build
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
```

Then open the daemon URL in a browser on the same machine:

```
http://127.0.0.1:8080/
```

For another device, expose that same daemon origin through a reverse proxy such
as Tailscale Serve and open the proxied URL directly. In both modes, the URL
serves the SPA and API together.

## Session Recovery

On startup, the daemon imports existing tmux sessions directly. Session ids are
tmux session names, such as `0`, and no repo or issue naming convention is
applied.

## Browser Console

Open the daemon URL in a browser to use the bundled SPA. It can stop tmux
sessions, attach to the selected tmux session, disconnect, switch tmux windows,
and refresh the session list.

The GitHub Pages build is useful for public inspection and documentation, but
browser control should come from the daemon-served SPA. Public origins such as
GitHub Pages can be blocked by browser local-network protections when they try
to call a Tailscale or localhost daemon.

Destructive session actions require exact confirmation. The REST delete endpoint
must be called as `DELETE /sessions/:sid?confirm=:sid`; the browser client
requires typing the session id before enabling the final action.
