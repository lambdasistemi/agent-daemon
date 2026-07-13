# Changelog

## [0.4.0](https://github.com/lambdasistemi/tmux-ws/compare/v0.3.0...v0.4.0) (2026-07-13)


### Features

* add --host option to bind to specific address ([1817c9a](https://github.com/lambdasistemi/tmux-ws/commit/1817c9abe4a47ed86c6be37b60faee8e5bace7fb))
* add aarch64-darwin build to CI ([800769d](https://github.com/lambdasistemi/tmux-ws/commit/800769d2877c1633ce09fdefd1dfd390a6ebb368))
* add browser session manager UI ([#66](https://github.com/lambdasistemi/tmux-ws/issues/66)) ([c6e3434](https://github.com/lambdasistemi/tmux-ws/commit/c6e343463c617de8f5742477ea7d38e01911a875))
* add browser terminal client with xterm.js ([f1614e8](https://github.com/lambdasistemi/tmux-ws/commit/f1614e82d763f732c5e4d19e4497cf0ce5d98bdd)), closes [#16](https://github.com/lambdasistemi/tmux-ws/issues/16)
* add CLI client recipes and websocat dependency ([f344883](https://github.com/lambdasistemi/tmux-ws/commit/f34488341ec957839f4600f9f9ea56b983edd27f)), closes [#11](https://github.com/lambdasistemi/tmux-ws/issues/11)
* add core types ([54fec6d](https://github.com/lambdasistemi/tmux-ws/commit/54fec6dc60e686c34e2baad42e0d72ec122472c8))
* add CORS support and GitHub Pages deployment ([322cbd2](https://github.com/lambdasistemi/tmux-ws/commit/322cbd22b3e1c898a6e5ef683d38d0acf4975d9d))
* add darwin cache spider workflow ([f00d033](https://github.com/lambdasistemi/tmux-ws/commit/f00d0332ad5a3467188ffd9bba47479c2c3a1daf))
* add error handling for subprocess calls ([bef8054](https://github.com/lambdasistemi/tmux-ws/commit/bef80543562faa3cec735006cdf6faa3d20c52cd)), closes [#5](https://github.com/lambdasistemi/tmux-ws/issues/5)
* add GET /branches and DELETE /branches/:repo/:branch endpoints ([2c18e38](https://github.com/lambdasistemi/tmux-ws/commit/2c18e38f428c86a872463c1b2c2b22434e3eb6c2))
* add GET /worktrees endpoint ([32b94b1](https://github.com/lambdasistemi/tmux-ws/commit/32b94b1211d05aa9193bb0803d7f19e14f64a89e)), closes [#32](https://github.com/lambdasistemi/tmux-ws/issues/32)
* add local paste snippets ([#67](https://github.com/lambdasistemi/tmux-ws/issues/67)) ([43ec6d5](https://github.com/lambdasistemi/tmux-ws/commit/43ec6d50a271d4dcfd0934f5d80eadada1aa98b7))
* add main entry point ([3c08479](https://github.com/lambdasistemi/tmux-ws/commit/3c084793629905443525918d02275526fc3b0123))
* add paste enter controls ([#68](https://github.com/lambdasistemi/tmux-ws/issues/68)) ([0cc3b6b](https://github.com/lambdasistemi/tmux-ws/commit/0cc3b6b3e45705ea991c59667d719400407ba9ef))
* add REST API and WebSocket handler ([65308b0](https://github.com/lambdasistemi/tmux-ws/commit/65308b01142cbaaa49b8232dd334a78b4d3de373))
* add terminal copy controls ([#70](https://github.com/lambdasistemi/tmux-ws/issues/70)) ([036fe44](https://github.com/lambdasistemi/tmux-ws/commit/036fe44aa7856abdcd415bce05e0f975fd993bdc))
* add tmux and worktree managers ([0bd1170](https://github.com/lambdasistemi/tmux-ws/commit/0bd117050a2194101a4d7989ddeff6998d56e296))
* add touch close-current actions ([e1dcd53](https://github.com/lambdasistemi/tmux-ws/commit/e1dcd533edba0c2a0a75c162128ac9cbd4250173))
* add touch terminal command deck ([6e75f3f](https://github.com/lambdasistemi/tmux-ws/commit/6e75f3fdef6fd387afa909f95041b942d2c4a7c2))
* add touch terminal selection ([#71](https://github.com/lambdasistemi/tmux-ws/issues/71)) ([0aff8ca](https://github.com/lambdasistemi/tmux-ws/commit/0aff8ca072dbc0ccf14ec10e23821a6bea62a06e))
* close current tmux contexts safely ([c1d0e56](https://github.com/lambdasistemi/tmux-ws/commit/c1d0e5613a707b140c968f207aafd34252391399))
* collapse paste editor ([#69](https://github.com/lambdasistemi/tmux-ws/issues/69)) ([9c3e03f](https://github.com/lambdasistemi/tmux-ws/commit/9c3e03f0f2be698c5f11f8e65c93585f986549f5))
* darwin release workflow with homebrew tap ([f5595d1](https://github.com/lambdasistemi/tmux-ws/commit/f5595d190dd4fcef3884ab071839289c85bd587f))
* expose agent-daemon as a NixOS module ([f2121b3](https://github.com/lambdasistemi/tmux-ws/commit/f2121b35aed8d8f909d52013c9eec43763b53502)), closes [#20](https://github.com/lambdasistemi/tmux-ws/issues/20)
* expose close-current API actions ([63656be](https://github.com/lambdasistemi/tmux-ws/commit/63656be7e6a7b75fa50b43e7108c3a101d42ce82))
* implement PTY terminal relay via posix-pty ([90ec281](https://github.com/lambdasistemi/tmux-ws/commit/90ec281181303bac6295522232bf9b452a7a3f7e))
* model close-current transitions ([4b8bd14](https://github.com/lambdasistemi/tmux-ws/commit/4b8bd14fa12bf331f068e12dcc2fee43d29e500c))
* model terminal command deck input ([d443b6b](https://github.com/lambdasistemi/tmux-ws/commit/d443b6b7b00cb3bcd8e304286484998d9d5df940))
* pass issue context to Claude on session launch ([2eaf836](https://github.com/lambdasistemi/tmux-ws/commit/2eaf836b037b65ac82b5535a9c9f932188467339)), closes [#7](https://github.com/lambdasistemi/tmux-ws/issues/7)
* recover sessions from running tmux on startup ([104deb3](https://github.com/lambdasistemi/tmux-ws/commit/104deb3b8c6999d3b53a05911c03e6ac7959b2f5)), closes [#6](https://github.com/lambdasistemi/tmux-ws/issues/6)
* store prompt and track last activity in sessions ([3e920b8](https://github.com/lambdasistemi/tmux-ws/commit/3e920b87637bf5793207f48e91ce01cc43eb0b67)), closes [#39](https://github.com/lambdasistemi/tmux-ws/issues/39)
* **ui:** make workspace touch-first ([63e1e37](https://github.com/lambdasistemi/tmux-ws/commit/63e1e3765174113d2bc4ba10de559fe48bd50576))


### Bug Fixes

* add Access-Control-Allow-Private-Network CORS header ([d5f45b9](https://github.com/lambdasistemi/tmux-ws/commit/d5f45b95fdffd408e85642b3ee736f239297c290))
* add createUser option to avoid conflicts with existing users ([02ac799](https://github.com/lambdasistemi/tmux-ws/commit/02ac799cf43cc3a99ed72e3befa72b4720d7825e))
* add serve recipe and show curl errors ([ec8278a](https://github.com/lambdasistemi/tmux-ws/commit/ec8278a804d3bbb5d19f0282c0a0b6293ebd6785))
* add sshAuthSock option to NixOS module ([1815218](https://github.com/lambdasistemi/tmux-ws/commit/1815218bb27d72dfd4e4b8f44e66528dd9a85acd))
* apply fourmolu formatting and hlint suggestions ([b09cbad](https://github.com/lambdasistemi/tmux-ws/commit/b09cbad402581c312a21daa86ccee93f7446a640))
* **ci:** isolate hosted runner verification ([306cb26](https://github.com/lambdasistemi/tmux-ws/commit/306cb26e2d8c142cc0c39184cdebc46ee704ccc4))
* clear screen on detach from terminal ([ef9ac71](https://github.com/lambdasistemi/tmux-ws/commit/ef9ac71e8135e453ab31b04b68c587f53294081b))
* complete public app and CORS cleanup ([#73](https://github.com/lambdasistemi/tmux-ws/issues/73)) ([d832720](https://github.com/lambdasistemi/tmux-ws/commit/d832720be004e396218d5bad2a273551280dd39a))
* detect default branch instead of hardcoding main ([0246e2f](https://github.com/lambdasistemi/tmux-ws/commit/0246e2ffdfe804c42ae36c5b032b759930e2fe0f))
* enable mermaid rendering in MkDocs site ([99f33bb](https://github.com/lambdasistemi/tmux-ws/commit/99f33bb2472f0a1320a6e5476a5ee278526830ed)), closes [#24](https://github.com/lambdasistemi/tmux-ws/issues/24)
* flatten JSON encoding for SessionId and SessionState ([d22e090](https://github.com/lambdasistemi/tmux-ws/commit/d22e09029cc805ab55f641286af27a6525349c70))
* handle existing worktrees and branches on launch ([c10e828](https://github.com/lambdasistemi/tmux-ws/commit/c10e8280a527881fc9ba4d7dfa6dd3fe9eec0f26))
* install dylibs to libexec to avoid homebrew conflicts ([8853da6](https://github.com/lambdasistemi/tmux-ws/commit/8853da6eda416360892ab0a5b3c39e020d919a57))
* keep signal handling in raw terminal mode ([736737f](https://github.com/lambdasistemi/tmux-ws/commit/736737f09cde6c54ac8dec0e6e076ba120f8d05f))
* keep touch command deck visible ([af9ecd4](https://github.com/lambdasistemi/tmux-ws/commit/af9ecd4216db71930a68ec87d317a9bf282b6f07))
* kill stale process on port before starting ([853af27](https://github.com/lambdasistemi/tmux-ws/commit/853af27af052e2f913b2839e81a41b26eca7bd07)), closes [#48](https://github.com/lambdasistemi/tmux-ws/issues/48)
* launch claude with --dangerously-skip-permissions ([88a9851](https://github.com/lambdasistemi/tmux-ws/commit/88a9851a140dc3732c5bfe37dd368526a97a6ffe))
* name tmux window 'agent' instead of default ([48a932f](https://github.com/lambdasistemi/tmux-ws/commit/48a932f04bfc14c350884301494308b18d5d52df))
* off-by-one in parseIssueBranch prefix length ([8e1449a](https://github.com/lambdasistemi/tmux-ws/commit/8e1449a4c714de17ccb635dd8ffb66d06979851c))
* **release:** preserve feature minor bumps before 1.0 ([0fb8038](https://github.com/lambdasistemi/tmux-ws/commit/0fb80386e24c744abeb3d95c7cb49cc5e6333735))
* **release:** recover rebased releases safely ([220fa85](https://github.com/lambdasistemi/tmux-ws/commit/220fa85070e783eb75c01fc08a3ecfe120b006f0))
* resolve sessions name collision in recovery module ([d37e87b](https://github.com/lambdasistemi/tmux-ws/commit/d37e87b94cd9cdc12a4dddd79e299eba734af8aa))
* restore files lost in CI bootstrap ([de5944a](https://github.com/lambdasistemi/tmux-ws/commit/de5944af91a904266430347f89b6c9e53155985b))
* return existing session on duplicate launch instead of 409 ([926610a](https://github.com/lambdasistemi/tmux-ws/commit/926610a7476100838e1bc0ab3d0c9e65d452326a))
* set TERM=xterm-256color in PTY environment ([2a7812b](https://github.com/lambdasistemi/tmux-ws/commit/2a7812b8bb32ea5adf50182f6a71fed0c362de3f))
* set terminal raw mode for attach recipe ([5e724dc](https://github.com/lambdasistemi/tmux-ws/commit/5e724dcfac9d3145b33d70a9f368c0914e404beb))
* skip tmux session creation if already exists ([5d3c30d](https://github.com/lambdasistemi/tmux-ws/commit/5d3c30d74633376779c4f4486f460ba68b1d2bc2))
* strip field prefixes from JSON and show curl errors ([dee7dc3](https://github.com/lambdasistemi/tmux-ws/commit/dee7dc3cd29e8b0256f64e9a37aeeae549393dac))
* suppress stderr noise from branch sync checks ([6880abb](https://github.com/lambdasistemi/tmux-ws/commit/6880abb221ea3f026c755e49cd75f35101767a93))
* use dev-assets mkdocs and fence_code_format for mermaid ([ebd6cb5](https://github.com/lambdasistemi/tmux-ws/commit/ebd6cb5e963dbec3fb815a7cead3ea8d20b12bca)), closes [#36](https://github.com/lambdasistemi/tmux-ws/issues/36)
* use nix run for serve recipe ([ac68d55](https://github.com/lambdasistemi/tmux-ws/commit/ac68d556e39101e731b783002c7207eabf339b37))
* use relative public app assets ([#72](https://github.com/lambdasistemi/tmux-ws/issues/72)) ([7c9140e](https://github.com/lambdasistemi/tmux-ws/commit/7c9140e676be44e2b1a2f00ed95f8c393c1cd37f))
* use WebGL renderer in xterm.js to reduce flickering ([8ab107f](https://github.com/lambdasistemi/tmux-ws/commit/8ab107f1a9ac6e985b852cbeef2c45b172d60502))
* use wss:// for HTTPS server connections ([d3ed618](https://github.com/lambdasistemi/tmux-ws/commit/d3ed618f768b26a64c503dedb0994ddafe8e42c1))


### Reverts

* restore gate after command-deck visibility regression ([f8e9cf3](https://github.com/lambdasistemi/tmux-ws/commit/f8e9cf3c5b9525615f4325066c8a8815fbce3442))

## [0.3.0](https://github.com/lambdasistemi/tmux-ws/compare/v0.2.0...v0.3.0) (2026-07-13)


### Features

* add touch terminal command deck ([6e75f3f](https://github.com/lambdasistemi/tmux-ws/commit/6e75f3fdef6fd387afa909f95041b942d2c4a7c2))
* model terminal command deck input ([d443b6b](https://github.com/lambdasistemi/tmux-ws/commit/d443b6b7b00cb3bcd8e304286484998d9d5df940))


### Bug Fixes

* keep touch command deck visible ([af9ecd4](https://github.com/lambdasistemi/tmux-ws/commit/af9ecd4216db71930a68ec87d317a9bf282b6f07))
* **release:** recover rebased releases safely ([220fa85](https://github.com/lambdasistemi/tmux-ws/commit/220fa85070e783eb75c01fc08a3ecfe120b006f0))


### Reverts

* restore gate after command-deck visibility regression ([f8e9cf3](https://github.com/lambdasistemi/tmux-ws/commit/f8e9cf3c5b9525615f4325066c8a8815fbce3442))

## [0.2.0](https://github.com/lambdasistemi/tmux-ws/compare/v0.1.1...v0.2.0) (2026-07-12)


### Features

* add touch close-current actions ([e1dcd53](https://github.com/lambdasistemi/tmux-ws/commit/e1dcd533edba0c2a0a75c162128ac9cbd4250173))
* close current tmux contexts safely ([c1d0e56](https://github.com/lambdasistemi/tmux-ws/commit/c1d0e5613a707b140c968f207aafd34252391399))
* expose close-current API actions ([63656be](https://github.com/lambdasistemi/tmux-ws/commit/63656be7e6a7b75fa50b43e7108c3a101d42ce82))
* model close-current transitions ([4b8bd14](https://github.com/lambdasistemi/tmux-ws/commit/4b8bd14fa12bf331f068e12dcc2fee43d29e500c))
* **ui:** make workspace touch-first ([63e1e37](https://github.com/lambdasistemi/tmux-ws/commit/63e1e3765174113d2bc4ba10de559fe48bd50576))


### Bug Fixes

* **ci:** isolate hosted runner verification ([306cb26](https://github.com/lambdasistemi/tmux-ws/commit/306cb26e2d8c142cc0c39184cdebc46ee704ccc4))
* **release:** preserve feature minor bumps before 1.0 ([0fb8038](https://github.com/lambdasistemi/tmux-ws/commit/0fb80386e24c744abeb3d95c7cb49cc5e6333735))
