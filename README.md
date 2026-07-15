# tmux-ws

[![CI](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml)

`tmux-ws` is a local Haskell daemon and PureScript browser SPA for operating
tmux sessions from another screen. The daemon serves the UI and its
REST/WebSocket API from one origin. The UI is touch-first and oriented toward
tablets and small screens, with session/window selectors, guarded close actions,
and an on-screen terminal command deck.

## Install

On macOS, install the primary command with Homebrew:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
```

Linux releases provide a versioned AppImage, stable `tmux-ws.AppImage`, and
packages for `apt` and `dnf`. Verify the accompanying `SHA256SUMS` before
running or installing an artifact. Nix users can run the flake directly, while
NixOS users can enable `services.tmux-ws`.

```bash
nix run github:lambdasistemi/tmux-ws -- --help
```

See the stable [installation guide](https://lambdasistemi.github.io/tmux-ws/docs/installation/)
for checksum, platform, upgrade, service-restart, and browser-refresh steps.

## Run and use

Start the daemon on the machine that owns the tmux sessions:

```bash
tmux-ws --host 127.0.0.1 --port 8080 --base-dir /code
```

Open `http://127.0.0.1:8080/` locally. For a tablet, keep the daemon bound to
localhost and expose that same origin through an HTTPS reverse proxy such as
Tailscale Serve. The [touch usage guide](https://lambdasistemi.github.io/tmux-ws/docs/usage/)
explains the modifier/arrow deck, literal Tmux Ctrl-B prefix, guarded pane and
window closing, refresh, and reconnect behavior.

## Develop and verify

Development is Nix-first:

```bash
nix develop --quiet
just build
```

Run the enduring full local CI route plus the focused documentation checks:

```bash
nix develop --quiet -c just ci
nix run --quiet .#docs-service-contract
nix build --quiet --no-link .#docs .#site
```

The [development guide](https://lambdasistemi.github.io/tmux-ws/docs/development/)
lists the build, test, lint, format, documentation, and live-boundary routes.

## Documentation and releases

The public documentation is at
[lambdasistemi.github.io/tmux-ws/docs/](https://lambdasistemi.github.io/tmux-ws/docs/).
The daemon-served SPA remains the supported control surface; the public site is
for inspection and documentation.

Release assets are discoverable through the stable
[latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest) and
[release history](https://github.com/lambdasistemi/tmux-ws/releases) links.
Version 0.4.0 is imminent but not yet published; consult those pages rather
than assuming its assets exist.

## License

tmux-ws is distributed under the [MIT license](LICENSE).
