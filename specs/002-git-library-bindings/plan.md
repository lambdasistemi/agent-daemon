# Implementation Plan: Git Library Bindings

**Branch**: `002-git-library-bindings` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-git-library-bindings/spec.md`

## Summary

Replace fragile `System.Process` git calls scattered across `Worktree.hs`, `Branch.hs`, and `Recovery.hs` with a centralized `AgentDaemon.Git` module using `typed-process`. All git operations get structured error types and typed return values. No Haskell git FFI library supports worktree operations, so the CLI wrapper is the pragmatic choice (see [research.md](research.md)).

## Technical Context

**Language/Version**: Haskell, GHC 9.8.4 via haskell.nix
**Primary Dependencies**: typed-process (new), aeson, warp, websockets, stm, posix-pty
**Storage**: N/A (stateless refactor)
**Testing**: hspec (existing e2e suite, add unit tests for Git module)
**Target Platform**: x86_64-linux, aarch64-darwin
**Project Type**: daemon (WebSocket server)
**Performance Goals**: N/A (no performance-sensitive changes)
**Constraints**: Must preserve all existing behavior
**Scale/Scope**: 3 modules refactored, 1 new module, ~300 lines changed

## Constitution Check

*Constitution is not yet defined for this project. No gates to evaluate.*

## Project Structure

### Documentation (this feature)

```text
specs/002-git-library-bindings/
├── spec.md
├── plan.md              # This file
├── research.md          # Library evaluation
├── data-model.md        # Error types and interface
└── tasks.md             # Created by /speckit.tasks
```

### Source Code (repository root)

```text
src/AgentDaemon/
├── Git.hs               # NEW — centralized git CLI wrapper
├── Worktree.hs          # MODIFIED — delegate to Git module
├── Branch.hs            # MODIFIED — delegate to Git module
├── Recovery.hs          # MODIFIED — delegate to Git module
├── Types.hs             # MODIFIED — add GitError type
└── ...                  # unchanged
```

**Structure Decision**: Single new module `AgentDaemon.Git` houses all git subprocess interactions. Existing modules become thin callers. No new directories needed.

## Design

### Phase 1: Core Git Module (User Story 1 — P1)

1. **Add `typed-process` dependency** to `agent-daemon.cabal`
2. **Define `GitError`** in `AgentDaemon.Types`:
   - `GitError { gitCommand :: Text, gitExitCode :: Int, gitStderr :: Text, gitRepoPath :: FilePath }`
3. **Create `AgentDaemon.Git`** with:
   - `runGit :: FilePath -> [String] -> IO (Either GitError ())` — fire-and-forget commands
   - `readGit :: FilePath -> [String] -> IO (Either GitError Text)` — commands that return output
   - `createWorktree :: FilePath -> FilePath -> Text -> Text -> IO (Either GitError ())`
   - `removeWorktree :: FilePath -> FilePath -> IO (Either GitError ())`
   - `defaultBranch :: FilePath -> IO Text` (falls back to "main")
   - `fetch :: FilePath -> String -> IO (Either GitError ())`
4. **Refactor `AgentDaemon.Worktree`** to call `AgentDaemon.Git` instead of `System.Process`
5. **Remove `process` import** from `Worktree.hs`

### Phase 2: Branch Operations (User Story 2 — P2)

1. **Add to `AgentDaemon.Git`**:
   - `listBranchesByPattern :: FilePath -> String -> IO (Either GitError [String])`
   - `deleteBranchLocal :: FilePath -> String -> Bool -> IO (Either GitError ())`
   - `deleteBranchRemote :: FilePath -> String -> IO (Either GitError ())`
   - `revParseVerify :: FilePath -> String -> IO Bool`
   - `syncStatus :: FilePath -> String -> IO SyncStatus`
2. **Refactor `AgentDaemon.Branch`** to call `AgentDaemon.Git`
3. **Remove `runGit`, `quietGit`** from `Branch.hs`

### Phase 3: Recovery Operations (User Story 3 — P3)

1. **Add to `AgentDaemon.Git`**:
   - `getRemoteUrl :: FilePath -> String -> IO (Either GitError Text)`
2. **Refactor `AgentDaemon.Recovery`** to call `AgentDaemon.Git.getRemoteUrl` instead of `readProcess`
3. **Remove `process` import** from `Recovery.hs`
4. **Remove `process` from cabal build-depends** for the library (keep in test suite if needed)

### Phase 4: Verification

1. Run existing e2e tests — must pass unchanged
2. Grep for `callProcess`, `readProcess`, `readCreateProcess` with git arguments — must find zero
3. Build with `-Wall -Werror` — must pass

## Complexity Tracking

No constitution violations to justify.
