# Tasks: Migrate API to Servant

**Input**: Design documents from `/specs/001-servant-api/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

## Phase 1: Setup

**Purpose**: Add servant dependencies and create the API type module

- [x] T001 Add `servant`, `servant-server` to build-depends in `agent-daemon.cabal`
- [x] T002 Create `src/AgentDaemon/Api/Types.hs` with the servant API type definition covering all 6 REST endpoints plus Raw fallback
- [x] T003 Register `AgentDaemon.Api.Types` in `exposed-modules` in `agent-daemon.cabal`

**Checkpoint**: Project compiles with new dependencies and API type module

---

## Phase 2: User Story 1 - REST endpoints continue to work (Priority: P1)

**Goal**: Replace manual WAI pattern matching with servant handlers, keeping identical JSON responses.

**Independent Test**: `just CI` passes, `curl` commands from justfile produce identical responses.

### Implementation

- [x] T004 [US1] Rewrite `src/AgentDaemon/Api.hs` — replace `apiApp` WAI Application with a servant `Server` using handlers that call the existing business logic (handleLaunch, handleList, handleStop, handleListWorktrees, handleListBranches, handleDeleteBranch). Keep `cors` middleware, `claudePrompt`, `setSessionState`, `errorJson`, `jsonHeaders`, `parseWorktreeName`, `toWorktreeInfo`, `repoPath` as internal helpers.
- [x] T005 [US1] Update `src/AgentDaemon/Server.hs` — change `startServer` to compose the servant WAI application (via `serve`) with `WaiWS.websocketsOr` and `cors` middleware. The `wsApp` routing stays unchanged.
- [x] T006 [US1] Update `src/AgentDaemon.hs` re-exports if needed (add `AgentDaemon.Api.Types` if it exports anything publicly useful)
- [x] T007 [US1] Build and verify: `nix develop --quiet -c just CI`

**Checkpoint**: All REST endpoints work identically. No manual pattern matching on `(requestMethod, pathInfo)` remains.

---

## Phase 3: User Story 2 - WebSocket terminal remains functional (Priority: P1)

**Goal**: Verify WebSocket terminal is unaffected by the servant migration.

**Independent Test**: `just attach <sid>` connects and relays I/O.

### Implementation

- [x] T008 [US2] Verify `src/AgentDaemon/Server.hs` — confirm `wsApp` still intercepts WebSocket upgrades via `WaiWS.websocketsOr` before servant handles the request. No code change expected, just verification.

**Checkpoint**: WebSocket terminal works as before.

---

## Phase 4: User Story 3 - Static file fallback (Priority: P2)

**Goal**: SPA routing continues to serve index.html for unmatched routes.

**Independent Test**: `curl localhost:8080/` and `curl localhost:8080/any/path` both return index.html.

### Implementation

- [x] T009 [US3] Ensure the `Raw` endpoint at the end of the servant API type in `src/AgentDaemon/Api/Types.hs` serves `index.html` for all unmatched routes. The handler in `src/AgentDaemon/Api.hs` should replicate the current fallback behavior.

**Checkpoint**: SPA routing works.

---

## Phase 5: Polish

**Purpose**: Format, lint, final CI pass

- [x] T010 Run `nix develop --quiet -c just format` to format all modified files
- [x] T011 Run `nix develop --quiet -c just CI` — full pipeline must pass
- [x] T012 Remove any dead code from the migration (unused imports, old routing helpers)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (US1)**: Depends on Phase 1
- **Phase 3 (US2)**: Depends on Phase 2 (verification only)
- **Phase 4 (US3)**: Depends on Phase 2
- **Phase 5 (Polish)**: Depends on all above

### Within Phase 2

- T004 and T005 are sequential (T005 depends on T004's new API)
- T006 depends on T004
- T007 is the verification gate

## Implementation Strategy

### MVP (Phase 1 + Phase 2)

1. Add deps + API type (Phase 1)
2. Rewrite Api.hs + update Server.hs (Phase 2)
3. Verify all REST endpoints work
4. **STOP and VALIDATE**: `just CI` passes

### Incremental

5. Verify WebSocket (Phase 3) — likely no code change
6. Verify SPA fallback (Phase 4) — covered by Raw endpoint
7. Polish (Phase 5)
