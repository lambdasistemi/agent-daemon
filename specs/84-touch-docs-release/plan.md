# Plan: Touch documentation and v0.2.0 release

## Baseline

- Repository head: `a962710`.
- Current formal release: `v0.1.1` at `d832720`.
- Current Pages deployment: green at `a962710`.
- Current manual Darwin release creates an archive but failed its smoke path.

## Slice 1 — operator documentation

Update `README.md`, the MkDocs user/deployment/Tailscale pages, and
`mkdocs.yml`. Describe current touch behavior and reboot persistence without
embedding development-host-specific secrets or URLs. Build the combined SPA +
documentation site as proof.

## Slice 2 — deterministic release automation

Add release-please manifest/config files from the `0.1.1` baseline, a release
workflow using the organization CI GitHub App, a Cabal-version synchronizer,
and a CI drift check. Convert the Darwin publisher into a reusable/recoverable
tag publisher. Its bundle must mirror Homebrew's installed layout and smoke
before upload; existing releases must fail closed rather than be deleted.

## Publication sequence

1. Merge this issue PR with green CI.
2. Let release-please open/update the `v0.2.0` release PR.
3. Verify Cabal/manifest synchronization and green required checks.
4. Merge the release PR; verify tag, release, asset, formula, and Pages.
5. Open a separate infrastructure change that pins the development service to
   the release revision, then deploy and smoke it without rebooting.

## Verification

- `./gate.sh`
- `nix build --no-link .#site`
- JSON/YAML/actionlint checks through the flake-owned workflow lint gate
- GitHub required checks on both the implementation and release PRs
- Post-release `gh release`, asset checksum, formula, and live service probes
