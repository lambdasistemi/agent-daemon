# Verification quickstart

Run these commands after the relevant slice is green:

```bash
nix build --quiet .#default
./result/bin/tmux-ws --help
./result/bin/agent-daemon --help
nix run --quiet .#workflow-lint
nix run --quiet .#release-product-name
nix build --quiet .#docs
./gate.sh
```

The Darwin pull-request proof must validate the archive/formula path without
`gh release upload`, tap push, tag/release creation, or any v0.3.0 mutation.
