# Research: Git Library Bindings

## Decision: Use typed CLI wrappers instead of FFI bindings

### Rationale

No Haskell library supports git worktree create/remove — the daemon's core operation.

- **hlibgit2** binds libgit2 v0.18.0 (2013). Worktree support was added to libgit2 in v0.24+ (2015). An open PR (#109) to update to v1.7.1 has been unmerged since Nov 2023.
- **gitlib** provides a `MonadGit` typeclass for object-level operations (commits, trees, blobs, refs) but has no worktree, remote, or fetch concepts.
- **git** (hs-git by Vincent Hanquez) is archived (2021), read-only, no worktree support.
- **No other Haskell libgit2 bindings exist.**

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| hlibgit2 (current) | Native FFI, no subprocess | Stuck on 2013 libgit2, no worktree support |
| hlibgit2 + PR #109 | Would get worktree support | Unmerged 2+ years, would need to maintain fork |
| gitlib + MonadGit | Nice typed API | No worktree/remote/fetch, needs hlibgit2 backend |
| hs-git | Pure Haskell | Archived, read-only, no worktree |
| **typed-process CLI wrapper** | Full git feature set, typed errors, testable | Still subprocess-based |

### Chosen Approach

Create a `AgentDaemon.Git` module that:

1. Wraps `git` CLI via `typed-process` (replacing raw `System.Process` calls)
2. Returns structured error types (not `Text` or `IOException`)
3. Provides typed return values for each operation
4. Centralizes all git subprocess calls behind a single interface
5. Is mockable via a typeclass or record-of-functions for future testing

This delivers the issue's core goals (typed errors, no fragile parsing, centralized git interface) while acknowledging the library ecosystem gap. The `git` CLI is already a hard dependency.

### typed-process vs process

`typed-process` (by Michael Snoyman) improves on `System.Process`:
- Explicit `ExitCode` handling (no silent failures)
- `ByteString`/`Text` output (no lazy String)
- Resource-safe (bracket-based cleanup)
- Already well-maintained, compatible with GHC 9.8.4

The project currently uses `process`. Adding `typed-process` is a small dependency.
