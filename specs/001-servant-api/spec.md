# Feature Specification: Migrate API to Servant

**Feature Branch**: `001-servant-api`
**Created**: 2026-03-29
**Status**: Draft
**Input**: Migrate the WAI application from manual pattern matching to a servant type-level API

## User Scenarios & Testing

### User Story 1 - Existing REST endpoints continue to work (Priority: P1)

A dashboard client (kanbanned) that currently calls the agent-daemon REST API must continue working with identical request/response shapes after the migration.

**Why this priority**: This is a refactor — zero behavioral change is the primary success criterion.

**Independent Test**: Send the same HTTP requests as before and verify identical JSON responses.

**Acceptance Scenarios**:

1. **Given** a running daemon, **When** POST /sessions with a valid launch request, **Then** a session is created and the response JSON has the same shape as before.
2. **Given** active sessions, **When** GET /sessions, **Then** the response is a JSON array of sessions with identical field names.
3. **Given** an active session, **When** DELETE /sessions/:sid, **Then** the session is stopped and cleaned up, response matches current shape.
4. **Given** worktrees on disk, **When** GET /worktrees, **Then** the response lists them with identical JSON structure.
5. **Given** branches on disk, **When** GET /branches, **Then** the response lists them with identical JSON structure.
6. **Given** a branch, **When** DELETE /branches/:repo/:branch, **Then** the branch is deleted, response matches current shape.

---

### User Story 2 - WebSocket terminal remains functional (Priority: P1)

A browser client connecting via WebSocket to /sessions/:sid/terminal must still be able to attach to a tmux session and relay terminal I/O.

**Why this priority**: Terminal access is core functionality and must not break during migration.

**Independent Test**: Connect via websocat to the WebSocket endpoint, verify bidirectional terminal I/O.

**Acceptance Scenarios**:

1. **Given** a running session, **When** a WebSocket client connects to /sessions/:sid/terminal, **Then** terminal I/O is relayed bidirectionally.
2. **Given** an invalid session ID, **When** a WebSocket client connects, **Then** the connection is rejected.

---

### User Story 3 - Static file fallback for SPA (Priority: P2)

Unmatched routes serve the index.html file so the single-page application can handle client-side routing.

**Why this priority**: Required for the kanbanned dashboard to load on any URL path.

**Independent Test**: Request a non-API path and verify index.html is served.

**Acceptance Scenarios**:

1. **Given** a running daemon, **When** GET / or any non-API path, **Then** static/index.html is served.

---

### Edge Cases

- What happens when the request body for POST /sessions is malformed? (400 with JSON error)
- What happens when DELETE /sessions/:sid references a non-existent session? (404 with JSON error)
- What happens when OPTIONS is sent to any endpoint? (CORS preflight response with 204)

## Requirements

### Functional Requirements

- **FR-001**: System MUST expose the same 6 REST endpoints with identical paths, methods, and JSON shapes.
- **FR-002**: System MUST route requests using a type-level API definition rather than manual pattern matching.
- **FR-003**: System MUST derive JSON encoding/decoding from the same Aeson instances currently in use.
- **FR-004**: System MUST handle CORS as WAI middleware wrapping the servant application.
- **FR-005**: System MUST keep the WebSocket endpoint functional via wai-websockets middleware (outside servant routing).
- **FR-006**: System MUST serve static files (index.html) as a fallback for unmatched routes.
- **FR-007**: System MUST preserve the existing error response format (JSON object with "error" field).

### Key Entities

- **API type**: A type-level description of all REST endpoints, capturing paths, methods, request/response bodies, and path captures.
- **Server handlers**: One handler function per endpoint, containing the existing business logic.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All existing REST endpoints return identical JSON for the same inputs.
- **SC-002**: The project builds and passes CI (build + format-check + hlint).
- **SC-003**: WebSocket terminal connections work identically to the current implementation.
- **SC-004**: No manual path/method pattern matching remains in the API module.

## Assumptions

- The servant and servant-server packages are available in the project's package set.
- The WebSocket endpoint will remain outside servant routing (handled by wai-websockets middleware as before).
- CORS middleware wraps the entire WAI application including servant.
- The static file fallback can use a Raw endpoint within the servant API type.
