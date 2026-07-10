# Feature Specification: Authoritative Nix and CI Quality Contract

**Feature Branch**: `ci/make-nix-checks-and-ci-authoritative`
**Created**: 2026-07-10
**Status**: Draft
**Input**: GitHub issue #77, child of epic #80

## Clarifications

### Session 2026-07-10

- Q: Which layer owns executable verification? → A: The Nix flake owns executable checks and focused apps; local commands and workflows orchestrate those outputs.
- Q: How are strict warnings reconciled with package validation? → A: Warning-as-error behavior is opt-in through a manual development-warning flag enabled by Nix development and CI surfaces.
- Q: Which PR job names form the merge contract? → A: `Build Gate`, `Haskell build and tests`, `Formatting`, `HLint`, `Cabal package validation`, `PureScript UI`, `Workflow lint`, `Dev shell build`, and `Darwin build`.

## User Scenarios & Testing

### User Story 1 - Run One Complete Local Gate (Priority: P1)

As a contributor, I run one lowercase `just ci` command and receive a trustworthy result for every shippable repository surface before I push.

**Why this priority**: A complete local gate is the fastest feedback path and prevents GitHub Actions from becoming the first place ordinary failures are discovered.

**Independent Test**: From a clean checkout, run `nix develop --quiet -c just ci`; it exits successfully, reports all 55 existing Haskell examples with zero failures, and exercises each declared quality surface.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** the contributor runs the lowercase local gate, **Then** Haskell build/tests, formatting, HLint, package validation, PureScript install/lint/build/bundle, workflow lint, and a representative development-shell build all succeed.
2. **Given** a deliberate formatting defect, **When** the representative flake check runs, **Then** it exits non-zero; after the defect is restored, the same check and full local gate exit zero.
3. **Given** the existing Haskell suite, **When** the test surface runs, **Then** all 55 examples execute and report zero failures rather than only compiling a wrapper.

---

### User Story 2 - Review Stable, Always-Present CI Gates (Priority: P1)

As a reviewer, I see stable, always-present pull-request checks whose names and results map directly to the local quality contract.

**Why this priority**: Reviewers need unambiguous merge evidence, and ruleset contexts are safe only when the jobs are present on every pull request.

**Independent Test**: Open or update the draft pull request and verify all nine named jobs appear; each substantive Linux job invokes the flake-owned surface or the separate representative development-shell build and finishes successfully.

**Acceptance Scenarios**:

1. **Given** any pull request to `main`, **When** CI starts, **Then** `Build Gate` warms the shared Nix store before the dependent Linux jobs run.
2. **Given** the cache-warming job succeeds, **When** dependent jobs run, **Then** the Haskell, formatting, HLint, package, UI, workflow, and development-shell job names remain stable and always present.
3. **Given** multi-platform verification, **When** CI runs, **Then** Linux jobs use `nixos` and `Darwin build` remains on the prescribed macOS runner.

---

### User Story 3 - Protect Main with the Observed CI Contract (Priority: P2)

As a maintainer, I configure the main ruleset from observed pull-request job names without losing the documented admin bypass.

**Why this priority**: Correct checks are not merge gates until the ruleset requires their exact, always-present contexts.

**Independent Test**: After all jobs are observed on the pull request, inspect ruleset `13867328`; its required contexts equal the nine names in this specification and its only documented bypass remains repository role actor `5` in `always` mode.

**Acceptance Scenarios**:

1. **Given** green pull-request checks, **When** the main ruleset is updated, **Then** it requires exactly the nine observed job contexts and no conditional or manual-only workflow context.
2. **Given** the pre-existing admin bypass, **When** the ruleset update is complete, **Then** actor `5`, type `RepositoryRole`, mode `always` is unchanged.

### Edge Cases

- A flake output that only builds a shell wrapper is not counted as executable verification; the check must run its underlying command in a sandbox.
- Packaged checks do not prove the development shell works; the development-shell build remains a separate gate.
- The `nixos` custom runner label must be declared to workflow linting without weakening validation of other runner labels.
- Existing release and Pages workflows may receive only behavior-neutral lint corrections; their triggers and publication behavior remain unchanged.
- CI jobs must not disappear through path filters, event conditions, matrix exclusions, or job-level conditions on pull requests.
- The baseline audit's alleged missing source-repository stanza was not reproduced: the current `cabal.project` already contains the pinned stanza, so no edit is justified unless fresh validation exposes a concrete warning.
- The existing uppercase `just CI` constitution command remains as a compatibility alias while lowercase `just ci` becomes the canonical contributor entrypoint.

