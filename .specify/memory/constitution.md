# Agent Daemon Constitution

## Core Principles

### I. Type-Safe API
All HTTP endpoints are defined as servant type-level API descriptions. Routing, request parsing, and response encoding are derived from types — no manual pattern matching on paths or methods.

### II. Haskell-First
GHC2021, fourmolu formatting, hlint, -Wall -Werror. Build with nix + cabal. All dependencies pinned via flake.nix.

### III. Separation of Concerns
Domain logic (session management, worktree operations, branch operations) stays in pure modules. The API layer only wires handlers to servant endpoints.

### IV. WebSocket as First-Class
Terminal WebSocket connections are a core feature, not an afterthought. They must integrate cleanly with the API layer (servant-websockets or raw fallback).

### V. CORS Stays as Middleware
CORS is applied as WAI middleware wrapping the full servant application. No per-endpoint CORS handling.

## Quality Gates

- `just CI` must pass locally before pushing (build + format-check + hlint)
- All endpoints must have correct JSON encoding/decoding derived from types
- WebSocket terminal functionality must remain working after migration

## Governance

Constitution supersedes ad-hoc decisions. Amendments require documentation update.

**Version**: 1.0.0 | **Ratified**: 2026-03-29
