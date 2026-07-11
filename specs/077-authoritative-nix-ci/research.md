# Research: Authoritative Nix and CI Quality Contract

## Decision 1: One script body, two flake projections

**Decision**: Define each verification script once, build it as a strict-path app, and have a sandboxed `runCommand` check invoke that exact app.

**Rationale**: Exposing a `writeShellApplication` directly as a check only builds the wrapper. Invoking the app from `runCommand` proves the command executes and catches missing runtime inputs.

**Alternatives considered**: Duplicating commands in checks/apps; keeping wrapper-shaped checks and compensating in CI. Both permit local/CI drift.

## Decision 2: Separate dev-shell proof

**Decision**: Keep a named `Dev shell build` job that runs `nix develop --quiet -c cabal build all -O0`, in addition to packaged flake checks.

**Rationale**: Packaged derivations never enter the development shell and cannot prove its package database, tool set, or environment works.

**Alternatives considered**: `nix develop -c true`, which does not exercise Cabal configuration; relying only on `nix flake check`, which proves a different surface.

## Decision 3: Conditional warning-as-error policy

**Decision**: Put only `-Werror` behind manual flag `development-warnings`, default it off for package portability, and explicitly enable it in Nix development/CI.

**Rationale**: This satisfies `cabal check` without weakening strict repository development.

**Alternatives considered**: Removing `-Werror`; leaving it unconditional and ignoring `cabal check`. Both violate the acceptance contract.

## Decision 4: Repository-wide workflow validation

**Decision**: Configure actionlint with custom runner label `nixos`, validate every workflow, and make only shellcheck-driven behavior-neutral fixes outside `ci.yml`.

**Rationale**: The baseline reports eight real findings across three workflows, while issue #78 and #79 own behavior changes to release and docs workflows.

**Alternatives considered**: Lint only `ci.yml`; disable shellcheck; redesign release/docs workflows. Each either weakens the contract or crosses ownership boundaries.

## Decision 5: Exact merge contexts

**Decision**: Require `Build Gate`, `Haskell build and tests`, `Formatting`, `HLint`, `Cabal package validation`, `PureScript UI`, `Workflow lint`, `Dev shell build`, and `Darwin build`.

**Rationale**: These jobs are unconditional on pull requests, cover each acceptance surface, retain the current platform check, and can be observed before ruleset mutation.

**Alternatives considered**: Require only an aggregate `build`; omit Build Gate; include Pages or manual release contexts. Those choices either hide evidence or introduce missing/conditional contexts.

## Decision 6: Preserve uppercase compatibility

**Decision**: Keep `just CI` as an alias to lowercase `just ci`.

**Rationale**: Issue #77 requires lowercase while the current ratified constitution still names uppercase. The alias satisfies both without entering #79 governance scope.

**Alternatives considered**: Delete uppercase now; update the constitution in this ticket. Both violate an existing contract or a sibling boundary.

## Baseline evidence reconciliation

- Flake evaluation reproduced the invalid `haskell-project-plan-to-nix-pkgs.drv` store-path failure.
- `cabal check` reproduced the unconditional `-Werror` rejection.
- The Haskell suite reproduced 55 examples with 0 failures.
- The current `cabal.project` already contains a pinned source-repository stanza; the audit's missing-stanza warning did not reproduce and does not justify an edit by itself.
- Actionlint reproduced eight findings: three unknown `nixos` labels and five Darwin workflow shellcheck findings.
- Ruleset `13867328` currently requires only `build` and retains repository-role bypass actor `5`.
