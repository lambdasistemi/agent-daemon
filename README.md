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

Open the daemon URL in a browser to use the bundled, touch-first SPA. A tablet
operator can use it without a keyboard or mouse. The header always shows the
selected **Session** and active **Window**, while the bottom action dock
provides **Refresh**, **Terminal**, **Paste**, and **Settings**. These controls
cover session/window selection, terminal keys and text selection, saved paste
snippets, display preferences, and guarded destructive actions.

Under **Settings**, **Close this pane** and **Close this window** first ask the
server what closing the current tmux context would do. Review that preview and
confirm in the sheet that follows. The server rejects the action if the tmux
topology changes between preview and confirmation. Closing the final pane in
the final window, or closing the final window, ends the session; otherwise the
SPA reloads the surviving session/window state and reconnects the terminal.

**Refresh** reloads the daemon's session and window registry inside the running
SPA. It does not download a new copy of the application. To fetch the SPA again
after an upgrade, reload the browser document. Daemon-served UI responses carry
`no-store` cache headers, so Chrome is instructed not to retain an old UI.

The GitHub Pages build is useful for public inspection and documentation, but
browser control should come from the daemon-served SPA. Public origins such as
GitHub Pages can be blocked by browser local-network protections when they try
to call a Tailscale or localhost daemon.

Ending a whole session remains a separate action and requires typing its exact
session id before the final button is enabled.

For unattended, reboot-persistent access, see the
[NixOS deployment](https://lambdasistemi.github.io/tmux-ws/docs/deployment/)
and [Tailscale Serve](https://lambdasistemi.github.io/tmux-ws/docs/tailscale/)
guides.
