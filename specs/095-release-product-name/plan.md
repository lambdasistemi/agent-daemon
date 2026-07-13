# Implementation Plan: tmux-ws public release identity

**Branch**: `fix/95-release-product-name` | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

Replace the public package/executable/archive/formula/service identity with
`tmux-ws`, preserve a bounded `agent-daemon` compatibility path, and make
flake-owned release/docs checks reject regressions. Work is three serial slices
because `nix/checks.nix` protects every later release and documentation surface.

## Technical Context

**Language/Version**: Nix, Cabal/Haskell GHC 9.8.4, Bash, Ruby formula text, Markdown/YAML
**Primary Dependencies**: haskell.nix, release-please, GitHub App tokens, Homebrew, MkDocs
**Testing**: Flake checks/apps, Cabal build, strict MkDocs, actionlint/shellcheck, Darwin CI package smoke
**Target Platform**: Linux Nix verification and macOS 14 Darwin/Homebrew verification
**Constraints**: no merge/publish/tag mutation; preserve v0.3.0 and internal namespaces/keys

## Constitution Check

Pass. No API, WebSocket, terminal, UI, or data-model change is planned. The
existing quality gate is strengthened through flake-owned checks, strict docs,
and a separate real development-shell build.

## Compatibility Decision

The primary package, executable, default flake app, Darwin archive, formula,
and NixOS service are `tmux-ws`. This corrective patch ships a tested
`agent-daemon` command alias plus deprecated legacy formula/service route.
Documentation names the replacement and states that removal needs a separately
reviewed migration ticket. The compatibility path is never a new-install path.

## Source Areas

- Cabal/Nix: `agent-daemon.cabal` → `tmux-ws.cabal`, `nix/project.nix`,
  `nix/checks.nix`, `nix/apps.nix`, `nix/module.nix`, and `flake.nix` only when
  output wiring requires it.
- Release: `.github/workflows/darwin-release.yml`,
  `.github/workflows/release.yml`, and sync workflow only if manifest rename
  requires it.
- Docs: `README.md`, `docs/index.md`, `docs/deployment.md`,
  `docs/tailscale.md`, new `docs/release.md`, and `mkdocs.yml`.

## Slice 1 — Canonical package and executable

**Commit**: `fix(package): make tmux-ws the canonical executable`
**Tasks**: T001, T002, T003

1. Driver writes focused RED package assertions that fail because the baseline
   default output and help command are `agent-daemon`.
2. Driver changes only public package/executable wiring so default package/app
   are `tmux-ws`, while `agent-daemon` remains a tested compatibility executable
   invoking the same daemon entry point. No module or browser-key rename.
3. Navigator requires captured RED output, Green packaged commands for both
   names, Cabal validation, focused flake app/check, and `./gate.sh` before one
   commit.

## Slice 2 — Darwin, Homebrew, and release recovery

**Commit**: `fix(release): publish tmux-ws distribution surfaces`
**Tasks**: T004, T005, T006

1. Driver adds RED checks for legacy archive/binary/formula names and missing
   `app/lambdasistemi-ci` author recognition, with positive and negative
   selector data rather than source grep alone.
2. Driver makes Darwin generate canonical archive and `TmuxWs` formula, retains
   a deprecated `agent-daemon` formula route and all dylib/layout hardening,
   and keeps publication gated to a real immutable tag.
3. Driver adds/factors a non-publishing macOS-equivalent package/formula smoke
   for archive contents, canonical help, and primary Homebrew install without
   upload or tap mutation. Recovery accepts exactly both App forms and retains
   all other guards.

## Slice 3 — Service migration, docs, and current-surface guard

**Commit**: `docs: lead operators with tmux-ws`
**Tasks**: T007, T008, T009, T010

1. Driver records a RED current-surface/docs guard that distinguishes allowed
   migration text from new-install guidance and private identifiers.
2. Driver exposes `tmux-ws` as primary NixOS option/service while retaining an
   evaluated legacy route; it documents exact conversion and removal policy.
3. Driver updates every current operator/install/deployment/Tailscale surface,
   adds a release guide, leads all new paths with `tmux-ws`, adds migration
   guidance, and enables strict docs/link/anchor validation.
4. Navigator requires strict docs proof, module compatibility proof, focused
   naming/release check, and full `./gate.sh` before one commit.

## Verification Plan

- Every slice captures a real RED failure before the smallest Green change.
- Focused commands cover packaged `tmux-ws --help`, legacy alias,
  release-product-name check, workflow lint, and strict docs build.
- `./gate.sh` is full repository evidence: `git diff --check`,
  `nix flake check --no-eval-cache`, and
  `nix develop --quiet -c cabal build all -O0`.
- The PR remains draft until local gate, exact-head hosted CI, Darwin
  non-publishing proof, formula smoke, and docs proof are recorded.

## Release Procedure After Merge

1. Confirm v0.3.0 tag, release, and historical asset remain unchanged.
2. Let release-please open the next patch PR; verify generated version,
   changelog, and installation/deployment links.
3. Epic owner merges that generated release PR, creating the new immutable tag.
4. Invoke Darwin publication only with the new tag; verify archive, primary
   formula/smoke, and deprecated legacy formula route.
5. Record release URL, digest, formula commit, and migration evidence on #95/#80.
