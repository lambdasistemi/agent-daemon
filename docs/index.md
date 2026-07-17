# tmux-ws

`tmux-ws` is a local daemon that serves both the browser SPA and the
REST/WebSocket API used to manage tmux sessions. The supported browser-control
entry point is the SPA served by the daemon itself.

## What it does

- Serves the tmux-ws SPA from `--static-dir`
- Lists and recovers running tmux sessions after daemon restart
- Provides browser-based terminal access via xterm.js and WebSockets
- Switches tmux windows from touch-first browsers
- Manages the session lifecycle: attach, detach, stop, refresh

## Quick start

The supported installation path is the
[latest GitHub release](https://github.com/lambdasistemi/tmux-ws/releases/latest).
You do not need Nix or a source checkout to run `tmux-ws`.

### Linux AppImage

The AppImage is the quickest option on x86_64 Linux. Its stable filename always
points to the latest release:

```bash
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/tmux-ws.AppImage
curl -fLO https://github.com/lambdasistemi/tmux-ws/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x tmux-ws.AppImage
./tmux-ws.AppImage --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

Open `http://127.0.0.1:8080/` on that computer. To use a tablet, keep the
daemon bound to localhost and follow the [Tailscale HTTPS guide](tailscale.md)
to expose the same daemon origin safely.

### Debian or Ubuntu

Download the `.deb` file from the
[latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest), then
run these commands from your Downloads directory:

```bash
sudo apt install ./tmux-ws-*-x86_64-linux.deb
tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

### Fedora, RHEL, or another RPM-based distribution

Download the `.rpm` file from the
[latest release](https://github.com/lambdasistemi/tmux-ws/releases/latest), then
run:

```bash
sudo dnf install ./tmux-ws-*-x86_64-linux.rpm
tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

### macOS on Apple Silicon

```bash
brew install lambdasistemi/tap/tmux-ws
tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

`tmux`, `git`, and `ssh` must be available in `PATH`. See
[Release and migration](release.md) for package details and upgrades.

## Build from source (developers only)

This is for contributors working on `tmux-ws`, not for normal installation:

```bash
nix develop
just build

tmux-ws --host 127.0.0.1 --port 8080 --base-dir "$HOME"
```

## Touch-first operation

The daemon-served SPA is designed to be usable on a tablet with no keyboard or
mouse. Open it and use the two selectors in the header to see and change the
current context:

- **Session** shows the selected tmux session by name.
- **Window** shows the active window by name (or index when it has no name).

The persistent action dock at the bottom contains four touch targets:

- **Refresh** reloads the session registry and, when attached, the window
  registry from the daemon.
- **Terminal** provides touch controls for copy, selection mode, `Esc`,
  `Ctrl-b`, the tmux command prompt, and returning to live output.
- **Paste** sends or saves reusable snippets, with optional Enter, so text and
  commands do not require an on-screen keyboard.
- **Settings** changes theme, terminal font size, and daemon address, and holds
  the guarded close-current actions.

Swiping the terminal scrolls the current pane. The **Terminal** menu's **Live**
action returns from tmux copy mode to live output.

### Terminal command deck

While a terminal is attached, a compact **command deck** sits below the terminal
output. It is a touch surface for the control keys that tmux and interactive
TUIs need — not a replacement alphanumeric keyboard. Type text with the tablet's
own keyboard; use the deck for the keys that keyboard cannot send. The deck is
present only while a session is attached.

It has eleven controls: **Esc**, **Tab**, **Ctrl**, **Alt**, **Shift**,
**Tmux**, **Left**, **Up**, **Down**, **Right**, and **Enter**. `Esc`, `Tab`,
and `Enter` are sent immediately; the arrows move the cursor; `Ctrl`, `Alt`,
`Shift`, and `Tmux` are one-shot latches.

**One-shot latches.** Tapping `Ctrl`, `Alt`, `Shift`, or `Tmux` arms a single
modifier. The armed state is visible and reported truthfully through
`aria-pressed`. The latch applies to the very next key and then disarms itself;
tapping an armed latch again cancels it, sending nothing and leaving the next
key unmodified. A latch also composes with the **next key typed on the tablet's
native keyboard** — arm `Ctrl` and press `c` to send Ctrl-C once, after which a
plain `c` remains plain. Each armed latch is consumed exactly once. Typical
combinations: `Ctrl`+`c` (Ctrl-C), `Shift`+`Tab` (back-tab), `Alt`+letter
(Alt/Meta-prefixed input), and `Tmux`+arrow.

**Tmux prefix.** `Tmux` is a literal tmux **Ctrl-B** prefix. It is one-shot and
composes with the next accessory, arrow, or native key, so any tmux binding is
reachable by touch. It is a fixed prefix, not a remappable one; the Terminal
menu's `Ctrl-b` and `Ctrl-b :` shortcuts remain for compatibility.

**Arrows and cursor mode.** The arrow controls honor xterm's
application-cursor-keys mode, so full-screen programs receive the arrow encoding
they expect. Press and hold an arrow to repeat it: the repeat is bounded and
stops on release, on pointer cancel or leave, and when the terminal loses focus
or detaches, so a held arrow never runs away.

**Focus.** Operating the deck preserves terminal focus and does not dismiss the
tablet keyboard, so you can move freely between typing text and tapping deck
keys. With 44×44 CSS-pixel targets and dark/light states, the deck makes tmux
and TUIs fully operable on a tablet with no hardware keyboard.

### Close the current pane or window

Open **Settings** and tap **Close this pane** or **Close this window**. This is
a guarded two-step operation:

1. The SPA asks the server to preview the consequence for the current tmux
   context. It does not choose a pane or window itself.
2. A confirmation sheet explains the server's preview. It can report that only
   the pane will be removed, the last pane and its window will be removed, a
   window and all its panes will be removed, or the whole session will end.
3. Confirming sends the server-issued, one-use confirmation back to the server.
   Canceling makes no change.

The confirmation is bound to the selected session and action. Immediately
before closing, tmux checks that the previewed topology is still current. If a
pane or window changed in the meantime, the server rejects the stale action and
the SPA refreshes the surviving state; request a new preview before trying
again.

After a close that leaves the session alive, the SPA reloads its session/window
registry and reconnects the terminal to the surviving context. Closing the
final pane in the final window, or closing the final window, ends that tmux
session; the SPA detaches and reloads the remaining session list.

Ending an entire session through the session menu is separate: it requires
typing the displayed session id exactly before **End session** is enabled.

### Refresh is not a document reload

The dock's **Refresh** action updates the session/window registry without
replacing the running SPA document. Use the browser's reload control when you
need to fetch the SPA itself, such as after upgrading the daemon. Static UI
responses from the daemon use `Cache-Control: no-store` (with compatible
no-cache headers), so Chrome is instructed not to keep serving an old UI after
a document reload.

## CLI options

| Flag | Default | Description |
|------|---------|-------------|
| `--host` | `*` (all interfaces) | Address to bind to |
| `--port` | `8080` | HTTP port |
| `--base-dir` | `/code` | Root directory for git worktrees |
| `--static-dir` | `static` | Directory for the SPA files served by the daemon |

## Prerequisites

The following must be available in `PATH`:

- **tmux** — session management
- **git** — worktree operations
- **ssh** — git authentication (agent forwarding or deploy keys)

The user running the daemon needs permission to inspect and control the tmux
sessions it exposes.

## Browser client

Open the daemon URL in your browser. On the same machine, use localhost:

```
http://127.0.0.1:8080/
```

For a tablet or another machine, expose the same daemon origin through a reverse
proxy such as Tailscale Serve and open that proxied URL directly:

```
https://<host>.<tailnet>.ts.net:<https-port>/
```

In both cases, the browser loads the SPA and calls the API from the same origin.

The GitHub Pages build at
[lambdasistemi.github.io/tmux-ws](https://lambdasistemi.github.io/tmux-ws/) is
a public static copy. It is useful for inspection, but browsers may block it
from controlling a localhost or Tailscale daemon because that crosses from a
public origin into a local/private network address space.
