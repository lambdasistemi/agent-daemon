# Implementation Plan: Dual-Mode Sessions

**Branch**: `003-dual-mode-sessions` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-dual-mode-sessions/spec.md`

## Summary

Add a second session mode ("structured") where the claude process runs with `--output-format stream-json --input-format stream-json` instead of as a TUI. The daemon manages the process via `typed-process`, exposes a prompt endpoint that accepts text and streams back JSON events via SSE, and supports switching between modes with `--resume` to preserve conversation history. See [research.md](research.md) for the stream-json protocol details.

## Technical Context

**Language/Version**: Haskell, GHC 9.8.4 via haskell.nix
**Primary Dependencies**: typed-process (existing), servant/servant-server, aeson, warp, websockets, stm, posix-pty
**Storage**: N/A (in-memory TVar state)
**Testing**: hspec (existing suite + new tests)
**Target Platform**: x86_64-linux, aarch64-darwin
**Project Type**: daemon (WebSocket + REST server)
**Constraints**: Must preserve all existing terminal-mode functionality unchanged
**Scale/Scope**: ~500 lines new code, 3 modules modified, 2 new modules

## Constitution Check

*Constitution is not yet defined for this project. No gates to evaluate.*

## Project Structure

### Documentation (this feature)

```text
specs/003-dual-mode-sessions/
├── spec.md
├── plan.md              # This file
├── research.md          # Stream-JSON protocol research
├── data-model.md        # SessionMode, StructuredProcess types
└── tasks.md             # Created by /speckit.tasks
```

### Source Code (repository root)

```text
src/AgentDaemon/
├── Types.hs             # MODIFIED — add SessionMode, extend Session
├── Structured.hs        # NEW — structured process management (spawn, prompt, kill)
├── Api.hs               # MODIFIED — add mode switch + prompt endpoints
├── Api/Types.hs         # MODIFIED — add new servant routes
├── Tmux.hs              # MODIFIED — extract claude launch for reuse
├── Server.hs            # MINOR — no changes expected (SSE is plain HTTP)
└── ...                  # unchanged
```

**Structure Decision**: One new module `AgentDaemon.Structured` handles the stream-json process lifecycle. Api.hs gets new handlers. Types.hs gets the mode enum and extended Session type.

## Design

### Phase 1: Types & Mode (User Story 1 + 3 — P1, P3)

1. **Add `SessionMode`** to `AgentDaemon.Types`:
   - `data SessionMode = Terminal | Structured`
   - JSON instances for API responses
2. **Extend `Session`** with:
   - `sessionMode :: SessionMode` (default `Terminal`)
   - `sessionClaudeId :: Maybe Text` (claude conversation UUID)
3. **Add mode to API responses** — `GET /sessions` now includes `mode` field
4. **Add mode switch endpoint** to servant API:
   - `POST /sessions/:id/mode` with body `{"mode": "structured"}` or `{"mode": "terminal"}`
5. **Implement mode switch handler** in `Api.hs`:
   - Validate session is Running
   - Kill current claude process
   - Respawn with new flags + `--resume`
   - Update session mode in TVar

### Phase 2: Structured Process (User Story 2 — P2)

1. **Create `AgentDaemon.Structured`**:
   - `spawnStructured :: FilePath -> Maybe Text -> IO StructuredProcess` — spawn claude with stream-json flags, optionally `--resume`
   - `sendPrompt :: StructuredProcess -> Text -> IO ()` — write user message JSON to stdin
   - `readEvents :: StructuredProcess -> (StreamEvent -> IO ()) -> IO ()` — read NDJSON lines, invoke callback per event
   - `killStructured :: StructuredProcess -> IO ()` — terminate the process
   - Parse `system/init` event to capture `claudeSessionId`
2. **Add prompt endpoint** to servant API:
   - `POST /sessions/:id/prompt` with body `{"prompt": "text"}`
   - Response: SSE stream (chunked transfer encoding with `text/event-stream`)
3. **Implement prompt handler**:
   - Validate session is in Structured mode
   - Check promptInProgress flag (reject if busy)
   - Write prompt to process stdin
   - Stream NDJSON events back as SSE until `result` event
   - Clear promptInProgress flag

### Phase 3: Integration & Polish

1. **Mode switch for terminal→structured**: Kill claude in tmux (send Ctrl-C + wait), spawn structured process
2. **Mode switch for structured→terminal**: Kill structured process, respawn claude in tmux with `sendKeys`
3. **Recovery**: On daemon restart, recovered sessions default to Terminal mode (existing behavior)
4. **Tests**: Integration tests for mode switching, prompt flow, error cases
5. **Edge cases**: Handle process crash during mode switch, reject switch during transitional states

## Complexity Tracking

No constitution violations to justify.
