# Tasks: Git Library Bindings

**Input**: Design documents from `/specs/002-git-library-bindings/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Not explicitly requested — test tasks omitted. Existing e2e suite serves as regression gate.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add dependency and define shared types

- [x] T001 Add `typed-process` dependency to `agent-daemon.cabal` build-depends
- [x] T002 Define `GitError` type in `src/AgentDaemon/Types.hs` with fields: `gitCommand :: Text`, `gitExitCode :: Int`, `gitStderr :: Text`, `gitRepoPath :: FilePath`

---

## Phase 2: Foundational

**Purpose**: Create the centralized Git module with core primitives that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Create `src/AgentDaemon/Git.hs` with `runGit :: FilePath -> [String] -> IO (Either GitError ())` using `typed-process` — run a git command, discard stdout, capture stderr on failure
- [x] T004 Add `readGit :: FilePath -> [String] -> IO (Either GitError Text)` to `src/AgentDaemon/Git.hs` — run a git command, return stdout as Text, capture stderr on failure
- [x] T005 Expose `AgentDaemon.Git` in `agent-daemon.cabal` exposed-modules list

**Checkpoint**: Foundation ready — `runGit` and `readGit` are the only two primitives needed by all stories

---

## Phase 3: User Story 1 - Reliable Worktree Operations (Priority: P1) 🎯 MVP

**Goal**: Worktree create/remove and default branch detection use `AgentDaemon.Git` instead of `System.Process`

**Independent Test**: Run existing e2e tests — worktree creation/removal must work identically

### Implementation for User Story 1

- [x] T006 [US1] Add `defaultBranch :: FilePath -> IO Text` to `src/AgentDaemon/Git.hs` — read `refs/remotes/origin/HEAD` via `readGit`, parse branch name, fall back to `"main"`
- [x] T007 [US1] Add `fetch :: FilePath -> String -> IO (Either GitError ())` to `src/AgentDaemon/Git.hs`
- [x] T008 [US1] Add `createWorktree :: FilePath -> FilePath -> Text -> Text -> IO (Either GitError ())` to `src/AgentDaemon/Git.hs` — wraps `git worktree add` with new-branch and existing-branch fallback
- [x] T009 [US1] Add `removeWorktree :: FilePath -> FilePath -> IO (Either GitError ())` to `src/AgentDaemon/Git.hs`
- [x] T010 [US1] Refactor `src/AgentDaemon/Worktree.hs` to import and call `AgentDaemon.Git` functions, remove local `runGit`, `defaultBranch`, and `System.Process` imports

**Checkpoint**: Worktree.hs has zero `System.Process` imports. E2e tests pass.

---

## Phase 4: User Story 2 - Reliable Branch Management (Priority: P2)

**Goal**: Branch listing, deletion, and sync status use `AgentDaemon.Git` instead of `System.Process`

**Independent Test**: `listBranches` and `deleteBranch` API endpoints return correct results for repos with known branch state

### Implementation for User Story 2

- [x] T011 [US2] Add `listBranchesByPattern :: FilePath -> String -> IO (Either GitError [String])` to `src/AgentDaemon/Git.hs` — wraps `git branch --list <pattern> --format=%(refname:short)`
- [x] T012 [US2] Add `revParseVerify :: FilePath -> String -> IO Bool` to `src/AgentDaemon/Git.hs` — wraps `git rev-parse --verify`
- [x] T013 [US2] Add `syncStatus :: FilePath -> String -> IO SyncStatus` to `src/AgentDaemon/Git.hs` — wraps `git rev-list --left-right --count`, parses ahead/behind
- [x] T014 [P] [US2] Add `deleteBranchLocal :: FilePath -> String -> Bool -> IO (Either GitError ())` to `src/AgentDaemon/Git.hs`
- [x] T015 [P] [US2] Add `deleteBranchRemote :: FilePath -> String -> IO (Either GitError ())` to `src/AgentDaemon/Git.hs`
- [x] T016 [US2] Refactor `src/AgentDaemon/Branch.hs` to import and call `AgentDaemon.Git` functions, remove local `runGit`, `quietGit`, and `System.Process` imports

**Checkpoint**: Branch.hs has zero `System.Process` imports. E2e tests pass.

---

## Phase 5: User Story 3 - Reliable Repository Metadata Extraction (Priority: P3)

**Goal**: Remote URL reading uses `AgentDaemon.Git` instead of `System.Process`

**Independent Test**: `getRepoOwner` returns correct owner for worktrees with SSH and HTTPS remotes

### Implementation for User Story 3

- [x] T017 [US3] Add `getRemoteUrl :: FilePath -> String -> IO (Either GitError Text)` to `src/AgentDaemon/Git.hs` — wraps `git remote get-url`
- [x] T018 [US3] Refactor `src/AgentDaemon/Recovery.hs` to import and call `AgentDaemon.Git.getRemoteUrl`, remove `System.Process` import

**Checkpoint**: Recovery.hs has zero `System.Process` imports for git operations. E2e tests pass.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Clean up and verify zero git subprocess calls remain

- [x] T019 ~~Remove `process` from library build-depends~~ — kept: `Tmux.hs` and `Recovery.hs` (tmux calls) still need it
- [x] T020 Verify zero `callProcess`, `readProcess`, `readCreateProcess` git calls remain — grep codebase, build with `-Wall -Werror`
- [x] T021 Run full e2e test suite, confirm all tests pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (needs `GitError` type and `typed-process`)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (`runGit`/`readGit` primitives)
- **User Story 2 (Phase 4)**: Depends on Phase 2 only — independent of US1
- **User Story 3 (Phase 5)**: Depends on Phase 2 only — independent of US1/US2
- **Polish (Phase 6)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on Foundational. No cross-story dependencies.
- **User Story 2 (P2)**: Depends only on Foundational. Uses `getRepoOwner` from Recovery but that import path doesn't change.
- **User Story 3 (P3)**: Depends only on Foundational. No cross-story dependencies.

### Parallel Opportunities

- T014 and T015 can run in parallel (independent branch delete functions)
- US1, US2, US3 can all proceed in parallel after Phase 2
- T001 and T002 are sequential (T002 needs the dependency from T001 available)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T005)
3. Complete Phase 3: User Story 1 (T006–T010)
4. **STOP and VALIDATE**: E2e tests pass, Worktree.hs clean
5. This covers the daemon's core loop — highest-value refactor

### Incremental Delivery

1. Setup + Foundational → Git module with primitives
2. Add US1 (Worktree) → Validate → Core operations clean
3. Add US2 (Branch) → Validate → Branch management clean
4. Add US3 (Recovery) → Validate → All git calls centralized
5. Polish → Remove `process` dep, final verification

---

## Notes

- All refactored modules must preserve identical behavior (same inputs → same outputs)
- `parseOwner` in Recovery.hs stays as-is — only the URL acquisition method changes
- `listTmuxSessions` in Recovery.hs is tmux, not git — leave unchanged
- `Tmux.hs` uses `System.Process` for tmux commands — out of scope
