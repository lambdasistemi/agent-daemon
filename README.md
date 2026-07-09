# tmux-ws

[![CI](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml)

WebSocket daemon for managing local tmux sessions from a browser.

## Documentation

See the [full documentation](https://lambdasistemi.github.io/tmux-ws/docs/).

## Quick start

```bash
nix develop
just build
agent-daemon --host 127.0.0.1 --port 8080 --base-dir /code
```

## Session Recovery

On startup, the daemon imports existing tmux sessions directly. Session ids are
tmux session names, such as `0`, and no repo or issue naming convention is
applied.

## Browser Console

Open the daemon URL in a browser to use the bundled console. It can stop tmux
sessions, attach to the selected tmux session, disconnect, and refresh the
session list.

Destructive session actions require exact confirmation. The REST delete endpoint
must be called as `DELETE /sessions/:sid?confirm=:sid`; the browser client
requires typing the session id before enabling the final action.
