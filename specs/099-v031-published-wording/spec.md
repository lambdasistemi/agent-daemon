# Specification: describe v0.3.1 as published

**Issue**: #99
**Parent**: #80
**Follow-up**: #95 / PR #96 / release PR #97

## User story

As an operator reading the live release guide after publication, I need truthful
release-state wording so that I know `v0.3.1` is already available and do not
mistake a completed release for a pending one.

## Acceptance target

In the publication-boundary paragraph of `docs/release.md`:

- `v0.3.0` remains immutable, unchanged, and neither rewritten nor deleted.
- `v0.3.1` is described as published with the canonical
  `tmux-ws-0.3.1-aarch64-darwin.tar.gz` Darwin asset and updated Homebrew tap
  formula.
- Restart guidance and the browser-document reload guidance for Chrome tablets
  remain present.
- No text says that `v0.3.1` “will publish” or that this PR does not publish
  it.

## Functional requirements

- **FR-001**: Change only the publication-boundary paragraph in
  `docs/release.md`.
- **FR-002**: Preserve all existing new-install, compatibility, and NixOS
  migration commands outside that paragraph.
- **FR-003**: Establish RED evidence against the stale pre-publication wording
  before editing the guide, then GREEN evidence for the published wording.
- **FR-004**: Strict MkDocs plus the repository-built link/anchor validation
  and `docs-service-contract` must pass.
- **FR-005**: Before review-ready, full local gate and exact-head CI must pass.

## Non-goals and constraints

- Do not bump package or release versions.
- Do not rewrite/delete `v0.3.0`, alter tags/assets, publish a release, or
  mutate the real Homebrew tap.
- Do not modify package, formula, service, UI, Nix module, workflow, or
  release-history behavior.
- GitHub Pages is verified after merge only: the final handoff must require an
  HTTP 200 response containing the corrected wording.

## Success criteria

1. The focused publication wording command fails on the current stale guide and
   passes after the paragraph change.
2. `nix build .#docs .#checks.x86_64-linux.docs-service-contract` passes.
3. `./gate.sh` passes before the implementation commit is accepted.
4. Hosted CI is successful on the final exact PR head.
