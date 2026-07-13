# Public release-surface contract

| Surface | Canonical contract | Compatibility contract | Proof |
|---|---|---|---|
| Cabal/Nix | Package/default executable `tmux-ws`; `tmux-ws --help` | `agent-daemon --help` reaches the same daemon | Packaged check/app |
| Darwin | `tmux-ws-<version>-aarch64-darwin.tar.gz`; `bin/tmux-ws` | Legacy binary only as documented compatibility | Non-publishing layout smoke |
| Homebrew | `brew install lambdasistemi/tap/tmux-ws`; `TmuxWs` | Deprecated `agent-daemon` route | Formula smoke/source guard |
| NixOS | `services.tmux-ws`; `tmux-ws.service` | Legacy option/service migration | Module evaluation |
| Docs | New instructions lead with `tmux-ws` | Separate migration section | Strict docs/name guard |
| Recovery | Exact generated PR with either App identity | No broad bot match | Positive/negative selectors |

`AgentDaemon` source namespaces, browser local-storage keys, and private test
fixture names are explicitly outside this contract.
