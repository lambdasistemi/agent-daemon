# Feature Specification: Dual-Mode Sessions

**Feature Branch**: `003-dual-mode-sessions`
**Created**: 2026-03-29
**Status**: Draft
**Input**: User description: "feat: dual-mode sessions (TUI + stream-json) with prompt API"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mode Switching (Priority: P1)

As a daemon operator, I want to switch an existing session between terminal mode (TUI) and structured mode (stream-json) so that different clients can interact with the same session in the way that suits them — terminal clients see a TUI, non-terminal clients (e.g., Telegram) get JSON.

**Why this priority**: Without mode switching, sessions are locked to one interaction style at creation time. This is the foundational capability that all other stories depend on — structured mode is useless if you can't activate it.

**Independent Test**: Create a session (defaults to terminal mode), switch it to structured mode, verify the session state reflects the new mode and the old process is stopped. Switch back to terminal mode, verify it resumes correctly.

**Acceptance Scenarios**:

1. **Given** a running session in terminal mode, **When** the operator requests a switch to structured mode, **Then** the terminal process is stopped, a new process starts with stream-json flags, and the session state shows "structured" mode.
2. **Given** a running session in structured mode, **When** the operator requests a switch to terminal mode, **Then** the structured process is stopped, a new process starts in TUI mode, and the session state shows "terminal" mode.
3. **Given** a session that has had conversation history, **When** mode is switched, **Then** the new process resumes the existing conversation (history is preserved across the switch).
4. **Given** a session already in the requested mode, **When** a switch to the same mode is requested, **Then** the system reports that the session is already in that mode (no-op).

---

### User Story 2 - Prompt API (Priority: P2)

As a non-terminal client (e.g., Telegram bot), I want to send text prompts to a session in structured mode and receive streamed JSON responses so that I can build conversational interfaces without terminal emulation.

**Why this priority**: This is the primary consumer of structured mode — without a prompt endpoint, structured mode has no external interface.

**Independent Test**: Switch a session to structured mode, send a prompt, receive a stream of JSON events including the assistant's response. Verify the response is well-formed and complete.

**Acceptance Scenarios**:

1. **Given** a session in structured mode, **When** a text prompt is sent, **Then** the system streams JSON response events back to the caller.
2. **Given** a session in terminal mode, **When** a prompt is sent to the prompt endpoint, **Then** the system rejects the request with an error indicating the session must be in structured mode.
3. **Given** a session in structured mode with an active prompt in progress, **When** another prompt is sent, **Then** the system rejects it (one prompt at a time).

---

### User Story 3 - Mode Visibility (Priority: P3)

As a dashboard user, I want to see which mode each session is running in so that I can understand what interaction channels are available for each session.

**Why this priority**: Operational visibility — without this, operators cannot tell which sessions support which interaction style.

**Independent Test**: List sessions, verify the mode field appears for each session. Create a session, switch modes, list again, verify the mode field updates.

**Acceptance Scenarios**:

1. **Given** multiple sessions in different modes, **When** the session list is retrieved, **Then** each session includes its current mode ("terminal" or "structured").
2. **Given** a session that has just switched modes, **When** the session list is retrieved, **Then** the mode field reflects the new mode immediately.

---

### Edge Cases

- What happens if the process crashes during a mode switch (between kill and respawn)?
- What happens if the session is in "creating" or "stopping" state when a mode switch is requested?
- What happens if the claude process in structured mode exits unexpectedly mid-prompt?
- How does the system handle very large JSON responses that exceed memory limits?
- What happens if the client disconnects mid-stream during a prompt response?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support two session modes: "terminal" (TUI, existing) and "structured" (stream-json).
- **FR-002**: System MUST allow switching between modes for an active session without destroying the tmux session or worktree.
- **FR-003**: System MUST preserve conversation history across mode switches by resuming the session.
- **FR-004**: System MUST enforce mutual exclusion — only one process per session at a time.
- **FR-005**: System MUST provide a prompt endpoint that accepts text and streams JSON responses (structured mode only).
- **FR-006**: System MUST run the structured-mode process with permissions bypassed (no interactive permission prompts).
- **FR-007**: System MUST reject prompt requests sent to sessions in terminal mode.
- **FR-008**: System MUST expose the current mode in session state for all listing and detail endpoints.
- **FR-009**: System MUST reject mode switch requests when the session is in a transitional state (creating, stopping).
- **FR-010**: System MUST handle process crashes during mode switch gracefully, leaving the session in a recoverable "failed" state rather than an inconsistent state.

### Key Entities

- **Session**: Extended with a mode field ("terminal" or "structured") and a reference to the currently running process.
- **Mode**: An enumeration of how the claude process runs — terminal (TUI with PTY I/O) or structured (JSON stdin/stdout).
- **Prompt**: A text message sent by a non-terminal client, paired with a streamed JSON response.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sessions can switch between terminal and structured mode without losing conversation history.
- **SC-002**: A prompt sent to a structured-mode session returns a complete assistant response as streamed JSON.
- **SC-003**: Mode field is present and accurate in all session listing responses.
- **SC-004**: All existing terminal-mode functionality continues working unchanged.

## Assumptions

- The claude CLI supports `--output-format stream-json --input-format stream-json --resume {session_id}` flags as described in the issue.
- A CLI flag exists to bypass interactive permission prompts (e.g., `--dangerously-skip-permissions` or equivalent), allowing structured mode to run unattended.
- The `--resume` flag reliably restores conversation history when the process is restarted in the same worktree.
- The stream-json output format produces newline-delimited JSON events that can be parsed incrementally.
- Response streaming will use Server-Sent Events (SSE) over HTTP. WebSocket streaming is a future consideration.
