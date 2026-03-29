# Research: Migrate API to Servant

## R1: servant-server integration with wai-websockets

**Decision**: Keep WebSocket routing in `wai-websockets` middleware (outside servant), same as current architecture.

**Rationale**: servant-websockets exists but adds complexity. The current `WaiWS.websocketsOr` pattern in `Server.hs` already works well — it intercepts WebSocket upgrades before they reach the WAI app. Servant handles only REST endpoints.

**Alternatives considered**: `servant-websockets` — rejected because it adds a dependency for no behavioral gain in this refactor.

## R2: Static file fallback (SPA routing)

**Decision**: Use servant's `Raw` combinator at the end of the API type to serve `index.html` for all unmatched routes.

**Rationale**: `Raw` embeds a plain WAI `Application` inside the servant API. A custom handler that always serves `index.html` matches the current catch-all behavior exactly.

**Alternatives considered**: `serveDirectoryWebApp` — serves directory listings and specific files by path, but doesn't serve `index.html` for all unmatched routes (SPA requirement).

## R3: CORS middleware placement

**Decision**: Keep CORS as WAI middleware wrapping the servant application, identical to current code.

**Rationale**: servant-cors exists but the current `cors` middleware in `Api.hs` is simple (4 headers, wraps `mapResponseHeaders`). Moving to servant-cors would add a dependency for no gain.

**Alternatives considered**: `servant-cors` or `wai-cors` — unnecessary for this simple use case.

## R4: Error response format

**Decision**: Use `ServerError` with custom JSON body matching the existing `{"error": "..."}` format.

**Rationale**: servant's `throwError` produces `ServerError` values. We set `errBody` and `errHeaders` to match the current JSON error format exactly.

**Alternatives considered**: Custom error handler middleware — overkill for simple JSON errors.

## R5: Handler monad

**Decision**: Use `Handler` (servant's default, which is `ExceptT ServerError IO`). Pass `SessionManager`, `baseDir`, and `staticDir` via partial application (closure), not via `ReaderT`.

**Rationale**: The current code passes these as function arguments. Keeping that pattern (partial application) is the minimal change. No need for `ReaderT` or custom monad.

**Alternatives considered**: `ReaderT env Handler` with a custom `Env` type — adds complexity for no benefit in a small API.
