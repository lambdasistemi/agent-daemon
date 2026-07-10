# Implementation Plan: Authoritative Nix and CI Quality Contract

**Branch**: `ci/make-nix-checks-and-ci-authoritative` | **Date**: 2026-07-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/077-authoritative-nix-ci/spec.md`

## Summary

Refactor the flake so each verification surface has one strict-path executable used by both a real sandboxed check and a matching local app. Make lowercase `just ci` invoke the complete flake gate plus a representative build from the real development shell. Rebuild GitHub Actions as an orchestration layer over those outputs, retain the existing Darwin build, then update main ruleset `13867328` from the job names observed on pull request #81.

## Technical Context

**Language/Version**: Nix; Cabal 3.0 metadata; Haskell on existing GHC 9.8.4; PureScript registry 72.1.0; GitHub Actions YAML
**Primary Dependencies**: haskell.nix, `writeShellApplication`, `runCommand`, `mkSpagoDerivation`, actionlint, shellcheck, `just`, Cachix
**Storage**: N/A; repository files, Nix store outputs, and GitHub ruleset metadata only
**Testing**: Nix sandbox checks/apps, Cabal build/check/test, fourmolu, cabal-fmt, HLint, purs-tidy, Spago, esbuild, actionlint/shellcheck, guarded PR check snapshots
**Target Platform**: Linux `x86_64-linux` on self-hosted `nixos`; retained `aarch64-darwin` build on macOS 14
**Project Type**: Haskell daemon with a bundled PureScript SPA and Nix-first CI
**Performance Goals**: One cache-warming Build Gate realizes shared closures before downstream Linux jobs; no new application runtime work
**Constraints**: No application/test-semantics/GHC/release/docs behavior change; real sandbox execution; stable always-present job names; preserve ruleset bypass actor `5`
**Scale/Scope**: Seven focused flake check/app surfaces, nine PR job contexts, one ruleset update

## Constitution Check

*GATE: Passed before design and re-checked after slice decomposition.*

- **Type-Safe API**: No endpoint or API type changes.
- **Haskell-First**: Existing GHC remains fixed; Nix and Cabal remain authoritative. Strict warnings remain enabled through an explicit development flag.
- **Separation of Concerns**: No domain or API source changes.
- **WebSocket as First-Class**: The existing 55-example suite, including terminal relay coverage, remains mandatory.
- **CORS Stays as Middleware**: No CORS behavior changes.
- **Quality Gates**: Lowercase `just ci` becomes canonical; uppercase `just CI` remains an alias so the ratified constitution command continues to pass.

No constitution violation or complexity exception is required.

## Architecture

### Check/app construction

`nix/checks.nix` owns one script specification per focused surface. Each specification declares all runtime binaries and one script body. `mkApp` creates a strict-path `writeShellApplication`; `mkCheck` runs that exact app from the flake source inside `runCommand`, supplies a UTF-8 locale where needed, and produces `$out` only after success. `nix/apps.nix` exposes the same app objects under `apps.<system>`.

The public Linux check/app names are:

1. `haskell-build`
2. `haskell-tests`
3. `formatting`
4. `hlint`
5. `cabal-package`
6. `ui`
7. `workflow-lint`

The Haskell test app executes the built `e2e-tests` component and must report all 55 examples. The UI surface realizes lockfile-derived Node modules and exercises lint/build/bundle outputs without runtime network access. The workflow surface runs repository-wide actionlint/shellcheck and, in slice 2, asserts the stable job-name/runner/orchestration contract.

### Cabal warning policy

`agent-daemon.cabal` declares a manual, default-off `development-warnings` flag. Existing warning options remain intact, while `-Werror` is conditional on that flag. `nix/project.nix` explicitly enables the flag for Nix development/CI surfaces. `cabal.project` changes only if a fresh `cabal check` after this correction exposes a concrete source-repository warning; the current baseline already contains the pinned stanza.

### Local gate

The root `justfile` provides lowercase `ci` as the canonical recipe. It runs `nix flake check --no-eval-cache` and a representative `cabal build all -O0` in the development shell entered by `gate.sh`. Uppercase `CI` delegates to lowercase `ci`. Focused existing recipes remain available for debugging.

### CI and ruleset

`.github/workflows/ci.yml` keeps all pull-request jobs unconditional and stable. `Build Gate` realizes the Linux flake checks/apps and development-shell input derivation to warm the shared Nix store. Dependent Linux jobs call focused `nix run .#<name>` apps, except `Dev shell build`, which must separately enter `nix develop` and run `cabal build all -O0`. `Darwin build` retains the current macOS platform exception.

