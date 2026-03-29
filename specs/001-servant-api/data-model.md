# Data Model: Migrate API to Servant

No new entities. All existing types in `AgentDaemon.Types` remain unchanged.

## API Type (new)

The servant API type maps the 6 REST endpoints:

| Endpoint | Servant Combinator |
|----------|-------------------|
| POST /sessions | `"sessions" :> ReqBody '[JSON] LaunchRequest :> Post '[JSON] Session` |
| GET /sessions | `"sessions" :> Get '[JSON] [Session]` |
| DELETE /sessions/:sid | `"sessions" :> Capture "sid" Text :> Delete '[JSON] Value` |
| GET /worktrees | `"worktrees" :> Get '[JSON] [WorktreeInfo]` |
| GET /branches | `"branches" :> Get '[JSON] [BranchInfo]` |
| DELETE /branches/:repo/:branch | `"branches" :> Capture "repo" Text :> Capture "branch" Text :> Delete '[JSON] Value` |

Plus a `Raw` fallback for SPA static file serving.

## Existing Types (unchanged)

- `LaunchRequest` — request body for POST /sessions
- `Session` — response for session endpoints
- `SessionId` — path capture (newtype over Text)
- `WorktreeInfo` — response for GET /worktrees
- `BranchInfo` — response for GET /branches
- `Repo` — nested in several types
- `SessionState`, `SyncStatus` — enums with custom JSON instances
