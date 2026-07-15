# Touch usage

The daemon-served SPA is a touch-first control surface for a tablet and small-screen
browser. Open the daemon URL itself so the UI, REST API, and
terminal WebSocket share one origin:

```text
http://127.0.0.1:8080/
```

For another device, use the HTTPS origin configured in
[Tailscale HTTPS](tailscale.md). The public GitHub Pages copy is for inspection,
not the supported control origin.

## Select a session and window

The header always shows the selected **Session** and active **Window**. Selecting
a session attaches its terminal; selecting a window switches the current tmux
window. The bottom dock provides **Refresh**, **Terminal**, **Paste**, and
**Settings**.

- **Terminal** provides compatibility shortcuts, copy/selection controls, and
  a return to live output.
- **Paste** sends or saves reusable text, optionally followed by Enter.
- **Settings** controls theme and terminal size and contains guarded destructive
  actions.

## Modifier and arrow command deck

While a terminal is attached, the modifier and arrow command deck appears
below it. It supplements the tablet's native keyboard; it is not a full
on-screen alphanumeric keyboard.

The controls are **Esc**, **Tab**, **Ctrl**, **Alt**, **Shift**, **Tmux**,
**Left**, **Up**, **Down**, **Right**, and **Enter**. Esc, Tab, Enter, and the
arrows send keys immediately. Ctrl, Alt, Shift, and Tmux are one-shot latches:
tap one, then tap a deck key or type the next native-keyboard key. The latch is
consumed once. Tap an armed latch again to cancel it without sending input.

Examples:

- **Ctrl**, then `c`, sends Ctrl-C once.
- **Shift**, then **Tab**, sends a back-tab.
- **Alt**, then a letter, sends Alt/Meta-prefixed input.
- **Tmux**, then an arrow or native key, sends the prefix followed by that key.

The **Tmux** latch sends a literal one-shot **Ctrl-B** prefix. It is fixed, not
derived from a remapped tmux prefix. The older Terminal-menu **Ctrl-b** and
**Ctrl-b :** shortcuts remain available.

Arrow encoding follows xterm's application-cursor mode for programs such as
vim, less, and tmux copy mode. Holding an arrow repeats it with a bound; repeat
stops on release, cancel, pointer leave, terminal blur, or detach. Deck use
preserves terminal focus and the tablet's native keyboard.

## Close the current pane or window

Open **Settings**, then choose **Close this pane** or **Close this window**.
Both follow the same guarded sequence:

1. The SPA asks the server to preview exactly what the action would close.
2. Review the consequence in the confirmation sheet. It distinguishes a pane,
   the last pane and its window, a whole window, and the final context that
   would end the session.
3. Confirm with the server-issued one-use token, or cancel without changing
   tmux.

Immediately before closing, the server checks that the tmux topology still
matches the preview. If it changed, the action is rejected and a new preview is
required. After a successful close that leaves the session alive, the SPA
refreshes the session/window registry and reconnects the terminal to the
surviving context. Closing the final pane/window ends that session and returns
the SPA to the remaining session list.

Ending an entire session is separate and requires typing its exact session ID
before the destructive button is enabled.

## Refresh, restart, and reconnect

The in-app **Refresh** action asks the daemon for the current sessions and
windows. It does not replace the running browser document or download upgraded
SPA assets.

After upgrading tmux-ws:

1. Restart the daemon service.
2. Wait until the daemon is healthy.
3. Use the browser's hard refresh to fetch the new SPA. If a tablet browser has
   no hard-refresh command, fully close and reopen the tab.
4. Select the recovered session and window to reconnect the terminal.

The daemon sends `Cache-Control: no-store` for UI responses and imports
existing tmux sessions on startup. A daemon or browser restart therefore does
not itself end the underlying tmux processes.
