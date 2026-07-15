# tmux-ws Constitution

## Core Principles

### I. One Product Across the Browser and tmux Boundary

tmux-ws is a Haskell daemon whose bundled PureScript SPA is served from one origin
with its REST API and WebSocket terminal relay.
The touch-first interface must remain practical for tablet and small-screen
operation, including the on-screen command deck and guarded close-current
actions.

The browser is a client of real daemon and tmux behavior, not a substitute for
it. Changes that reach tmux must preserve the tmux live-boundary contract:
session discovery, terminal attachment, commands, close actions, and recovery
must be verified at the strongest boundary available.

### II. Nix-First, Flake-Owned Reproducibility

Nix-first reproducibility governs development, verification, packaging, and
documentation. The repository's flake-owned checks, apps, and packages are the
source of truth, with pinned toolchains and dependencies providing repeatable
inputs across supported systems.

The durable full local gate from a fresh checkout is
`nix develop --quiet -c just ci`; it enters the pinned development shell and
invokes the `just ci` recipe with that exact spelling. Because packaged
derivations do not enter the development shell, CI must also keep a separate
development-shell gate that performs a representative Cabal build.

### III. RED/GREEN Tests and Boundary Evidence

Behavior changes follow RED then GREEN test-first discipline: first observe a
focused check fail for the expected reason, then make the smallest change that
passes it. Fresh verification output is required as evidence before completion,
and the full repository gate must pass before a slice is handed off.

Use a live-boundary smoke whenever deterministic checks cannot establish the
production contract. No combination of mocks, unit tests, or golden checks can
by itself prove tmux, browser, packaging, service, and preview boundaries. When
CI cannot reach a required boundary, record a named operator follow-up with a
verifiable artifact before merge.

### IV. Typed Contracts and Separation of Concerns

Public type and API contracts must keep Haskell handlers, JSON payloads,
PureScript clients, and WebSocket protocols compatible. Contract changes require
tests at the affected boundary and explicit compatibility review.

Maintain separation of concerns: domain decisions belong outside transport and
UI wiring; external effects such as git, tmux, processes, HTTP, and WebSockets
remain explicit; the SPA owns presentation and interaction rather than daemon
policy. Temporary migration details are not permanent architectural axioms.

### V. Cabal-Owned, Immutable Releases

The Cabal manifest and its version are the release authority.
A release tag must match that version, and release notes and artifacts must
describe the same product version before publication.

Published tags and releases are immutable; a defect requires a corrective
release rather than rewriting history. There is no ad-hoc artifact publication:
artifacts are built, smoked, and attached only through the reviewed release
contracts. Any compatibility alias removal or migration change crosses a
compatibility and migration review boundary and must be handled separately.

### VI. Reviewable, Linear Delivery

Linux and documentation jobs run on `nixos`; Darwin jobs run on `macos-14`.
Platform-specific behavior must be proved on its corresponding runner.

Conventional Commits provide task traceability, including the required `Tasks:`
trailer. Delivery uses rebase-only linear history, with one
bisect-safe slice commit for each reviewed slice;
repository rules and required CI checks are merge gates and may not be bypassed
to land an unverified change.

## Governance

This constitution governs repository-local engineering decisions. An amendment
must be proposed as a reviewed change, explain the affected principles and
migration consequences, update dependent guidance or templates, and pass the
same repository gates as other changes.

Semantic versions describe governance impact: MAJOR for incompatible or
materially rewritten principles, MINOR for a new principle or substantial
expansion, and PATCH for clarification without changed obligations. Reviewers
must check compliance explicitly; exceptions require documented scope, owner,
and resolution before merge.

**Version**: 2.0.0
**Last amended**: 2026-07-15
