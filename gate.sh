#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c just ci
nix build --quiet --no-link .#docs .#site
nix run --quiet .#workflow-lint
nix run --quiet .#docs-service-contract

site="$(nix build --quiet --no-link --print-out-paths .#site)"
port=4179
preview_probe="$(mktemp -d)"
nix develop --quiet -c python3 -m http.server "$port" \
  --bind 127.0.0.1 --directory "$site" >/tmp/tmux-ws-docs-preview.log 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  rm -rf "$preview_probe"
}
trap cleanup EXIT

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$port/" >/dev/null; then
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:$port/" -o "$preview_probe/root.html"
curl -fsS "http://127.0.0.1:$port/docs/" -o "$preview_probe/docs.html"
grep -Fq 'tmux-ws' "$preview_probe/root.html"
grep -Fq 'tmux-ws' "$preview_probe/docs.html"
