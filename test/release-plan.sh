#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'release-plan test: %s\n' "$*" >&2
  exit 1
}

expect_fail() {
  local description="$1"
  shift
  if "$@" >"$tmp/expected-failure.out" 2>&1; then
    fail "expected failure: $description"
  fi
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq "$needle" "$file" || fail "missing $needle in $file"
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  if grep -Fq "$needle" "$file"; then
    fail "unexpected $needle in $file"
  fi
}

for script in get-cabal-version extract-notes check-version-consistency plan; do
  test -x "$root/scripts/release/$script" \
    || fail "missing executable scripts/release/$script"
done

version="$(bash "$root/scripts/release/get-cabal-version")"
test "$version" = 0.3.1 || fail "expected Cabal version 0.3.1, got $version"

notes="$tmp/notes.md"
bash "$root/scripts/release/extract-notes" "$version" > "$notes"
test -s "$notes" || fail 'matching changelog notes are empty'
expect_fail 'missing changelog section' \
  bash "$root/scripts/release/extract-notes" 9.9.9

make_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts"
  cp "$root/tmux-ws.cabal" "$root/CHANGELOG.md" "$repo/"
  cp -R --no-preserve=mode "$root/scripts/release" "$repo/scripts/"
  git -C "$repo" init --quiet --initial-branch main
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" add .
  git -C "$repo" commit --quiet -m 'chore: baseline release'
  git -C "$repo" tag -a v0.3.1 -m 'Release v0.3.1'
}

bash "$root/scripts/release/check-version-consistency" --mode proposal
runner_minimal_bin="$tmp/runner-minimal-bin"
mkdir "$runner_minimal_bin"
for command in env bash dirname; do
  ln -s "$(command -v "$command")" "$runner_minimal_bin/$command"
done
expect_fail 'runner-minimal direct consistency command lacks awk' \
  env PATH="$runner_minimal_bin" \
  "$root/scripts/release/check-version-consistency" --mode proposal
assert_contains 'nix run --quiet .#release-consistency' "$root/.github/workflows/ci.yml"
assert_not_contains 'run: scripts/release/check-version-consistency --mode proposal' \
  "$root/.github/workflows/ci.yml"
assert_contains 'release-consistency = {' "$root/nix/checks.nix"
assert_contains 'bash scripts/release/check-version-consistency --mode proposal' \
  "$root/nix/checks.nix"
assert_contains 'bash scripts/release/get-cabal-version' \
  "$root/nix/checks.nix"
assert_contains 'bash scripts/release/check-version-consistency "$@"' \
  "$root/nix/checks.nix"

reject_repo="$tmp/reject"
make_repo "$reject_repo"
printf '{}\n' > "$reject_repo/release-please-config.json"
# shellcheck disable=SC2016
expect_fail 'release-please artifacts are rejected' \
  bash -c 'cd "$1" && exec bash scripts/release/check-version-consistency --mode proposal' \
  _ "$reject_repo"

proposal_repo="$tmp/proposal"
make_repo "$proposal_repo"
printf 'proposal fixture\n' > "$proposal_repo/feature.txt"
git -C "$proposal_repo" add feature.txt
git -C "$proposal_repo" commit --quiet -m 'feat: add release planner fixture'
bash "$proposal_repo/scripts/release/plan" --dry-run > "$tmp/proposal.out"
assert_contains 'proposal version=0.4.0' "$tmp/proposal.out"
assert_contains 'release/cabal-release' "$tmp/proposal.out"
test "$(git -C "$proposal_repo" branch --show-current)" = main \
  || fail 'dry-run changed the checked-out branch'
test "$(git -C "$proposal_repo" status --porcelain)" = '' \
  || fail 'dry-run changed the proposal fixture'

