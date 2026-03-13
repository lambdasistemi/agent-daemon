# Agent Daemon — Design

## Overview

A Haskell WebSocket server that manages Claude Code agent sessions.
Runs on a single machine reachable via Tailscale, providing full
terminal access to tmux sessions through xterm.js in the browser.

## System Context

```mermaid
graph LR
    Browser["Browser<br/>(gh-dashboard)"]
    Daemon["agent-daemon<br/>(Haskell)"]
    Tmux["tmux sessions"]
    Git["git worktrees"]
    GH["GitHub API"]

    Browser -- "WebSocket<br/>terminal I/O" --> Daemon
    Browser -- "REST<br/>session mgmt" --> Daemon
    Daemon -- "PTY attach" --> Tmux
    Daemon -- "git worktree<br/>add/remove" --> Git
    Daemon -- "gh issue view" --> GH
```

## Session Lifecycle

```mermaid
sequenceDiagram
    participant D as Dashboard
    participant A as agent-daemon
    participant T as tmux
    participant C as Claude Code

    D->>A: POST /sessions {repo, issue}
    A->>A: git worktree add /code/<repo>-issue-<N>
    A->>T: tmux new-session -d -s <repo>-<N>
    A->>T: send-keys "claude 'Work on owner/repo#N...'"
    A-->>D: 201 {session_id, state: creating}

    D->>A: WS /sessions/<id>/terminal
    A->>T: PTY attach to tmux session
    T-->>A: PTY stream
    A-->>D: terminal I/O (bidirectional)

    Note over D,C: User disconnects (closes tab)
    Note over T,C: tmux + Claude keep running

    D->>A: WS /sessions/<id>/terminal
    A->>T: PTY attach (reconnect)
    A-->>D: terminal I/O (resumed)

    D->>A: DELETE /sessions/<id>
    A->>T: tmux kill-session -t <repo>-<N>
    A->>A: git worktree remove
    A-->>D: 200 {status: stopped}
```

## Component Architecture

```mermaid
graph TB
    subgraph "agent-daemon process"
        HTTP["Warp HTTP Server"]
        WS["WebSocket Handler"]
        SM["Session Manager<br/>(TVar Map)"]
        TM["Tmux Manager"]
        WM["Worktree Manager"]
        REC["Recovery"]

        HTTP --> SM
        WS --> SM
        SM --> TM
        SM --> WM
        REC --> SM
        REC --> TM
    end

    subgraph "OS layer"
        TMX["tmux"]
        GIT["git"]
        PTY["PTY pairs"]
    end

    TM --> TMX
    TM --> PTY
    WM --> GIT
```

### Components

- **Warp HTTP Server** — REST endpoints for session CRUD, static file serving
- **WebSocket Handler** — bridges xterm.js to tmux PTY streams with bidirectional binary frames
- **Session Manager** — in-memory `TVar (Map SessionId Session)`, thread-safe, not persisted to disk
- **Tmux Manager** — creates, attaches, kills tmux sessions
- **Worktree Manager** — creates and removes git worktrees, branches as `feat/issue-<N>`
- **Recovery** — on startup, scans for existing tmux sessions and reconstructs state from worktree directories and git remote URLs

## Session State Machine

```mermaid
stateDiagram-v2
    [*] --> Creating: POST /sessions
    Creating --> Running: worktree + tmux ready
    Creating --> Failed: error

    Running --> Attached: WS connect
    Attached --> Running: WS disconnect
    Running --> Stopping: DELETE /sessions/<id>
    Attached --> Stopping: DELETE /sessions/<id>

    Stopping --> [*]: cleanup done
    Failed --> [*]: reported
```

## Data Model

```mermaid
classDiagram
    class Session {
        +SessionId id
        +Repo repo
        +IssueNumber issue
        +WorktreePath worktree
        +TmuxSession tmuxName
        +SessionState state
        +UTCTime createdAt
    }

    class SessionState {
        <<enumeration>>
        Creating
        Running
        Attached
        Stopping
        Failed Text
    }

    class Repo {
        +Text owner
        +Text name
    }

    Session --> SessionState
    Session --> Repo
```

## Naming Conventions

