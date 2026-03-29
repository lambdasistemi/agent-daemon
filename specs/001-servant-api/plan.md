# Implementation Plan: Migrate API to Servant

**Branch**: `001-servant-api` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)

## Summary

Replace manual WAI pattern matching in `AgentDaemon.Api` with a servant type-level API. All 6 REST endpoints keep identical JSON shapes. WebSocket and CORS stay as WAI middleware.

## Technical Context

**Language/Version**: Haskell GHC2021 (GHC 9.x via nix)
**Primary Dependencies**: servant, servant-server (new); wai, warp, wai-websockets, aeson (existing)
**Storage**: N/A (in-memory TVar + filesystem)
**Testing**: Manual + existing e2e-tests (hspec + websockets)
**Target Platform**: Linux server
**Project Type**: Web service (daemon)
**Performance Goals**: N/A (low-traffic local daemon)
**Constraints**: Identical API surface — no behavioral changes
**Scale/Scope**: 6 REST endpoints, 1 WebSocket endpoint, ~460 LOC in Api.hs

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| I. Type-Safe API | PASS | This is the goal of the migration |
| II. Haskell-First | PASS | Using servant (standard Haskell library) |
| III. Separation of Concerns | PASS | Domain logic stays in existing modules; Api.hs becomes servant wiring |
| IV. WebSocket as First-Class | PASS | Stays in wai-websockets middleware, unchanged |
| V. CORS Stays as Middleware | PASS | CORS wraps the full servant application |

## Project Structure

### Documentation (this feature)

```text
specs/001-servant-api/
├── plan.md
├── research.md
├── data-model.md
└── tasks.md
```

### Source Code (repository root)

```text
src/
├── AgentDaemon.hs           # re-exports (unchanged)
├── AgentDaemon/
│   ├── Api.hs               # REWRITTEN: servant API type + server
│   ├── Api/
│   │   └── Types.hs         # NEW: API type definition
│   ├── Branch.hs            # unchanged
│   ├── Recovery.hs          # unchanged
│   ├── Server.hs            # MODIFIED: use servant app instead of raw WAI
│   ├── Terminal.hs           # unchanged
│   ├── Tmux.hs              # unchanged
│   ├── Types.hs             # unchanged
│   └── Worktree.hs          # unchanged
```

**Structure Decision**: Minimal change — extract the API type into `Api.Types`, rewrite `Api.hs` as servant handlers, adjust `Server.hs` to compose servant app with websockets middleware.
