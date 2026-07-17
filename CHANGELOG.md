# Changelog

## [0.5.1] (2026-07-17)

tmux-ws 0.5.1 is the installable corrective release for the tablet command
deck and touch-friendly context menus introduced in 0.5.0.

### Release status

The immutable v0.5.0 tag and release remain available, but their asset jobs
stopped at tag-message validation and attached no binaries. Use v0.5.1 for
installation. It contains the same tablet UI plus the repaired release path.

### Tablet and browser coverage

- Sessions and Windows use bottom menus sized for touch and small screens.
- Esc, Tab, Enter, arrows, and every Ctrl/Alt/Shift/Tmux combination send exact
  terminal bytes once per tap.
- Held arrows stop on release, pointer cancellation/leave, and browser blur.
- Playwright exercises 390x844, 768x1024, and 1024x768 touch viewports,
  including all 15 modifier combinations, latches, repeat lifecycle, native
  xterm virtual-keyboard input, WebSocket bytes, and browser errors.

### Install or upgrade

Download Linux builds from the
[v0.5.1 release](https://github.com/lambdasistemi/tmux-ws/releases/tag/v0.5.1):

- `tmux-ws-0.5.1-x86_64-linux.AppImage`
- `tmux-ws-0.5.1-x86_64-linux.deb`
- `tmux-ws-0.5.1-x86_64-linux.rpm`
- stable `tmux-ws.AppImage`
- `SHA256SUMS`

Verify downloads with `sha256sum -c SHA256SUMS --ignore-missing`. On Apple
Silicon macOS:

```bash
brew update
brew upgrade tmux-ws || brew install lambdasistemi/tap/tmux-ws
```

### Documentation

- [Quick start and installation](https://lambdasistemi.github.io/tmux-ws/docs/#quick-start)
- [Release packages and migration](https://lambdasistemi.github.io/tmux-ws/docs/release/)
- [NixOS deployment and service operation](https://lambdasistemi.github.io/tmux-ws/docs/deployment/)
- [Persistent Tailscale HTTPS for tablets](https://lambdasistemi.github.io/tmux-ws/docs/tailscale/)

### Release reliability

Release tags are published through GitHub's annotated-tag and reference APIs
without broadening the org-wide App's permissions. Tag validation now reads the
tag object's contents directly, including API-created messages without a final
line feed.

### Included changes

- fix(release): validate API-created tag messages (7e511f0)


## [0.5.0] (2026-07-17)

> Publication note: v0.5.0 remains immutable, but its asset workflows attached
> no binaries. Install v0.5.1 instead.

tmux-ws 0.5.0 makes its tablet command deck dependable and adds browser-level
regression coverage for the no-keyboard workflow.

### Tablet controls

- Sessions and Windows open touch-friendly bottom menus, keeping their actions
  reachable on small screens.
- Esc, Tab, Enter, arrows, and Ctrl/Alt/Shift/Tmux combinations now send exactly
  one terminal sequence per tap. In particular, `Tmux` + `Up` no longer leaks a
  second plain `Up` after Chrome synthesizes a click.
- Held arrows stop on release, pointer cancellation, pointer leave, or browser
  focus loss, so a tablet cannot keep scrolling after Chrome is backgrounded.
- Modifier latches remain one-shot and can be cancelled without sending terminal
  input.

### Browser regression suite

The Playwright interaction suite runs at 390x844, 768x1024, and 1024x768. It
checks every direct command button, all 15 non-empty Ctrl/Alt/Shift/Tmux
combinations, latch cancellation and clearing, arrow-repeat lifecycle,
keyboard/assistive activation, native xterm virtual-keyboard input, exact
WebSocket bytes, and browser errors. Pull requests also publish an isolated UI
preview for real-device review.

### Install or upgrade

Download Linux builds from the
[v0.5.0 release](https://github.com/lambdasistemi/tmux-ws/releases/tag/v0.5.0):

- `tmux-ws-0.5.0-x86_64-linux.AppImage`
- `tmux-ws-0.5.0-x86_64-linux.deb`
- `tmux-ws-0.5.0-x86_64-linux.rpm`
- stable `tmux-ws.AppImage`
- `SHA256SUMS`

Verify downloaded assets with `sha256sum -c SHA256SUMS --ignore-missing` before
running or installing them. On Apple Silicon macOS:

```bash
brew update
brew upgrade tmux-ws || brew install lambdasistemi/tap/tmux-ws
```

### Documentation

- [Quick start and installation](https://lambdasistemi.github.io/tmux-ws/docs/#quick-start)
- [Release packages and migration](https://lambdasistemi.github.io/tmux-ws/docs/release/)
- [NixOS deployment and service operation](https://lambdasistemi.github.io/tmux-ws/docs/deployment/)
- [Persistent Tailscale HTTPS for tablets](https://lambdasistemi.github.io/tmux-ws/docs/tailscale/)

### Included changes

- fix(ui): stop arrow repeat on browser blur (d84867e)
- fix(ui): send touch command deck keys once (5826d78)
- ci: publish PR-only UI preview (d97f2f9)
- feat(ui): add touch context bottom sheets (b98e5ba)
- docs: lead README with release installs (453a5b3)


## [0.4.0] (2026-07-15)

tmux-ws now ships reproducible x86_64 Linux packages alongside the existing Apple Silicon/Homebrew distribution.

### Linux packages

The release includes:

- `tmux-ws-0.4.0-x86_64-linux.AppImage`
- `tmux-ws-0.4.0-x86_64-linux.deb`
- `tmux-ws-0.4.0-x86_64-linux.rpm`
- the stable `tmux-ws.AppImage` download name
- `SHA256SUMS`

Verify downloaded assets before installation:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

For AppImage:

```bash
chmod +x tmux-ws-0.4.0-x86_64-linux.AppImage
./tmux-ws-0.4.0-x86_64-linux.AppImage --help
```

For Debian or Ubuntu:

```bash
sudo apt install ./tmux-ws-0.4.0-x86_64-linux.deb
tmux-ws --help
```

For Fedora or another RPM-based distribution:

```bash
sudo dnf install ./tmux-ws-0.4.0-x86_64-linux.rpm
tmux-ws --help
```

### macOS

```bash
brew update
brew install lambdasistemi/tap/tmux-ws
tmux-ws --help
```

### Documentation

- [Quick start and installation](https://lambdasistemi.github.io/tmux-ws/docs/#quick-start)
- [Release, Linux packages, and migration guide](https://lambdasistemi.github.io/tmux-ws/docs/release/)
- [Deployment and service operation](https://lambdasistemi.github.io/tmux-ws/docs/deployment/)
- [Tailscale HTTPS setup](https://lambdasistemi.github.io/tmux-ws/docs/tailscale/)

### Release integrity

Linux packages are built and smoke-tested from the immutable `v0.4.0` tag. AppImage, DEB, and RPM contents are extracted and the canonical `tmux-ws --help` surface is exercised before publication. Historical releases, including v0.3.1, remain unchanged.


## [0.3.1](https://github.com/lambdasistemi/tmux-ws/compare/v0.3.0...v0.3.1) (2026-07-13)

### Corrective packaging release

`tmux-ws` is now the canonical package, executable, Darwin archive, Homebrew
formula, NixOS option, and systemd unit. The `agent-daemon` command and formula
remain only as a bounded migration route for this corrective release.

- **New Homebrew installs:** run `brew update`,
  `brew install lambdasistemi/tap/tmux-ws`, then `tmux-ws --help`.
- **Legacy Homebrew migration:** install `tmux-ws` first and migrate scripts.
  Then either upgrade `agent-daemon` to retain its temporary command alias or
  uninstall it after migration.
- **NixOS migration:** rename `services.agent-daemon` to `services.tmux-ws`.
  The compatibility option maps to the single `tmux-ws.service`; private
  account and state defaults stay unchanged to avoid disrupting upgrades.
- **Browser refresh after upgrade:** restart the daemon, then reload the
  browser document. The in-app **Refresh** action reloads tmux state, not the
  installed SPA document—this distinction matters on Chrome tablets.
- **Immutable history:** `v0.3.0` is unchanged. This release publishes the new
  `tmux-ws-0.3.1-aarch64-darwin.tar.gz` asset and updates the real Homebrew tap.

See [installation](https://lambdasistemi.github.io/tmux-ws/docs/#quick-start),
the [release and migration guide](https://lambdasistemi.github.io/tmux-ws/docs/release/),
[deployment](https://lambdasistemi.github.io/tmux-ws/docs/deployment/), and
[Tailscale HTTPS](https://lambdasistemi.github.io/tmux-ws/docs/tailscale/).

## [0.3.0](https://github.com/lambdasistemi/tmux-ws/compare/v0.2.0...v0.3.0) (2026-07-13)


### Features

* add touch terminal command deck ([6e75f3f](https://github.com/lambdasistemi/tmux-ws/commit/6e75f3fdef6fd387afa909f95041b942d2c4a7c2))
* model terminal command deck input ([d443b6b](https://github.com/lambdasistemi/tmux-ws/commit/d443b6b7b00cb3bcd8e304286484998d9d5df940))


### Bug Fixes

* keep touch command deck visible ([af9ecd4](https://github.com/lambdasistemi/tmux-ws/commit/af9ecd4216db71930a68ec87d317a9bf282b6f07))
* **release:** recover rebased releases safely ([220fa85](https://github.com/lambdasistemi/tmux-ws/commit/220fa85070e783eb75c01fc08a3ecfe120b006f0))


### Reverts

* restore gate after command-deck visibility regression ([f8e9cf3](https://github.com/lambdasistemi/tmux-ws/commit/f8e9cf3c5b9525615f4325066c8a8815fbce3442))

## [0.2.0](https://github.com/lambdasistemi/tmux-ws/compare/v0.1.1...v0.2.0) (2026-07-12)


### Features

* add touch close-current actions ([e1dcd53](https://github.com/lambdasistemi/tmux-ws/commit/e1dcd533edba0c2a0a75c162128ac9cbd4250173))
* close current tmux contexts safely ([c1d0e56](https://github.com/lambdasistemi/tmux-ws/commit/c1d0e5613a707b140c968f207aafd34252391399))
* expose close-current API actions ([63656be](https://github.com/lambdasistemi/tmux-ws/commit/63656be7e6a7b75fa50b43e7108c3a101d42ce82))
* model close-current transitions ([4b8bd14](https://github.com/lambdasistemi/tmux-ws/commit/4b8bd14fa12bf331f068e12dcc2fee43d29e500c))
* **ui:** make workspace touch-first ([63e1e37](https://github.com/lambdasistemi/tmux-ws/commit/63e1e3765174113d2bc4ba10de559fe48bd50576))


### Bug Fixes

* **ci:** isolate hosted runner verification ([306cb26](https://github.com/lambdasistemi/tmux-ws/commit/306cb26e2d8c142cc0c39184cdebc46ee704ccc4))
* **release:** preserve feature minor bumps before 1.0 ([0fb8038](https://github.com/lambdasistemi/tmux-ws/commit/0fb80386e24c744abeb3d95c7cb49cc5e6333735))