publish_repo="$tmp/publish"
make_repo "$publish_repo"
sed -i 's/^version:[[:space:]]*0\.3\.1/version:         0.4.0/' \
  "$publish_repo/tmux-ws.cabal"
{
  head -n 1 "$publish_repo/CHANGELOG.md"
  printf '\n## [0.4.0] (test)\n\n### Features\n\n- planner fixture\n\n'
  tail -n +2 "$publish_repo/CHANGELOG.md"
} > "$publish_repo/CHANGELOG.next"
mv "$publish_repo/CHANGELOG.next" "$publish_repo/CHANGELOG.md"
git -C "$publish_repo" add tmux-ws.cabal CHANGELOG.md
git -C "$publish_repo" commit --quiet -m 'chore: release 0.4.0'
git -C "$publish_repo" init --bare --quiet "$tmp/publish-remote.git"
git -C "$publish_repo" remote add origin "$tmp/publish-remote.git"
git -C "$publish_repo" push --quiet -u origin main --tags

mock_bin="$tmp/mock-bin"
mkdir "$mock_bin"
printf '#!%s\n' "$(command -v bash)" > "$mock_bin/gh"
cat >> "$mock_bin/gh" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  'pr list') printf '[{"mergedAt":"2026-07-14T00:00:00Z"}]\n' ;;
  'release view') test -e "$GH_RELEASE_EXISTS" ;;
  'release create') touch "$GH_RELEASE_EXISTS" ;;
  *) printf 'unexpected gh command: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$mock_bin/gh"
GH_LOG="$tmp/gh.log" GH_RELEASE_EXISTS="$tmp/release-exists" PATH="$mock_bin:$PATH" \
  bash "$publish_repo/scripts/release/plan" > "$tmp/publish.out"
git -C "$publish_repo" rev-parse -q --verify refs/tags/v0.4.0 >/dev/null \
  || fail 'planner did not create the annotated release tag'
assert_contains 'release create v0.4.0' "$tmp/gh.log"
assert_not_contains 'release delete' "$tmp/gh.log"

before="$(grep -Fc 'release create v0.4.0' "$tmp/gh.log")"
GH_LOG="$tmp/gh.log" GH_RELEASE_EXISTS="$tmp/release-exists" PATH="$mock_bin:$PATH" \
  bash "$publish_repo/scripts/release/plan" > "$tmp/publish-repeat.out"
after="$(grep -Fc 'release create v0.4.0' "$tmp/gh.log")"
test "$before" = "$after" || fail 're-running publication created a release'

for workflow in .github/workflows/release.yml .github/workflows/darwin-release.yml; do
  assert_contains 'pull_request:' "$root/$workflow"
  assert_contains 'workflow_dispatch:' "$root/$workflow"
  assert_contains "github.event_name == 'push'" "$root/$workflow"
  assert_not_contains 'gh release delete' "$root/$workflow"
  assert_not_contains 'gh release create' "$root/$workflow"
done
linux_workflow="$root/.github/workflows/release.yml"
# shellcheck disable=SC2016
assert_contains \
  'test "${GITHUB_REF_NAME#v}" = "$(nix run --quiet .#release-consistency -- --version)"' \
  "$linux_workflow"
assert_contains 'nix run --quiet .#release-consistency -- --mode publish' \
  "$linux_workflow"
# shellcheck disable=SC2016
assert_contains \
  'nix run .#linux-artifact-smoke -- --artifacts-dir "$(readlink -f result)" --artifact-version "$(nix run --quiet .#release-consistency -- --version)"' \
  "$linux_workflow"
# shellcheck disable=SC2016
assert_not_contains '$(scripts/release/get-cabal-version)' "$linux_workflow"
assert_not_contains 'scripts/release/check-version-consistency --mode publish' \
  "$linux_workflow"
assert_not_contains 'nix run .#linux-artifact-smoke -- result' "$linux_workflow"
assert_contains 'actions/create-github-app-token@v1' \
  "$root/.github/workflows/release-plan.yml"
assert_contains 'scripts/release/plan' "$root/.github/workflows/release-plan.yml"
assert_not_contains 'release-please' "$root/.github/workflows/release-plan.yml"
for obsolete in \
  .github/workflows/sync-cabal-version.yml \
  release-please-config.json \
  .release-please-manifest.json; do
  test ! -e "$root/$obsolete" || fail "obsolete release-please artifact remains: $obsolete"
done

printf 'release-plan tests passed\n'
