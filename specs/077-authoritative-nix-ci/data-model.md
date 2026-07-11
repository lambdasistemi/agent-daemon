# Quality Contract Model

This ticket changes no application data. The relevant entities are repository-quality contract records.

## Quality Surface

- **Name**: Stable focused identifier such as `formatting` or `ui`.
- **App**: Strict-path executable used for focused local/CI execution.
- **Check**: Sandboxed derivation that invokes the same app.
- **Evidence**: Exit status plus surface-specific output, such as 55 examples and 0 failures.

## CI Job

- **Job ID**: Internal workflow identifier.
- **Context name**: Stable human-visible name reported to GitHub.
- **Runner**: `nixos` for Linux or macOS 14 for Darwin.
- **Dependency**: Linux substantive jobs depend on `build-gate`.
- **Command**: Focused flake app, representative dev-shell build, or retained Darwin build.
- **Presence rule**: Unconditional on every pull request to `main`.

## Ruleset Contract

- **Ruleset ID**: `13867328`.
- **Required contexts**: Exact set of nine observed CI context names.
- **Strict policy**: Preserve the existing value unless the ticket explicitly requires otherwise.
- **Bypass actor**: ID `5`, type `RepositoryRole`, mode `always`.

## State Transitions

1. Baseline quality surface is missing, wrapper-only, or failing.
2. Focused RED evidence proves the new check can reject a representative defect.
3. Focused GREEN and full local gate prove the restored contract.
4. Draft PR reports all stable jobs successfully.
5. Ruleset required contexts are replaced with the observed exact set.
6. Final gate/audit pass and the PR moves from draft to ready.
