# Release and migration

## New installations

Install a published artifact from the
[latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest).
Normal installations do not require Nix or a source checkout.

On x86_64 Linux, the stable AppImage is the shortest path:

```bash
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/tmux-ws.AppImage
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

Debian, Ubuntu, Fedora, and RHEL users can instead download the `.deb` or `.rpm`
from that release and install it with the platform package manager. Apple
Silicon macOS users install the released archive through Homebrew:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

NixOS service configuration is an advanced option for reboot-persistent daemon
operation; it is not the general installation path. See [deployment](deployment.md).

## Linux release artifacts

Published releases provide
`tmux-ws-<version>-x86_64-linux.AppImage`,
`tmux-ws-<version>-x86_64-linux.deb`,
`tmux-ws-<version>-x86_64-linux.rpm`, `SHA256SUMS`, and the stable
`tmux-ws.AppImage` path. Download the matching assets and verify the checksum
before using an AppImage:

```bash
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/tmux-ws.AppImage
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --help
```

The stable path is the same AppImage under an unversioned name. Use the
versioned AppImage from the release page only when you need to pin a specific
release.

On Debian or Ubuntu, install the downloaded package and then use the canonical
`tmux-ws` executable:

```bash
sudo apt install ./tmux-ws-*-x86_64-linux.deb
tmux-ws --help
```

On an RPM-based distribution, use the equivalent RPM package:

```bash
sudo dnf install ./tmux-ws-*-x86_64-linux.rpm
tmux-ws --help
```

Pull requests and manual workflow runs build and smoke artifacts only; they do
not publish production assets. An immutable `v*` tag attaches production assets
only to the planner-created release. Attachment is idempotent and does not
delete or recreate that release.

`v0.3.0` is immutable and remains unchanged; it will not be rewritten or deleted.
`v0.3.1` is the corrective publication that introduced the canonical
Darwin archive and used the release workflow to update the real Homebrew tap.
Current releases likewise include a versioned Apple Silicon Darwin archive and
update the Homebrew formula without changing historical releases. After an
upgrade, restart the daemon
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
