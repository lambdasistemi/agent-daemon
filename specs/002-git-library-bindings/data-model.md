# Data Model: Git Library Bindings

## Entities

### GitError

Structured error type replacing raw `Text` and `IOException` from git operations.

- **command**: The git subcommand that failed (e.g., "worktree add", "branch -d")
- **exitCode**: Process exit code
- **stderr**: Error output from git
- **repoPath**: Repository path where the command ran

### SyncStatus (existing)

Already well-typed: `Synced | Ahead Int | Behind Int | Diverged Int Int | LocalOnly`

No changes needed.

### BranchInfo (existing)

Already well-typed with `branchRepo`, `branchIssue`, `branchName`, `branchSync`.

No changes needed.

## Interface: Git Operations

Central abstraction grouping all git CLI interactions:

### Worktree operations
- **createWorktree**: repo path, destination, branch name → success or GitError
- **removeWorktree**: repo path, worktree path → success or GitError

### Branch operations
- **defaultBranch**: repo path → branch name or GitError
- **listIssueBranches**: repo path → list of branch names or GitError
- **deleteBranchLocal**: repo path, branch, force flag → success or GitError
- **deleteBranchRemote**: repo path, branch → success or GitError
- **syncStatus**: repo path, branch → SyncStatus

### Remote operations
- **fetch**: repo path, remote, refspec → success or GitError
- **getRemoteUrl**: repo path, remote name → URL text or GitError

## State Transitions

None — this is a stateless refactor. All state management remains in `SessionManager` (STM).

## Validation Rules

- Repository paths must exist and contain `.git`
- Branch names must be non-empty
- Worktree destination must not already exist (or reuse is handled)
