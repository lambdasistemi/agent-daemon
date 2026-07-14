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

## Future Linux release artifacts

Future Linux releases provide
`tmux-ws-<version>-x86_64-linux.AppImage`,
`tmux-ws-<version>-x86_64-linux.deb`,
`tmux-ws-<version>-x86_64-linux.rpm`, `SHA256SUMS`, and the stable
`tmux-ws.AppImage` path. Download the matching assets and verify the checksum
before using an AppImage:

```bash
sha256sum -c SHA256SUMS --ignore-missing
chmod +x tmux-ws-<version>-x86_64-linux.AppImage
./tmux-ws-<version>-x86_64-linux.AppImage --help
```

The stable path is the same AppImage under an unversioned name:

```bash
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --help
```

On Debian or Ubuntu, install the downloaded package and then use the canonical
`tmux-ws` executable:

```bash
sudo apt install ./tmux-ws-<version>-x86_64-linux.deb
tmux-ws --help
```

On an RPM-based distribution, use the equivalent RPM package:

```bash
sudo dnf install ./tmux-ws-<version>-x86_64-linux.rpm
tmux-ws --help
```

Pull requests and default manual runs build and smoke artifacts only. They do
not publish production assets. A future immutable `v*` tag attaches production assets only to the planner-created release.
The attachment is idempotent and does not delete or recreate that release.
This PR does not publish, dispatch, retag, rewrite releases, or mutate a tap.

`v0.3.0` is immutable and remains unchanged, and will not be rewritten or deleted.
`v0.3.1` is published with the canonical `tmux-ws-0.3.1-aarch64-darwin.tar.gz` Darwin asset and an
updated Homebrew tap formula. The release workflow used that formula to
update the real Homebrew tap. After an upgrade, restart the daemon
(`systemctl restart tmux-ws` on NixOS) and
reload the browser document on Chrome tablets to fetch the updated SPA. See
[deployment](deployment.md), [Tailscale HTTPS](tailscale.md), and the
[installation guide](index.md#quick-start) for the linked operator flow.

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