## Requirements

### Functional Requirements

- **FR-001**: The flake MUST expose real sandboxed checks and matching focused apps for Haskell build/tests, formatting, HLint, Cabal package validation, PureScript UI verification, and workflow linting.
- **FR-002**: Each scripted flake check MUST invoke the same strict-path executable exposed as its matching app; building a script without executing it is insufficient.
- **FR-003**: The Haskell test surface MUST execute all 55 existing examples and report their result.
- **FR-004**: The Cabal package MUST move `-Werror` behind a manual, default-off development-warning flag, and the Nix development/CI configuration MUST explicitly enable that flag.
- **FR-005**: `nix develop --quiet -c cabal check` MUST report no warnings or errors after the package change.
- **FR-006**: Lowercase `just ci` MUST be the canonical local entrypoint and MUST cover the flake-owned checks plus `cabal build all -O0` inside the real development shell.
- **FR-007**: Uppercase `just CI` MUST remain a compatibility alias to the lowercase entrypoint so the current constitution remains satisfied.
- **FR-008**: Workflow linting MUST recognize the `nixos` custom runner and MUST validate every committed workflow with actionlint and shellcheck.
- **FR-009**: Any changes outside `.github/workflows/ci.yml` MUST be minimal lint-only corrections that do not alter release or documentation behavior.
- **FR-010**: The CI workflow MUST start with `Build Gate` and MUST expose the exact always-present job names `Haskell build and tests`, `Formatting`, `HLint`, `Cabal package validation`, `PureScript UI`, `Workflow lint`, `Dev shell build`, and `Darwin build`.
- **FR-011**: Every Linux CI job MUST run on `nixos`; `Darwin build` MUST remain on the prescribed macOS runner.
- **FR-012**: Substantive CI jobs MUST orchestrate flake-owned apps rather than duplicate their shell logic; `Dev shell build` MUST separately run a representative `nix develop` build.
- **FR-013**: Ruleset `13867328` MUST require exactly the nine job contexts named in FR-010, including `Build Gate`.
- **FR-014**: Ruleset `13867328` MUST retain bypass actor `5` with actor type `RepositoryRole` and bypass mode `always`.
- **FR-015**: The implementation MUST include observed RED evidence from a deliberate representative defect followed by GREEN evidence from the restored full gate.
- **FR-016**: The ticket MUST NOT change application/API/terminal/WebSocket/session/UI behavior, test semantics, GHC version, release publication, documentation behavior, or historical tags/releases.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `nix flake check --no-eval-cache` exits `0` and executes every declared flake check.
- **SC-002**: `nix develop --quiet -c just ci` exits `0` from a clean worktree after exercising every local contract surface.
- **SC-003**: The Haskell test output reports exactly 55 examples and 0 failures.
- **SC-004**: `nix develop --quiet -c cabal check` exits `0` with no warnings or errors.
- **SC-005**: Repository-wide actionlint/shellcheck validation exits `0` with zero findings across every committed workflow.
- **SC-006**: Pull request #81 shows all nine named jobs and each concludes successfully.
- **SC-007**: Ruleset `13867328` contains exactly nine required contexts matching the observed PR job names and retains exactly the documented admin-role bypass.
- **SC-008**: A deliberate representative defect causes its focused check to exit non-zero before restoration; the restored focused check and final full gate both exit `0`.

## Assumptions

- The existing branch and worktree remain based on the current `origin/main`; no duplicate worktree is needed.
- Current GHC 9.8.4 and all application/test sources remain unchanged.
- The pinned source-repository package in `cabal.project` remains valid unless fresh package validation provides contrary evidence.
- Self-hosted `nixos` runners share a Nix store, so the Build Gate remains useful as a cache warmer even though checks are independently executable.
- Main ruleset mutation occurs only after GitHub has reported the final always-present job names on pull request #81.
