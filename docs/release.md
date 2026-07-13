# Release and migration

## New installations

Install the primary product with Homebrew:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
```

NixOS users should configure `services.tmux-ws` and enable the `tmux-ws`
systemd service.

`v0.3.0` is immutable and will not be rewritten or deleted. The corrective
`v0.3.1` release will publish a new Darwin asset and update the real Homebrew tap;
this PR itself does neither. After an upgrade, restart the daemon
(`systemctl restart tmux-ws` on NixOS) and reload the browser document to fetch
the updated SPA. See [deployment](deployment.md), [Tailscale HTTPS](tailscale.md),
and the [installation guide](index.md#quick-start) for the linked operator flow.

## Corrective-release compatibility

This corrective release keeps `agent-daemon` only as a bounded compatibility
route. Existing Homebrew command users can run `agent-daemon --help`; it
forwards to the installed `tmux-ws` binary without adding a second daemon.
Existing NixOS configurations using `services.agent-daemon` are accepted as a
renamed option and configure the single `services.tmux-ws` service.

### Existing Homebrew users

Existing `tmux-ws` users can update and upgrade the installed primary formula:

```bash
brew update
brew upgrade tmux-ws
tmux-ws --help
```

Existing legacy-only `agent-daemon` users must install the primary formula
first, migrate scripts, then choose one compatibility path:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
# Keep the deprecated command alias temporarily:
brew upgrade agent-daemon
agent-daemon --help
```

Or, after migration, remove the compatibility formula:

```bash
brew uninstall agent-daemon
tmux-ws --help
```

The deprecated `agent-daemon` formula is not the new-install default.

### Existing NixOS users

Rename `services.agent-daemon` to `services.tmux-ws` in your configuration,
then rebuild and verify the single new unit:

```bash
sudo nixos-rebuild switch
sudo systemctl restart tmux-ws
systemctl status tmux-ws
systemctl is-active tmux-ws
```

Do not start `agent-daemon.service`: the renamed option creates only
`tmux-ws.service`.

Move configurations and scripts to `services.tmux-ws`, `systemctl restart
tmux-ws`, and `tmux-ws`. The legacy compatibility route is limited to this
corrective release; its removal requires a separately reviewed migration ticket.
