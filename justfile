# shellcheck shell=bash

set unstable := true

# List available recipes
default:
    @just --list

# Format all source files
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for i in {1..3}; do
        fourmolu -i src app
    done
    cabal-fmt -i *.cabal
    nixfmt *.nix nix/*.nix

# Check formatting without modifying
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fourmolu -m check src app
    cabal-fmt -c *.cabal

# Run hlint
hlint:
    #!/usr/bin/env bash
    hlint src app

# Build all components
build:
    #!/usr/bin/env bash
    cabal build all -O0

# Full CI pipeline
CI:
    #!/usr/bin/env bash
    set -euo pipefail
    just build
    fourmolu -m check src app
    hlint src app

# --- Client recipes ---

host := "localhost"
port := "8080"
base := "http://" + host + ":" + port

# Launch a new agent session
launch owner repo issue:
    #!/usr/bin/env bash
    curl -s -X POST "{{base}}/sessions" \
      -H "Content-Type: application/json" \
      -d '{"repo":{"owner":"{{owner}}","name":"{{repo}}"},"issue":{{issue}}}' \
      | jq .

# List all active sessions
list:
    #!/usr/bin/env bash
    curl -s "{{base}}/sessions" | jq .

# Stop a session and clean up
stop session_id:
    #!/usr/bin/env bash
    curl -s -X DELETE "{{base}}/sessions/{{session_id}}" | jq .

# Attach to a session terminal via WebSocket
attach session_id:
    #!/usr/bin/env bash
    websocat -b "ws://{{host}}:{{port}}/sessions/{{session_id}}/terminal"
