# Installation and upgrades

Release artifacts are published on the stable
[latest-release page](https://github.com/lambdasistemi/tmux-ws/releases/latest),
with all historical versions on the
[releases page](https://github.com/lambdasistemi/tmux-ws/releases).

!!! warning "v0.4.0 publication status"
    v0.4.0 is imminent but not yet published. Until it appears on the releases
    page, do not construct v0.4.0 download URLs or assume its assets exist. The
    names below describe the release contract using `<version>` placeholders.

## Verify Linux downloads

Download `SHA256SUMS` and the desired artifact from the same GitHub release,
place them in one directory, and verify before making an AppImage executable or
installing a package:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

The command must report `OK` for the file you intend to use. A missing entry,
checksum mismatch, or artifact from a different release is a stop condition.

Expected Linux assets are:

- `tmux-ws-<version>-x86_64-linux.AppImage`
- `tmux-ws-<version>-x86_64-linux.deb`
- `tmux-ws-<version>-x86_64-linux.rpm`
- `tmux-ws.AppImage`, the stable unversioned copy of that release's AppImage
- `SHA256SUMS`, covering all four files above

## Linux AppImage

Use the versioned name when scripts or archives must identify an exact release:

```bash
chmod +x tmux-ws-<version>-x86_64-linux.AppImage
./tmux-ws-<version>-x86_64-linux.AppImage --help
```

Use the stable path when an operator-managed location should keep one filename
across upgrades:

```bash
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --help
```

Replacing `tmux-ws.AppImage` changes the executable on disk; restart the
running daemon before expecting the new SPA or server code.

## Debian and Ubuntu (`apt`)

After checksum verification:

```bash
sudo apt install ./tmux-ws-<version>-x86_64-linux.deb
tmux-ws --help
```

Using `apt install ./...` records the local package with the system package
database and installs its declared runtime dependencies.

## RPM distributions (`dnf`)

After checksum verification:

```bash
sudo dnf install ./tmux-ws-<version>-x86_64-linux.rpm
tmux-ws --help
```

## macOS Homebrew

Install the primary formula from the lambdasistemi tap:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
```

New installations should use `tmux-ws`; the historical `agent-daemon` formula
is only a compatibility route for existing users.

## Nix and NixOS

Run the flake without a global install:

```bash
nix run github:lambdasistemi/tmux-ws -- --help
```

For a persistent NixOS service, add the flake's module and configure
`services.tmux-ws`. The [deployment guide](deployment.md) contains a complete
module example, including the tmux owner and socket-directory requirements.

## Upgrade

Homebrew users upgrade the primary formula in place:

```bash
brew update
brew upgrade tmux-ws
tmux-ws --help
```

Linux artifact users download the new release's artifact and `SHA256SUMS`,
verify them together, then replace the AppImage or install the new local
package with the same `apt` or `dnf` command shown above. Nix/NixOS users update
the pinned flake input and rebuild their configuration.

Restart a system service after replacing or upgrading the executable:

```bash
sudo systemctl restart tmux-ws
systemctl status tmux-ws
```

The in-app **Refresh** button reloads tmux state, not the browser application.
After an upgrade and daemon restart, reload the browser document. On a tablet,
use the browser's hard refresh (or fully close and reopen the tab if the browser
does not expose one) before reconnecting to a terminal.

For exposure beyond localhost, continue with [Tailscale HTTPS](tailscale.md).
