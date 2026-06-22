# Data Model: Dual-Mode Sessions

## New Entities

### SessionMode

Enumeration of how the claude process runs inside a tmux session.

- **Terminal**: TUI mode (existing). Claude runs interactively, terminal I/O bridged via PTY/WebSocket.
- **Structured**: Stream-JSON mode. Claude runs with `--output-format stream-json --input-format stream-json`. Daemon writes prompts to stdin, reads NDJSON from stdout.

### StructuredProcess

Handle to a running claude process in structured mode. Held in memory (not persisted).

- **processHandle**: The typed-process handle for the running claude CLI
- **processStdin**: Write end for sending JSON messages
- **processStdout**: Read end for receiving NDJSON events
- **claudeSessionId**: The UUID from the `system/init` event, used for `--resume`
- **promptInProgress**: Whether a prompt is currently being processed (mutual exclusion)

### PromptRequest

A text prompt sent by a non-terminal client.

- **prompt**: The text content to send to claude

### StreamEvent

A single NDJSON line from the claude process stdout, forwarded to the client as an SSE event.

- **eventType**: `system`, `assistant`, `result`, `stream_event`
- **payload**: The raw JSON object

## Modified Entities

### Session (extended)

Add fields:
- **sessionMode**: `Terminal | Structured` — current mode
- **sessionClaudeId**: Optional UUID — the claude conversation session ID, captured from `system/init` on first structured run. Used for `--resume`.
- **sessionProcess**: Optional handle to the structured process (only present in Structured mode)

### SessionState (unchanged)

No changes needed. The existing states (Creating, Running, Attached, Stopping, Failed) apply to both modes.

## State Transitions

```
[Create Session] → Creating → Running (Terminal mode, default)
                                 │
                          [Switch to Structured]
                                 │
                                 ▼
                          Running (Structured mode)
                                 │
                          [Switch to Terminal]
                                 │
                                 ▼
                          Running (Terminal mode)
```

Mode switches:
1. Kill current claude process (in tmux for terminal, process handle for structured)
2. Respawn with appropriate flags + `--resume <claudeSessionId>`
3. Update sessionMode

## Validation Rules

- Mode switch only allowed when session is in Running state
- Prompt endpoint only accepts requests when session is in Structured mode
- Only one prompt at a time per session (promptInProgress flag)
- claudeSessionId must be captured before any `--resume` can work
