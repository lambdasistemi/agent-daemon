# Release and migration

v0.4.0 is imminent but not yet published. Do not assume a `v0.4.0` tag or its
assets exist until they appear through the stable
[latest-release link](https://github.com/lambdasistemi/tmux-ws/releases/latest)
or [release history](https://github.com/lambdasistemi/tmux-ws/releases).

The permanent operator flow is documented in the stable
[installation guide](https://lambdasistemi.github.io/tmux-ws/docs/installation/)
and [touch usage guide](https://lambdasistemi.github.io/tmux-ws/docs/usage/).

## Expected v0.4.0 routes

Once v0.4.0 is published, its Linux release contract is expected to include:

- `tmux-ws-0.4.0-x86_64-linux.AppImage`
- `tmux-ws-0.4.0-x86_64-linux.deb`
- `tmux-ws-0.4.0-x86_64-linux.rpm`
- the stable `tmux-ws.AppImage` copy
- `SHA256SUMS` covering the versioned packages and both AppImage names

Download the checksum file and selected asset from the same release. Verify
before execution or installation:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

Run a verified versioned or stable AppImage with:

```bash
chmod +x tmux-ws-0.4.0-x86_64-linux.AppImage
./tmux-ws-0.4.0-x86_64-linux.AppImage --help

chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --help
```

Install a verified package through the distribution package manager:

```bash
sudo apt install ./tmux-ws-0.4.0-x86_64-linux.deb
sudo dnf install ./tmux-ws-0.4.0-x86_64-linux.rpm
tmux-ws --help
```

The macOS route remains the primary Homebrew formula:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
```

NixOS operators use `services.tmux-ws` and rebuild their configuration as
described in [deployment](deployment.md). Nix users can run the repository flake
directly.

## Upgrade and reconnect

Existing Homebrew users upgrade the primary formula:

```bash
brew update
brew upgrade tmux-ws
tmux-ws --help
```

Linux artifact users fetch the new artifact and matching `SHA256SUMS`, verify
them, then replace the AppImage or install the package with `apt`/`dnf`. NixOS
users update the pinned input and rebuild.

After any service-backed upgrade, restart and verify the daemon:

```bash
sudo systemctl restart tmux-ws
systemctl status tmux-ws
```

Then reload the browser document. The in-app **Refresh** action only refreshes
tmux state. On a tablet, use a browser hard refresh—or fully close and reopen
the tab—before reconnecting to a recovered tmux session.

## Published history and compatibility

`v0.3.0` is immutable and will not be rewritten or deleted. `v0.3.1` is the
published corrective version with the canonical
`tmux-ws-0.3.1-aarch64-darwin.tar.gz` asset. Its release workflow used the
shared formula renderer to update the real Homebrew tap.

That corrective release keeps `agent-daemon` only as a bounded compatibility
route. The command forwards to the installed `tmux-ws` binary; the renamed
NixOS option configures the single `services.tmux-ws` service. New users should
not install or enable a second legacy daemon.

### Legacy Homebrew users

Install the primary formula first and migrate scripts. If the deprecated alias
is still temporarily required:

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
brew upgrade agent-daemon
agent-daemon --help
```

After migration, remove the compatibility formula:

```bash
brew uninstall agent-daemon
tmux-ws --help
```

### Legacy NixOS users

Rename `services.agent-daemon` to `services.tmux-ws`, rebuild, and operate the
single primary unit:

```bash
sudo nixos-rebuild switch
sudo systemctl restart tmux-ws
systemctl status tmux-ws
systemctl is-active tmux-ws
```

The compatibility route is limited to the corrective release; removal requires
a separately reviewed migration ticket.
