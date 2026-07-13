# Feature Specification: tmux-ws public release identity

**Feature Branch**: `fix/95-release-product-name`
**Created**: 2026-07-13
**Status**: Planned
**Input**: Issue #95 and parent epic #80

## User Scenarios & Testing

### User Story 1 - Install the named product (Priority: P1)

As a new operator, I install and run `tmux-ws` rather than the historical
implementation name, while an existing script that invokes `agent-daemon`
continues to work during this corrective patch release.

**Why this priority**: The executable and package identity are the primary
operator-facing contract.

**Independent Test**: Build the default packaged output, run
`tmux-ws --help`, run the compatibility `agent-daemon --help`, and prove that
the package/default app and checks select `tmux-ws` as primary.

**Acceptance Scenarios**:

1. **Given** a new Nix or Cabal installation, **When** the operator follows
   the primary command, **Then** `tmux-ws --help` succeeds and all public
   package metadata names `tmux-ws`.
2. **Given** an existing operator automation that runs `agent-daemon`, **When**
   it is upgraded to this patch release, **Then** the compatibility command
   runs the same daemon and its temporary status is explicit in the docs.

---

### User Story 2 - Receive a safe macOS/Homebrew corrective release (Priority: P1)

As a macOS operator, I receive a new immutable patch asset and a `tmux-ws`
Homebrew formula whose installed command works, without rewriting `v0.3.0` or
publishing from a pull request.

**Why this priority**: The faulty Darwin asset and tap formula are the direct
customer impact behind #95.

**Independent Test**: A non-publishing release/package proof validates the
new archive name and `bin/tmux-ws`, generated `TmuxWs` formula and clean
`brew install lambdasistemi/tap/tmux-ws` smoke contract. Contract checks also
exercise both supported GitHub App author shapes in release recovery.

**Acceptance Scenarios**:

1. **Given** a patch tag created after this PR merges, **When** Darwin
   publication runs, **Then** it uploads
   `tmux-ws-<version>-aarch64-darwin.tar.gz` containing `bin/tmux-ws` to the
   already-created release.
2. **Given** a clean Homebrew environment, **When** the operator installs
   `lambdasistemi/tap/tmux-ws`, **Then** `tmux-ws --help` succeeds; the old
   formula is an explicit compatibility/migration route rather than the
   primary formula.
3. **Given** release-please recovery sees a merged generated PR authored as
   either `lambdasistemi-ci[bot]` or `app/lambdasistemi-ci`, **When** the
   matching release state is recovered, **Then** it recognizes only that
   exact generated PR and removes no unrelated PR.

---

### User Story 3 - Follow current installation and service documentation (Priority: P2)

As a new or upgrading operator, I find `tmux-ws` first in README, install,
deployment, Tailscale, release, and NixOS service instructions, with a
separate migration section for historical names.

**Why this priority**: A corrected package that docs still teach under the old
name recreates the incident for new operators.

**Independent Test**: Build documentation in strict mode, resolve every
installation/deployment link and anchor, and run source-level checks that
reject `agent-daemon` in current-title, primary-command, archive, or formula
surfaces while permitting the bounded migration section and private keys.

**Acceptance Scenarios**:

1. **Given** a first-time operator, **When** they open README or documentation
   installation/deployment guidance, **Then** every primary command, package,
   formula, and service title is `tmux-ws`.
2. **Given** an existing NixOS service configuration, **When** it follows the
   documented migration path, **Then** it can move to the new primary service
   name without a silent outage; the legacy service path remains explicitly
   documented and tested for this release.

### Edge Cases

- `v0.3.0`, its historical Darwin asset, and its tap formula remain immutable;
  no task may delete, overwrite, or retag them.
- Pull-request and dry-run paths must not upload assets or mutate the Homebrew
  tap.
- `AgentDaemon` namespaces, browser storage keys, and private test fixture
  names remain unchanged unless proven to be a public package surface.
- A generated release PR with a matching branch but an unrecognized author,
  wrong base, wrong title, or ambiguous match must not be recovered or closed.

## Requirements

### Functional Requirements

- **FR-001**: The canonical Cabal package, default Nix package/app, and
  primary executable MUST be named `tmux-ws`; `tmux-ws --help` MUST be proven
  from the packaged output.
- **FR-002**: This patch release MUST retain an intentional, tested
  `agent-daemon` compatibility command. It MUST NOT be the default package,
  formula, command, or service title.
- **FR-003**: Darwin publication MUST produce
  `tmux-ws-<version>-aarch64-darwin.tar.gz` with `bin/tmux-ws`, validate its
  installed layout, and publish only to an already-created immutable release.
- **FR-004**: Homebrew publication MUST generate primary formula `tmux-ws`,
  install and smoke `tmux-ws --help`, and provide an explicit compatibility
  treatment for the historical `agent-daemon` formula.
- **FR-005**: Release-please recovery and false-follow-on cleanup MUST accept
  exactly `lambdasistemi-ci[bot]` and `app/lambdasistemi-ci`, while retaining
  title, branch, base, time, and ambiguity guards.
- **FR-006**: Automated checks MUST fail on regression of the primary package,
  packaged help command, Darwin archive/binary, primary formula/install smoke,
  current user-facing title/install command, or App-author cleanup selector.
- **FR-007**: README and current installation, upgrade, deployment,
  Tailscale, release, and operator documentation MUST lead with `tmux-ws`.
  Historical text is allowed only in identified migration text or intentionally
  private identifiers.
- **FR-008**: The NixOS module MUST expose `tmux-ws` as the primary service
  configuration and preserve a documented, tested legacy service migration or
  alias path.
- **FR-009**: Documentation MUST build strictly and prove current
  installation/release/deployment links and anchors resolve.
- **FR-010**: The complete repository gate and focused naming/release proofs
  MUST run before review. No pull-request execution may publish, merge, change
  tap state, delete a release, or alter `v0.3.0`.

## Success Criteria

- **SC-001**: The default packaged output exposes `tmux-ws --help` with exit
  status 0, and the compatibility command also exits 0.
- **SC-002**: A non-publishing Darwin/Homebrew proof validates exactly one
  `tmux-ws-<version>-aarch64-darwin.tar.gz`, `bin/tmux-ws`, the
  `tmux-ws` formula, and `tmux-ws --help` with no tap mutation.
- **SC-003**: Strict documentation build and link/anchor validation finish
  with zero errors; every current installation command uses the canonical name.
- **SC-004**: The full repository gate and all hosted required CI jobs succeed
  on the final PR head before the PR becomes ready.

## Assumptions

- The bounded compatibility window is this corrective patch release; removal
  requires a separately reviewed migration ticket.
- The historical Homebrew formula can remain as a deprecated forwarding formula
  so old automation has an explicit route to `tmux-ws`.
- The final patch version and release notes are created only after merge by
  release-please; this branch must not pre-create a tag or release.
