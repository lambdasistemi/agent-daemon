# Specification: documentation and repository governance

**Issue**: #79
**Parent**: #80
**Baseline**: `origin/main` at merged PR #101 (`a3edae6`)
**Delivery PR**: #103

## P1 user story

As a contributor or reviewer, I can understand, preview, validate, and safely
merge tmux-ws using accurate documentation and repository controls.

## Acceptance target

The branch delivers a strict, browser-accessible documentation preview on every
pull request, keeps the combined SPA/documentation site deployed from `main`,
and replaces stale onboarding and release text with an accurate touch-first,
cross-platform guide. The external repository state then matches the same
contract: current wiki, metadata and topics, security updates enabled,
rebase-only merge hygiene, branch deletion, and an active `main` ruleset that
requires the always-present `Docs build` context.

## Functional requirements

- **FR-001 — strict PR documentation check**: the documentation workflow runs
  on opened, synchronized, and reopened pull requests without a paths filter;
  its always-present `Docs build` job uses `runs-on: nixos` and builds the
  flake-owned combined site, whose docs derivation executes
  `mkdocs build --strict` and internal link/anchor validation.
- **FR-002 — preview lifecycle**: non-closed pull-request events publish the
  built site through `paolino/dev-assets/static-preview`, upserting one marker
  comment; the closed event runs a NixOS cleanup job that removes the preview.
  Live evidence must cover create, update-in-place, and delete behavior.
- **FR-003 — Pages deployment**: `main` pushes and manual dispatches build the
  same site and deploy it through GitHub Pages workflow mode. Every Linux/docs
  job uses `nixos`; Darwin jobs remain `macos-14` and are otherwise untouched.
- **FR-004 — README**: document purpose, touch-first/tablet orientation,
  macOS/Homebrew and Linux installation, Nix development, verification
  commands, documentation, releases, and the MIT license.
- **FR-005 — MkDocs experience**: use the canonical site/repository URLs,
  remembered OS-aware light/dark palettes, search, structured navigation,
  navigation indexes/sections/path, integrated table of contents, and code-copy
  support. Navigation must clearly separate user, operator, and developer
  material.
- **FR-006 — operator accuracy**: documentation describes the daemon-served
  SPA as touch-first and tablet/small-screen oriented, including the on-screen
  modifier/arrow command deck, one-shot Tmux prefix, close-current actions,
  and browser document reload after upgrades.
- **FR-007 — imminent v0.4.0 install/release guidance**: replace stale “future
  Linux artifacts” and PR-specific non-publication wording with truthful
  guidance for the imminent v0.4.0 release. Cover SHA256SUMS verification,
  versioned/stable AppImage, apt, dnf, Homebrew, NixOS, upgrades/restarts,
  tablet hard refresh, and stable documentation/release links. Do not claim
  v0.4.0 is published before it is, and do not mutate release proposal PR #102.
- **FR-008 — constitution and portable scaffold**: the Speckit constitution
  reflects the actual Haskell/PureScript browser-SPA and tmux-daemon
  architecture, flake-owned checks, RED/GREEN testing, live-boundary proof,
  Cabal-owned release invariants, NixOS/Darwin runner split, Conventional
  Commits, and rebase-only linear history. Delete the approved obsolete tracked
  `.claude/commands/speckit.*` copies while preserving `.specify/`.
- **FR-009 — wiki**: publish a Home page, sidebar, and July 2026 logbook page
  linking the repository-hardening epic #80 and issue/PR #79/#103.
- **FR-010 — metadata**: set an accurate touch-first Haskell/PureScript tmux
  workspace description, the stable Pages homepage, and relevant topics.
- **FR-011 — security**: vulnerability alerts and automated security fixes are
  enabled and read back through the GitHub API.
- **FR-012 — merge governance**: allow rebase merges only, delete branches on
  merge, and update the active `main` ruleset without losing its admin-role
  bypass or existing required contexts. Add the exact always-present
  `Docs build` context.
- **FR-013 — evidence**: fresh local full gate, strict docs/site build,
  localhost preview smoke, link/anchor validation, workflow lint, live preview
  lifecycle, exact-head hosted checks, wiki/Pages HTTP reads, and repository
  settings readback are recorded before review-ready handoff.

## Non-goals and safety constraints

- No application, API, UI, package, or service behavior changes.
- No GHC upgrade or dependency refresh unrelated to the documentation contract.
- Do not merge, close, edit, retarget, or otherwise mutate release proposal
  PR #102. Do not publish v0.4.0, push a tag, create/edit a release, or mutate
  the Homebrew tap.
- Do not rewrite historical release notes or existing immutable tags/releases.
- Do not merge PR #103 or clean its worktree/branch; the epic owner owns those
  actions.

## Success criteria

1. `./gate.sh` exits 0 on the exact final branch head before it is removed.
2. The PR has one browser-accessible preview comment whose URL returns HTTP 200;
   a later push updates the same comment, and closing the draft removes the
   preview before it is reopened for final review.
3. All exact-head required checks, including `Docs build`, succeed.
4. README/MkDocs satisfy FR-004 through FR-007 and the built site passes strict
   build plus internal link/anchor validation.
5. The GitHub API readback proves FR-010 through FR-012, and the wiki pages are
   readable from GitHub.
6. PR #102 remains open at its original head unless changed independently by
   its own automation; this ticket performs no mutation against it.
