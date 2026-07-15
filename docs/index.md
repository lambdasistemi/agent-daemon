# tmux-ws

`tmux-ws` is a local daemon and browser SPA for operating tmux sessions. The
daemon serves the PureScript UI and its Haskell REST/WebSocket API from the same
origin, avoiding a separate dashboard deployment.

The SPA is touch-first and designed for tablets and small screens. It provides
session and window selection, terminal access, reusable paste snippets,
display settings, guarded close-current actions, and a compact command deck for
keys that tablet keyboards often cannot send.

## Choose a guide

- **User:** [install or upgrade tmux-ws](installation.md), then learn the
  [touch control surface](usage.md).
- **Operator:** configure a persistent [NixOS or systemd deployment](deployment.md),
  optionally protected by [Tailscale HTTPS](tailscale.md), and follow the
  [release and migration guide](release.md).
- **Developer:** enter the Nix environment and run the project-owned checks in
  the [development guide](development.md); consult [design](design.md) for
  architecture details.

## Quick start from source

```bash
nix develop --quiet
just build
tmux-ws --host 127.0.0.1 --port 8080 --base-dir /code
```

Open `http://127.0.0.1:8080/` on the same machine. For another device, keep the
daemon bound to localhost, configure [Tailscale HTTPS](tailscale.md), and open
the proxied daemon URL. The daemon URL—not the public GitHub Pages copy—is the
supported browser-control origin.

## Runtime prerequisites

The daemon expects these programs in `PATH`:

- `tmux` for session management
- `git` for worktree operations
- `ssh` for authenticated Git operations

The daemon process must run as the user who owns the tmux sessions, or be
configured to use that user's tmux socket directory. On restart it imports
existing tmux sessions directly; session IDs are the tmux session names.

## Public site

The combined GitHub Pages build publishes a static SPA copy at the site root
and these guides under `/docs/`. The public SPA is useful for inspection, but
browsers may block it from controlling localhost or a private tailnet origin.
Use the daemon-served SPA for real operation.
