# tmux-ws

[![CI](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdasistemi/tmux-ws/actions/workflows/ci.yml)

`tmux-ws` is a local daemon that serves the browser SPA and the
REST/WebSocket API from the same origin. Open the SPA from the daemon URL
itself to manage local tmux sessions from a browser.

## Install and quick start

Download published builds from the
[latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest).

### Linux AppImage

The stable AppImage name tracks the latest release:

```bash
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/tmux-ws.AppImage
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

Open the daemon URL in a browser on the same machine:

```
http://127.0.0.1:8080/
```

For another device, expose that same daemon origin through a reverse proxy such
as Tailscale Serve and open the proxied URL directly. In both modes, the URL
serves the SPA and API together.

### Native Linux packages

The [latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest)
also provides versioned native x86_64 DEB and RPM packages. Download the one
for your distribution, then install it with the matching package manager:

```bash
sudo apt install ./tmux-ws-*-x86_64-linux.deb

sudo dnf install ./tmux-ws-*-x86_64-linux.rpm
```

### macOS with Homebrew

```bash
brew install lambdasistemi/tap/tmux-ws
```

The formula is backed by the latest release's versioned
`tmux-ws-<version>-aarch64-darwin.tar.gz` artifact.

After installing a native package or the Homebrew formula, launch with:

```bash
tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

Then open `http://127.0.0.1:8080/` on the same machine, or expose that same
origin with Tailscale Serve for another device. The browser must open the
daemon origin so the SPA and API remain same-origin.

See the [full documentation](https://lambdasistemi.github.io/tmux-ws/docs/)
and the [NixOS deployment guide](https://lambdasistemi.github.io/tmux-ws/docs/deployment/)
for configuration and unattended operation.

## Build from source

With Nix installed:

```bash
nix develop
just build
```

Then launch the resulting `tmux-ws` executable with the native command shown
above.

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

## Terminal command deck

When a terminal is attached, a compact **command deck** appears below the
terminal. It is a touch surface for the keys tmux and interactive TUIs need,
not a full on-screen alphanumeric keyboard: type text with the tablet's own
keyboard and reach for the deck for the keys that keyboard lacks. The deck is
shown only while a session is attached.

The deck has eleven controls: **Esc**, **Tab**, **Ctrl**, **Alt**, **Shift**,
**Tmux**, **Left**, **Up**, **Down**, **Right**, and **Enter**. `Esc`, `Tab`,
and `Enter` are sent immediately, the arrows move the cursor, and `Ctrl`,
`Alt`, `Shift`, and `Tmux` are one-shot latches.

### One-shot latches

**Ctrl**, **Alt**, **Shift**, and **Tmux** arm a single modifier. A latch is
visibly armed (reported truthfully through `aria-pressed`), applies to the very
next key, and then disarms itself. Tap an armed latch again to cancel it; a
cancelled latch sends nothing and leaves the next key unmodified. A latch also
composes with the **next key you type on the tablet's own keyboard**: arm
**Ctrl** and press `c` to send Ctrl-C once, and the following plain `c` stays
plain. Each armed latch is consumed exactly once.

Examples: **Ctrl** then `c` sends Ctrl-C; **Shift** then **Tab** sends a
back-tab; **Alt** then a letter sends an Alt-prefixed (Meta) key; **Tmux** then
an arrow sends the tmux prefix followed by the arrow.

**Tmux** is a literal tmux **Ctrl-B** prefix. It composes with whatever comes
next — an accessory key, an arrow, or a native-keyboard key — so any tmux
binding is reachable by touch. It is a fixed prefix, not a remappable one. The
older **Ctrl-b** / **Ctrl-b :** shortcuts in the Terminal menu remain as
compatibility shortcuts.

### Arrows, cursor mode, and focus

The arrow controls follow xterm's application-cursor-keys mode, so full-screen
programs such as vim, less, and tmux copy mode receive the arrow encoding they
expect. Press and hold an arrow to repeat it; the repeat is bounded and stops as
soon as you lift, cancel, or move off the control, or when the terminal loses
focus or detaches, so a held arrow never runs away.

Operating the deck preserves terminal focus and does not dismiss the tablet's
native keyboard, so you can alternate between typing text and tapping deck keys.
The whole deck is touch-operable with 44×44 CSS-pixel targets and dark/light
states, which makes tmux and TUIs fully usable on a tablet without a hardware
keyboard.
