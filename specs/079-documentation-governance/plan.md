# Plan: documentation and repository governance

## Technical context

Post-PR-101 `main` already builds `packages.docs` with strict MkDocs and an
internal HTML link/anchor checker, then combines the SPA and docs under
`packages.site`. The current Pages workflow deploys only from `main`, has no PR
preview lifecycle, uses stale action versions, and runs its deploy job on
Ubuntu. `nix/checks.nix` already exposes workflow validation as both a real
flake check and an app, so the permanent workflow contract belongs there.

The README and site already contain the touch command deck and close-current
concepts, but onboarding is incomplete and `docs/release.md` still describes
Linux artifacts as future/PR-specific despite merged PR #101. The constitution
still describes the historical Haskell-only agent-daemon. External repository
readback confirms empty topics, legacy metadata, automated security fixes off,
all three merge modes enabled, branch deletion off, and no docs context in the
active `main` ruleset.

All tracked workflow/documentation changes are executed by the persistent
Codex-driver/Claude-navigator panes after both are cleared for each slice. The
ticket owner writes only the specification artifacts, temporary gate, worker
briefs, external GitHub mutations, evidence artifact, and PR metadata.

## Slice 1 — strict documentation delivery and preview lifecycle

**Owned files**: `.github/workflows/pages.yml`, `nix/checks.nix`.

1. Add focused workflow-contract assertions first and observe RED against the
   current main-only Pages workflow.
2. Convert the workflow to opened/synchronize/reopened/closed PR handling, an
   always-present `Docs build` job on `nixos`, shared static-preview publish,
   `nixos` cleanup, and `nixos` Pages deployment from `main`/manual runs.
3. Preserve `packages.site` as the single built artifact and Pages workflow
   mode; use current prescribed action versions and no external preview secret.
4. Green the focused workflow check, actionlint, full flake check, strict docs
   build, localhost preview smoke, and temporary gate.

**Commit**: `ci: add strict documentation preview lifecycle`
**Tasks trailer**: `Tasks: T001, T002, T003, T004`

## Slice 2 — accurate touch-first onboarding and release guidance

**Owned files**: `README.md`, `mkdocs.yml`, `docs/index.md`,
`docs/installation.md` (new), `docs/usage.md` (new),
`docs/development.md` (new), `docs/release.md`, `nix/checks.nix`.

1. Extend the docs service contract first so it rejects missing macOS/Linux,
   v0.4.0, checksum/package-manager, touch deck, verification, stable-link,
   license, and navigation requirements; observe RED.
2. Rewrite the README as a concise reviewer-facing landing page with accurate
   installation, touch use, development/verification, docs, releases, and
   license routes.
3. Build coherent user/operator/developer navigation and OS-aware remembered
   palettes with search/path/sections/indexes/TOC/code-copy features.
4. Add dedicated installation, touch usage, and development pages while
   preserving accurate deployment/Tailscale/design pages and avoiding
   duplicate or contradictory guidance.
5. Describe the imminent (not yet published) v0.4.0 Linux artifacts and stable
   release route accurately, including checksum/AppImage/apt/dnf/Homebrew/NixOS
   install and upgrade/restart/tablet hard-refresh guidance. Do not mention the
   delivery PR as a publication boundary and do not touch PR #102.
6. Green focused contracts, strict MkDocs/link checks, localhost smoke, and the
   full temporary gate.

**Commit**: `docs: complete touch-first installation and operation guides`
**Tasks trailer**: `Tasks: T005, T006, T007, T008, T009, T010`

## Slice 3 — current constitution and portable Speckit scaffold

**Owned files**: `.specify/memory/constitution.md` and deletion of every
tracked `.claude/commands/speckit.*.md` file.

1. Record RED showing the constitution's obsolete Agent Daemon/Haskell-only
   contract and the tracked command copies.
2. Replace it with the actual Haskell/PureScript, Nix-first, test/live-boundary,
   release, runner, linear-history, and governance principles.
3. Remove only the explicitly approved tracked Speckit command copies; preserve
   the portable `.specify/` scaffold and unrelated agent guidance.
4. Green focused content/absence assertions and the full temporary gate.

**Commit**: `docs: align the constitution and Speckit scaffold`
**Tasks trailer**: `Tasks: T011, T012, T013, T014`

## Slice 4 — repository wiki logbook

**External repository**: `lambdasistemi/tmux-ws.wiki.git`.
**Owned files**: `Home.md`, `_Sidebar.md`, `Logbook-July-2026.md`.

1. A cleared driver/navigator pair clones or refreshes an isolated wiki
   checkout, establishes RED for the missing current logbook navigation, and
   writes the three pages with links to #80, #79, and PR #103.
2. The navigator reviews RED/GREEN and the wiki commit. The driver stops without
   push; the ticket owner verifies and pushes the wiki commit, then reads the
   pages back from GitHub.

**Commit**: `docs: initialize the repository-hardening logbook`

## Ticket-owner governance and evidence slice

After Slice 1 has produced the real `Docs build` context and all content pushes
have exercised preview update-in-place:

1. Set description, homepage, topics, rebase-only merge mode, and delete-branch
   policy; enable automated security fixes while preserving vulnerability
   alerts.
2. Read the active main ruleset, preserve all existing rules/bypasses/contexts,
   add only `Docs build`, update it, and read it back.
3. Exercise the draft PR's close cleanup and reopen recreation; verify preview
   create/update/delete via PR comments, workflow runs, and HTTP responses.
4. Write `governance-evidence.md` under this spec directory with exact URLs,
   head SHAs, run ids, preview/comment observations, wiki readback, repository
   settings/ruleset JSON summaries, and PR #102 non-mutation readback.
5. Stamp T015–T021 into the evidence commit, update the living PR body, rerun
   the full gate and finalization audit, verify exact-head hosted checks, drop
   `gate.sh`, and wait for the new exact-head checks before marking ready.

No merge, tag, release, Homebrew mutation, or worktree cleanup occurs here.