Ruleset mutation is deferred until GitHub reports the exact final job names on pull request #81. Its required contexts then become exactly the nine names in [contracts/quality-contract.md](./contracts/quality-contract.md), while bypass actor `5` remains unchanged.

## RED → GREEN Strategy

- **Slice 1 RED**: Add the executable formatting check first, introduce a temporary Cabal formatting defect, and observe the focused check exit non-zero. Record the diff and failure before restoring the file. The existing invalid dev-shell evaluation and `cabal check` failures are supporting baseline evidence, not substitutes for this deliberate negative test.
- **Slice 1 GREEN**: Restore the Cabal file, complete all seven check/app surfaces and warning policy, then run the focused check, `cabal check`, all 55 tests, actionlint, and `./gate.sh` successfully.
- **Slice 2 RED**: Extend the workflow-lint surface with structural assertions for the nine job names, prescribed runners, dependency on Build Gate, and focused commands; run it against the old CI workflow and observe failure.
- **Slice 2 GREEN**: Replace the CI orchestration, rerun the workflow-lint surface and full `./gate.sh`, then commit only after navigator approval.

## Bisect-Safe Slice Plan

### Slice 1 — Authoritative local and flake contract

**Owned files**: `flake.nix`, `nix/project.nix`, `nix/checks.nix`, `nix/apps.nix`, `justfile`, `agent-daemon.cabal`, `cabal.project`, `.github/actionlint.yaml`, `.github/workflows/darwin-release.yml`.

Deliver real checks/apps, the manual development-warning flag, lowercase local gate/uppercase alias, actionlint runner configuration, and minimal Darwin lint corrections. No CI orchestration rewrite lands here. Commit subject: `ci: make Nix checks authoritative`.

### Slice 2 — Stable GitHub Actions orchestration

**Owned files**: `nix/checks.nix`, `.github/workflows/ci.yml`.

Add the failing structural workflow contract, then make the workflow satisfy it with the Build Gate and eight stable dependent jobs. Commit subject: `ci: align GitHub Actions with flake checks`.

### Slice 3 — Orchestrator-owned finalization

**Owned surfaces**: pull request #81 metadata/checks, `specs/077-authoritative-nix-ci/tasks.md`, ruleset `13867328`, temporary `gate.sh`.

The ticket owner independently reruns the full local gate, verifies all PR contexts and conclusions, updates the ruleset without changing bypass actor `5`, completes task accounting and PR body evidence (including parent epic #80), runs the finalization audit, drops `gate.sh`, pushes, and marks the PR ready. No worker modifies GitHub metadata or pushes.

## Project Structure

```text
flake.nix
nix/
├── project.nix
├── checks.nix
└── apps.nix
justfile
agent-daemon.cabal
cabal.project
.github/
├── actionlint.yaml
└── workflows/
    ├── ci.yml
    ├── darwin-release.yml
    └── pages.yml
specs/077-authoritative-nix-ci/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/quality-contract.md
├── checklists/requirements.md
└── tasks.md
```

**Structure Decision**: Keep `flake.nix` thin; place executable check definitions and app projections in `nix/`. Confine all ticket planning artifacts to the issue-specific specs directory.

## Complexity Tracking

No justified violations.