| Entity | Pattern | Example |
|--------|---------|---------|
| Worktree path | `/code/<repo>-issue-<N>/` | `/code/cardano-utxo-csmt-issue-42/` |
| tmux session | `<repo>-<N>` | `cardano-utxo-csmt-42` |
| Branch | `feat/issue-<N>` | `feat/issue-42` |
| Session ID | `<repo>-<N>` | `cardano-utxo-csmt-42` |

## REST API

### Launch session

```
POST /sessions
Content-Type: application/json

{
  "repo": { "owner": "cardano-foundation", "name": "cardano-utxo-csmt" },
  "issue": 42
}

→ 201 Created (new session)
→ 200 OK (session already exists, idempotent)
{
  "id": "cardano-utxo-csmt-42",
  "repo": { "owner": "cardano-foundation", "name": "cardano-utxo-csmt" },
  "issue": 42,
  "worktree": "/code/cardano-utxo-csmt-issue-42",
  "tmuxName": "cardano-utxo-csmt-42",
  "state": "creating",
  "createdAt": "2026-03-13T10:30:00Z"
}
```

### List sessions

```
GET /sessions

→ 200 OK
[
  {
    "id": "cardano-utxo-csmt-42",
    "repo": { "owner": "cardano-foundation", "name": "cardano-utxo-csmt" },
    "issue": 42,
    "state": "running",
    "createdAt": "2026-03-13T10:30:00Z"
  }
]
```

### Stop session

```
DELETE /sessions/cardano-utxo-csmt-42

→ 200 OK
{ "status": "stopped" }
```

Kills the tmux session and removes the git worktree.

### Terminal attach

```
GET /sessions/cardano-utxo-csmt-42/terminal
Upgrade: websocket

↔ bidirectional binary frames (terminal I/O)
```

Terminal resize is sent as a protocol message: `\x01cols;rows`.

### Static files

Any path not matching the API routes serves from `--static-dir`,
falling back to `index.html` (SPA support).

### CORS

All responses include permissive CORS headers (any origin, GET/POST/DELETE/OPTIONS).

## Issue Context Injection

When a session launches, the daemon sends a bootstrap command to tmux:

```bash
claude 'Work on owner/repo#N. Start by running: gh issue view N -R owner/repo'
```

Claude receives the issue context by running `gh issue view` interactively.
No environment variables or prompt files are used.

## Session Recovery

On startup the daemon reconstructs state from existing tmux sessions:

1. Run `tmux list-sessions` to find active sessions
2. Parse session names (split on last hyphen: `repo-name-N` → repo=`repo-name`, issue=`N`)
3. Check for worktree directory at `baseDir/repoName-issue-N`
4. Read git remote URL from the worktree to recover `repoOwner`
5. Create `Session` records with `Running` state in the in-memory map

This means the daemon can be restarted without losing track of running
agent sessions — tmux and worktrees are the persistent state.

## Network Topology

```mermaid
graph LR
    subgraph "User machine"
        Browser["Browser<br/>gh-dashboard"]
    end

    subgraph "Tailscale network"
        TS["tailscale serve<br/>TLS termination<br/>:8443 → :8080"]
    end

    subgraph "Server"
        AD["agent-daemon<br/>127.0.0.1:8080"]
        T1["tmux: csmt-42"]
        T2["tmux: wallet-15"]
        W1["/code/csmt-issue-42/"]
        W2["/code/wallet-issue-15/"]
    end

    Browser -- "wss://" --> TS --> AD
    AD --> T1
    AD --> T2
    T1 -.-> W1
    T2 -.-> W2
```

The daemon binds to `127.0.0.1` (localhost only). `tailscale serve`
provides TLS termination on port 8443, accessible only within the
tailnet. See README.md for setup instructions.

## Authentication

Currently relies on Tailscale ACLs — only machines on the tailnet can
reach the service. No application-level authentication (tokens, API keys).

## Current Limitations

- **No resource limits** — unbounded concurrent sessions, no memory or CPU guards
- **No completion detection** — sessions run until explicitly stopped; no webhook or polling for PR creation
- **In-memory state** — session metadata is not persisted to disk (recovered from tmux on restart)
- **Single WebSocket per session** — no multi-attach tracking
