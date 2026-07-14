# Specification: reproducible Linux release artifacts

**Issue**: #78  
**Parent**: #80  
**Draft PR**: #101

## P1 user story

As a maintainer, I merge a Cabal-planned release proposal and receive one new,
immutable `v<version>` release whose Linux AppImage, DEB, RPM, and checksums
are built from the flake, smoke-tested as installed artifacts, and attached
without rewriting any historical release.

## Reconciled release contract

The older issue wording and the current `main` implementation disagree: current
`main` uses release-please's manifest plus a synchronization workflow, while
the parent invariant says that `tmux-ws.cabal` is the release-version source of
truth. This ticket replaces that manifest/synchronization path with a
Cabal-owned planner. It preserves the already-published `v0.3.1` release and
its sole Darwin asset exactly as-is; no historic tag, release, or asset is
deleted, recreated, or overwritten.

## Functional requirements

- **FR-001**: `tmux-ws.cabal` is the sole version authority. Release planner
  scripts derive, validate, and advance the Cabal version and `CHANGELOG.md`;
  release-please configuration, manifest, and Cabal-sync workflow are absent.
- **FR-002**: A main-branch release-planner workflow uses a short-lived,
  repository-scoped `lambdasistemi-ci` App token. It creates/updates only the
  `release/cabal-release` proposal, then creates one annotated immutable tag
  and its GitHub Release after that proposal merges. Its generated release
  notes come from the matching changelog section.
- **FR-003**: Only an immutable `v*` tag can publish production assets. The
  tag workflow waits for the planner-created release and idempotently uploads
  artifacts; it never deletes or recreates a release. A pull request and every
  default manual dispatch build, smoke-test, and retain workflow artifacts
  only. They do not mutate tags, GitHub Releases, or the Homebrew tap.
- **FR-004**: On `x86_64-linux`, the flake exposes
  `linux-release-artifacts` and `linux-dev-release-artifacts`. Each output
  stages `tmux-ws-<version>-x86_64-linux.AppImage`, `.deb`, `.rpm`, and
  `SHA256SUMS`; it also stages `tmux-ws.AppImage` as the stable latest-download
  name. Dev artifacts add the checked-out short revision to `<version>`.
- **FR-005**: The flake exposes `linux-artifact-smoke`. It copies/extracts
  each AppImage, DEB, and RPM, locates the canonical `tmux-ws` executable, and
  exercises its offline `--help` surface. It must not require a daemon,
  socket, network service, or host-installed package manager state.
- **FR-006**: Bundler inputs and the packaged executable have the flake shape
  required by AppImage/DEB/RPM bundlers: a Linux-only package with
  `meta.mainProgram = "tmux-ws"`, version derived from the Cabal file, and a
  lockfile pin. Darwin remains an `aarch64-darwin` flake system and keeps the
  existing `tmux-ws` Homebrew archive/formula and compatibility route.
- **FR-007**: Linux and Darwin workflows have explicit PR, default-manual, and
  tag modes. Linux artifacts are retained for 30 days at the exact PR head.
  Existing Homebrew publication stays tag-only, non-destructive, App-token
  scoped, and smoke-tested.
- **FR-008**: Flake checks and workflow contracts test the release planner,
  Cabal/changelog/tag consistency, non-destructive publication boundaries,
  artifact names, workflow triggers/modes, action versions, and stable product
  identity.
- **FR-009**: The release guide documents Linux AppImage, DEB, and RPM use,
  names the stable AppImage endpoint, and states the build-only versus
  tag-publication boundary without changing historical-release claims.

## Acceptance criteria

1. `nix build .#linux-release-artifacts` yields the exact versioned AppImage,
   DEB, RPM, `SHA256SUMS`, and stable AppImage names.
2. `nix build .#linux-dev-release-artifacts` uses
   `<cabal-version>-<short-rev>` names, and `nix run .#linux-artifact-smoke`
   passes against both staged output forms with the matching version.
3. `scripts/release/plan` has focused RED/GREEN proof for version selection,
   changelog generation/validation, no-releasable-commit behavior, and
   non-destructive tag/release handling. The planner never uses release-please
   files as an authority.
4. Workflow validation proves PR/default-manual modes cannot publish and tag
   mode only attaches to the existing planner-created release. No workflow
   contains `gh release delete` or release recreation logic.
5. Existing Darwin/Homebrew canonical `tmux-ws` behavior remains covered by
   its artifact/install smoke and the old `agent-daemon` route remains bounded
   compatibility only.
6. Full local gate, flake check, Linux artifact build/smoke, workflow lint,
   and exact-head hosted PR checks are green before handoff.

## Non-goals and safety constraints

- Do not publish, merge, close #78, delete, retag, recreate, or modify
  `v0.3.1` or any other historical release/tag/asset.
- Do not change application, API, UI, NixOS service, public executable, or
  compatibility behavior beyond packaging/release mechanics.
- Do not upgrade GHC, add Alpine/musl support, or alter repository governance,
  Pages, wiki, or broad onboarding documentation owned by #79.
- Do not use a PAT, deploy key, or persistent tap token; use only scoped
  short-lived GitHub App tokens where a workflow needs write authority.
