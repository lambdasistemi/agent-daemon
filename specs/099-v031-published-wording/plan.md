# Plan: post-publication v0.3.1 wording

## Technical context

The documentation site is built by MkDocs through `flake.nix`; its docs output
runs strict MkDocs plus repository-built HTML link/anchor validation. Existing
`docs-service-contract` protects the release guide's current product and
migration surfaces. Issue #99 needs no application or package change.

## Slice 1 — correct the release-state paragraph

**Owned file**: `docs/release.md` only.

1. Run a focused shell contract that rejects the stale “will publish” and “this
   PR itself does neither” wording. Record its failure as RED.
2. Let the navigator review the RED handoff.
3. Replace only the publication-boundary paragraph with the completed-release
   wording: unchanged `v0.3.0`, published canonical v0.3.1 archive, updated
   Homebrew tap formula, daemon restart, and Chrome-tablet document reload.
4. Run the focused wording contract, strict docs output, and
   `docs-service-contract`; navigator reviews GREEN.
5. Run `./gate.sh`, commit one bisect-safe docs slice, and stop without push.

## Ticket-owner finalization

The owner reviews and gates the committed slice, stamps the task into the same
commit, pushes it to draft PR #100, waits for exact-head CI, audits the PR
body/tasks, removes the temporary `gate.sh`, and waits for final exact-head CI
before marking the PR ready. The merge guard then verifies post-merge GitHub
Pages HTTP 200 and the corrected wording.

## Scope protection

No permanent check is added because the issue explicitly limits the product
change to one documentation paragraph. The temporary PR gate holds the focused
release-state contract during review; it is removed at finalization.
