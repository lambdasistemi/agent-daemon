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
    A->>T: send-keys "cd worktree && claude"
    A-->>D: 201 {session_id, status: running}

    D->>A: WS /sessions/<id>/terminal
    A->>T: tmux attach -t <repo>-<N>
    T-->>A: PTY stream
    A-->>D: terminal I/O (bidirectional)

    Note over D,C: User disconnects (closes tab)
    Note over T,C: tmux + Claude keep running

    D->>A: WS /sessions/<id>/terminal
    A->>T: tmux attach -t <repo>-<N>
    T-->>A: PTY stream (resumes)
    A-->>D: terminal I/O (reconnected)

    D->>A: DELETE /sessions/<id>
    A->>T: tmux kill-session -t <repo>-<N>
    A->>A: git worktree remove
    A-->>D: 200 OK
```

## Component Architecture

```mermaid
graph TB
    subgraph "agent-daemon process"
        HTTP["Warp HTTP Server"]
        WS["WebSocket Handler"]
        SM["Session Manager"]
        TM["Tmux Manager"]
        WM["Worktree Manager"]

        HTTP --> SM
        WS --> SM
        SM --> TM
        SM --> WM
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

- **Warp HTTP Server** — REST endpoints for session CRUD
- **WebSocket Handler** — bridges xterm.js to tmux PTY streams
- **Session Manager** — tracks active sessions, maps issue to session
- **Tmux Manager** — creates, attaches, kills tmux sessions
- **Worktree Manager** — creates and removes git worktrees

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

## REST API

### Launch session

```
POST /sessions
Content-Type: application/json

{
  "repo": { "owner": "cardano-foundation", "name": "cardano-utxo-csmt" },
  "issue": 42
}

→ 201 Created
{
  "id": "cardano-utxo-csmt-42",
  "state": "creating",
  "worktree": "/code/cardano-utxo-csmt-issue-42"
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
DELETE /sessions/cardano-utxo-csmt-42?cleanup=true

→ 200 OK
```

### Terminal attach

```
GET /sessions/cardano-utxo-csmt-42/terminal
Upgrade: websocket

↔ bidirectional binary frames (terminal I/O)
```

## Network Topology

```mermaid
graph LR
    subgraph "User machine"
        Browser["Browser<br/>gh-dashboard"]
    end

    subgraph "Tailscale network"
        TS["Tailscale tunnel"]
    end

    subgraph "Server (single machine)"
        AD["agent-daemon<br/>:8080"]
        T1["tmux: csmt-42"]
        T2["tmux: wallet-15"]
        W1["/code/csmt-issue-42/"]
        W2["/code/wallet-issue-15/"]
    end

    Browser --> TS --> AD
    AD --> T1
    AD --> T2
    T1 -.-> W1
    T2 -.-> W2
```

## Open Questions

1. **Issue context injection** — how does Claude know what issue to work on?
   Options: prompt file in worktree, `CLAUDE_ISSUE` env var, or rely
   on a bootstrap skill that reads from branch name.

2. **Authentication** — Tailscale ACLs may suffice. Add token auth later
   if needed.

3. **Completion detection** — how to know the agent is done?
   Watch for PR creation via GitHub webhook, or poll.

4. **Resource limits** — max concurrent sessions, memory/CPU guards.

5. **Session recovery** — if daemon restarts, rediscover running tmux
   sessions and reconstruct state.
