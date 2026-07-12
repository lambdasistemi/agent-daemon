# Specification: rebase-safe release recovery

## Outcome

Release publication remains safe and automatic when Release Please cannot
recognize a rebased generated release PR, and Darwin bundling correctly ignores
only a copied dylib's own install ID.

## Requirements

- Release Please remains the primary release creator.
- A fallback may create a release only when the pushed main SHA is associated
  with a merged generated release PR and PR title, manifest, Cabal version,
  changelog, and missing tag all agree.
- Existing tags/releases and ordinary main pushes remain no-ops.
- The resolved release outputs drive the existing Darwin publisher.
- Recursive Darwin dependency scanning skips a staged dylib's self install ID
  but still rejects unresolved dependency install names.
- The flake-owned workflow contract covers the safety guards and self-ID rule.

## Live evidence

- Release run 29192687901 skipped v0.2.0 and opened false PR #88 after rebase.
- Darwin run 29192773902 failed on `libz.dylib` self ID `@rpath/libz.dylib`.
