# Specification: Touch documentation and v0.2.0 release

## P1 user story

As a tablet operator, I follow the published tmux-ws documentation, install
the latest release, and observe the same touch-first, reboot-persistent
behavior as the deployed service.

## User-visible requirements

1. The manual explains the tablet action dock without assuming a keyboard or
   mouse.
2. The manual names the selected session and window and explains the guarded
   close-current pane/window flow, including its confirmation and topology
   checks.
3. Refresh is distinguished from a full document reload; operators are told
   how no-store responses prevent stale Chrome assets.
4. NixOS deployment for an existing tmux user includes a reboot-stable tmux
   socket location and persistent Tailscale Serve routing.
5. Documentation supports both light and dark color schemes.

## Release requirements

1. Release state is manifest-driven from the existing `v0.1.1` baseline.
2. Unreleased `feat:` commits produce the pre-1.0 minor release `v0.2.0`.
3. The Cabal PVP version is kept equal to the manifest SemVer version.
4. Publishing never deletes an existing tag or release.
5. The macOS archive uses its installed directory layout during the smoke
   test, including `libexec/lib`, before upload.
6. The Homebrew test explicitly trusts the organization tap and fails on an
   unusable binary.
7. CI, Pages, the GitHub release, release asset, and Homebrew formula are all
   verified after publication.

## Non-goals

- Product or API behavior changes.
- Hackage, Windows, or container publication.
- Rebooting the development host.
- Releasing from an unmerged feature branch.

## Success criteria

- A reader can operate tmux-ws on a keyboardless tablet from the public
  manual.
- The release automation creates `v0.2.0` once and publishes a smoke-tested
  macOS archive.
- The development service can subsequently be pinned to and deployed from the
  released revision.
