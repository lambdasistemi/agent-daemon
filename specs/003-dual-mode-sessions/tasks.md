# Tasks: Dual-Mode Sessions

**Input**: Design documents from `/specs/003-dual-mode-sessions/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Integration tests included — this feature introduces new I/O paths that need verification.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add types and extend session model

- [x] T001 Add `SessionMode` type (`Terminal | Structured`) with `ToJSON`/`FromJSON` instances to `src/AgentDaemon/Types.hs`
- [x] T002 Add `PromptRequest` type with `prompt :: Text` field and `FromJSON` instance to `src/AgentDaemon/Types.hs`
- [x] T003 Add `ModeRequest` type with `mode :: SessionMode` field and `FromJSON` instance to `src/AgentDaemon/Types.hs`
- [x] T004 Extend `Session` in `src/AgentDaemon/Types.hs` with `sessionMode :: SessionMode` (default `Terminal`) and `sessionClaudeId :: Maybe Text`
- [x] T005 Update all `Session` construction sites (Api.hs, Recovery.hs) to include `sessionMode = Terminal` and `sessionClaudeId = Nothing`

---

## Phase 2: Foundational — Structured Process Module

**Purpose**: Core structured process lifecycle — MUST be complete before mode switching or prompt API

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Create `src/AgentDaemon/Structured.hs` with `StructuredProcess` record type: process handle, stdin handle, stdout handle, `claudeSessionId :: TVar (Maybe Text)`, `promptInProgress :: TVar Bool`
- [x] T007 Implement `spawnStructured :: FilePath -> Maybe Text -> IO StructuredProcess` in `src/AgentDaemon/Structured.hs` — spawn `claude -p --output-format stream-json --input-format stream-json --verbose --dangerously-skip-permissions` with optional `--resume <id>`, capture stdin/stdout handles
- [x] T008 Implement `readInitEvent :: StructuredProcess -> IO ()` in `src/AgentDaemon/Structured.hs` — read the first NDJSON line (`system/init`), extract `session_id`, store in `claudeSessionId` TVar
- [x] T009 Implement `sendPrompt :: StructuredProcess -> Text -> IO ()` in `src/AgentDaemon/Structured.hs` — encode user message as JSON, write to stdin with newline
- [x] T010 Implement `readEvents :: StructuredProcess -> (Value -> IO Bool) -> IO ()` in `src/AgentDaemon/Structured.hs` — read NDJSON lines from stdout, call callback per event, stop when callback returns False (on `result` event)
- [x] T011 Implement `killStructured :: StructuredProcess -> IO ()` in `src/AgentDaemon/Structured.hs` — terminate the process, clean up handles
- [x] T012 Expose `AgentDaemon.Structured` in `agent-daemon.cabal` exposed-modules list

**Checkpoint**: Structured process can be spawned, receive prompts, stream events, and be killed programmatically

---

## Phase 3: User Story 1 + 3 — Mode Switching & Visibility (Priority: P1, P3)

**Goal**: Sessions can switch between terminal and structured mode; mode is visible in API responses

**Independent Test**: Create session, switch to structured, verify mode in GET /sessions, switch back to terminal

### Implementation for User Stories 1 & 3

- [x] T013 [US1] [US3] Update `ToJSON Session` in `src/AgentDaemon/Types.hs` to include `mode` and `claudeId` fields in JSON output
- [x] T014 [US1] Add mode switch route `POST /sessions/:id/mode` accepting `ModeRequest` body to `src/AgentDaemon/Api/Types.hs`
- [x] T015 [US1] Implement `handleSwitchMode` in `src/AgentDaemon/Api.hs` — validate session is Running, reject if already in requested mode, reject if transitional state
- [x] T016 [US1] Implement terminal→structured switch in `handleSwitchMode`: send Ctrl-C to tmux to kill claude TUI, spawn structured process with `--resume`, update session mode and claude ID in TVar
- [x] T017 [US1] Implement structured→terminal switch in `handleSwitchMode`: kill structured process, respawn claude in tmux with `sendKeys` using `--resume`, update session mode in TVar
- [x] T018 [US1] Handle mode switch failures: if respawn fails after killing the old process, set session state to `Failed` with reason

**Checkpoint**: Mode switching works end-to-end. GET /sessions shows mode field.

---

## Phase 4: User Story 2 — Prompt API (Priority: P2)

**Goal**: Non-terminal clients can send prompts and receive streamed JSON responses via SSE

**Independent Test**: Switch session to structured mode, POST prompt, receive SSE stream with assistant response

### Implementation for User Story 2

- [x] T019 [US2] Add prompt route `POST /sessions/:id/prompt` accepting `PromptRequest` body to `src/AgentDaemon/Api/Types.hs`
- [x] T020 [US2] Implement `handlePrompt` in `src/AgentDaemon/Api.hs` — validate session is in Structured mode, check `promptInProgress` flag, reject if busy or wrong mode
- [x] T021 [US2] Implement SSE response streaming in `handlePrompt`: set `promptInProgress = True`, write prompt to stdin via `sendPrompt`, read events via `readEvents`, forward each as SSE `data:` line, set `promptInProgress = False` on `result` event
- [x] T022 [US2] Handle edge cases in `handlePrompt`: process exit mid-prompt (set session to Failed), client disconnect (clean up promptInProgress flag)

**Checkpoint**: Full prompt→response cycle works via SSE. Concurrent prompts are rejected.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Recovery, tests, edge cases

- [x] T023 Update `recoverSessions` in `src/AgentDaemon/Recovery.hs` to set recovered sessions to `Terminal` mode (existing behavior preserved)
- [x] T024 Add integration tests for mode switching in `test/AgentDaemon/StructuredSpec.hs` — spawn structured process, send prompt, verify events, kill
- [x] T025 Add integration tests for prompt rejection in wrong mode in `test/AgentDaemon/StructuredSpec.hs`
- [x] T026 Add `AgentDaemon.StructuredSpec` to `agent-daemon.cabal` test-suite other-modules
- [x] T027 Format all modified files with fourmolu, build with `-Wall -Werror`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (needs `SessionMode` and extended `Session`)
- **User Stories 1+3 (Phase 3)**: Depends on Phase 2 (`spawnStructured`/`killStructured`)
- **User Story 2 (Phase 4)**: Depends on Phase 2 (`sendPrompt`/`readEvents`) — can run in parallel with Phase 3
- **Polish (Phase 5)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational. Mode switching is independent of prompt API.
- **User Story 2 (P2)**: Depends on Foundational. Can proceed in parallel with US1 (different files: prompt handler vs mode handler).
- **User Story 3 (P3)**: Bundled with US1 — the mode field in `ToJSON Session` is needed for both.

### Parallel Opportunities

- T001, T002, T003 can run in parallel (independent type additions to Types.hs — but same file, so sequential in practice)
- Phase 3 and Phase 4 can proceed in parallel after Phase 2 (mode switch handler vs prompt handler)
- T024 and T025 can run in parallel (independent test files)

---

## Implementation Strategy

### MVP First (Mode Switching Only)

1. Complete Phase 1: Setup (T001–T005)
2. Complete Phase 2: Foundational (T006–T012)
3. Complete Phase 3: Mode Switching + Visibility (T013–T018)
4. **STOP and VALIDATE**: Mode switching works, mode visible in API
5. This covers the core capability — prompt API can follow

### Incremental Delivery

1. Setup + Foundational → Structured process module exists
2. Add US1+US3 (Mode Switch) → Validate → Sessions can switch modes
3. Add US2 (Prompt API) → Validate → Full prompt→response cycle works
4. Polish → Recovery, tests, edge cases

---

## Notes

- The structured process lives outside tmux — it's a direct child of the daemon, managed via `typed-process`
- The tmux session persists across mode switches — it's just the claude process inside that changes
- For terminal→structured: we send Ctrl-C to tmux to kill the TUI, then spawn the structured process directly
- For structured→terminal: we kill the structured process, then `sendKeys` in tmux to launch claude TUI again
- `--resume` requires the claude session UUID, captured from the `system/init` event on first structured spawn
- SSE response format: `data: {json}\n\n` per event, `Content-Type: text/event-stream`
