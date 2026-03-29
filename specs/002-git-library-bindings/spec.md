# Feature Specification: Git Library Bindings

**Feature Branch**: `002-git-library-bindings`
**Created**: 2026-03-29
**Status**: Draft
**Input**: User description: "refactor: use git/github libraries instead of shelling out"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reliable Worktree Operations (Priority: P1)

As the daemon operator, I want worktree creation and removal to use native git bindings so that failures are reported as structured errors rather than opaque process exit codes.

**Why this priority**: Worktree management is the daemon's core loop — every session starts with creating a worktree and ends by removing one. Parsing process output is the primary source of edge-case bugs (e.g., the recent `main` vs `master` default branch detection issue).

**Independent Test**: Create and remove worktrees via the daemon API and verify that invalid paths, missing branches, and already-existing worktrees produce specific, typed error values instead of raw stderr text.

**Acceptance Scenarios**:

1. **Given** a repository with `main` as default branch, **When** the daemon creates a worktree for an issue, **Then** the worktree is created on a new branch based off the default branch without shelling out to `git`.
2. **Given** a repository with `master` as default branch, **When** the daemon detects the default branch, **Then** it returns `master` without parsing text output from a subprocess.
3. **Given** a worktree that exists on disk, **When** the daemon removes it, **Then** the worktree directory and its git metadata are cleaned up via library calls.
4. **Given** an invalid worktree path, **When** removal is attempted, **Then** a typed error is raised (not a process exit code).

---

### User Story 2 - Reliable Branch Management (Priority: P2)

As the daemon operator, I want branch listing, deletion, and sync-status checks to use native git bindings so that branch operations are robust against format changes in git CLI output.

**Why this priority**: Branch operations (list, delete, sync status) are used in cleanup, recovery, and UI display. They currently parse `--format` output and `rev-list --left-right` counts, which is brittle.

**Independent Test**: List issue branches, check sync status, and delete branches through the daemon, verifying correct results against known repository state without relying on subprocess text parsing.

**Acceptance Scenarios**:

1. **Given** a repository with several `feat/issue-*` branches, **When** branches are listed, **Then** all matching branches are returned as typed values.
2. **Given** a local branch ahead of its remote, **When** sync status is checked, **Then** the ahead/behind counts are returned as integers without parsing `rev-list` output.
3. **Given** a branch to delete, **When** deletion is requested (local and remote), **Then** both operations succeed or fail with typed errors.

---

### User Story 3 - Reliable Repository Metadata Extraction (Priority: P3)

As the daemon operator, I want repository owner and remote URL extraction to use native git bindings so that recovery can reconstruct sessions without fragile URL parsing of subprocess output.

**Why this priority**: Recovery reads the git remote URL to determine the repo owner, then reconstructs sessions. A parsing failure here means orphaned sessions.

**Independent Test**: Point recovery at worktrees with SSH and HTTPS remotes and verify owner extraction returns correct values through library calls.

**Acceptance Scenarios**:

1. **Given** a worktree with an SSH remote (`git@github.com:org/repo.git`), **When** the repo owner is extracted, **Then** it returns `org` without shelling out.
2. **Given** a worktree with an HTTPS remote (`https://github.com/org/repo.git`), **When** the repo owner is extracted, **Then** it returns `org` without shelling out.

---

### Edge Cases

- What happens when the git repository is in a corrupted state (e.g., missing `.git` directory)?
- How does the system handle a worktree pointing to a branch that no longer exists on the remote?
- What happens when the remote is unreachable during a fetch operation?
- How does default branch detection behave when `refs/remotes/origin/HEAD` is not set?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST perform all worktree operations (create, remove) through native git library bindings, not subprocess calls.
- **FR-002**: System MUST detect the repository's default branch through native git library bindings.
- **FR-003**: System MUST list, delete, and check sync status of branches through native git library bindings.
- **FR-004**: System MUST extract remote URL and parse repository owner through native git library bindings.
- **FR-005**: System MUST report git operation failures as typed, structured errors (not raw process exit codes or stderr text).
- **FR-006**: System MUST fetch from remotes through native git library bindings.
- **FR-007**: System MUST preserve all existing behavior — the change is internal (same inputs produce same outputs).

### Key Entities

- **GitRepository**: A local repository checkout, identified by its root path. Used to open a handle for all git operations.
- **Worktree**: A secondary working directory linked to a branch within a repository. Created and removed by the daemon per session.
- **Branch**: A git ref, either local or remote. Listed, compared, and deleted during cleanup and recovery.
- **Remote**: A named remote (typically `origin`) with a URL. Inspected for owner extraction and fetch targets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All existing daemon tests pass without modification (behavior preservation).
- **SC-002**: Zero subprocess calls to `git` remain in the codebase (verifiable by searching for `callProcess`, `readProcess`, `readCreateProcess` with git arguments).
- **SC-003**: Git operation errors are reported as typed values, not raw strings or exit codes.
- **SC-004**: Default branch detection works correctly for repositories using `main`, `master`, or custom default branches.

## Assumptions

- The git library chosen provides worktree management support (create/remove). If not, worktree operations may still require subprocess calls as a scoped exception.
- The existing URL parsing logic for SSH/HTTPS remotes (`parseOwner`) remains valid — only the method of obtaining the URL changes.
- Network operations (fetch, remote push/delete) are available through the chosen library.
- Tmux subprocess calls are out of scope — only git-related process calls are replaced.
