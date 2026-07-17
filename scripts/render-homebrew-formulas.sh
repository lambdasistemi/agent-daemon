#!/usr/bin/env bash
set -euo pipefail

out_dir=${1:?usage: render-homebrew-formulas.sh OUT_DIR URL SHA256 VERSION}
url=${2:?usage: render-homebrew-formulas.sh OUT_DIR URL SHA256 VERSION}
sha256=${3:?usage: render-homebrew-formulas.sh OUT_DIR URL SHA256 VERSION}
version=${4:?usage: render-homebrew-formulas.sh OUT_DIR URL SHA256 VERSION}

mkdir -p "$out_dir"

cat > "$out_dir/tmux-ws.rb" <<EOF
class TmuxWs < Formula
  desc "WebSocket daemon for managing tmux workspaces"
  homepage "https://github.com/lambdasistemi/tmux-ws"
  url "$url"
  sha256 "$sha256"
  version "$version"

  def install
    bin.install "bin/tmux-ws"
    (libexec/"lib").install Dir["libexec/lib/*"]
    (share/"tmux-ws").install Dir["share/tmux-ws/*"]
  end

  test do
    system "#{bin}/tmux-ws", "--help"
  end
end
EOF

cat > "$out_dir/agent-daemon.rb" <<EOF
class AgentDaemon < Formula
  desc "Deprecated compatibility route; install tmux-ws instead"
  homepage "https://github.com/lambdasistemi/tmux-ws"
  url "$url"
  sha256 "$sha256"
  version "$version"
  depends_on "tmux-ws"

  def install
    bin.install_symlink Formula["tmux-ws"].opt_bin/"tmux-ws" => "agent-daemon"
  end

  def caveats
    <<~EOS
      agent-daemon is deprecated; use tmux-ws.
    EOS
  end
end
EOF
