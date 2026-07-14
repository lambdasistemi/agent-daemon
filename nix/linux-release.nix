{ pkgs, bundlers, cabalVersion, devVersion, linuxTmuxWs, }:
let
  appImage = bundlers.toAppImage linuxTmuxWs;
  deb = bundlers.toDEB linuxTmuxWs;
  rpm = bundlers.toRPM linuxTmuxWs;
  mkArtifacts = artifactVersion:
    pkgs.runCommand "tmux-ws-linux-artifacts-${artifactVersion}" {
      nativeBuildInputs = [ pkgs.coreutils pkgs.findutils ];
    } ''
      appimage="$(find ${appImage} -type f -name '*.AppImage' -print -quit)"
      debFile="$(find ${deb} -type f -name '*.deb' -print -quit)"
      rpmFile="$(find ${rpm} -type f -name '*.rpm' -print -quit)"

      test -n "$appimage"
      test -n "$debFile"
      test -n "$rpmFile"

      mkdir -p "$out"
      cp -L "$appimage" "$out/tmux-ws-${artifactVersion}-x86_64-linux.AppImage"
      cp "$debFile" "$out/tmux-ws-${artifactVersion}-x86_64-linux.deb"
      cp "$rpmFile" "$out/tmux-ws-${artifactVersion}-x86_64-linux.rpm"
      cp "$out/tmux-ws-${artifactVersion}-x86_64-linux.AppImage" "$out/tmux-ws.AppImage"
      (
        cd "$out"
        sha256sum \
          "tmux-ws-${artifactVersion}-x86_64-linux.AppImage" \
          "tmux-ws-${artifactVersion}-x86_64-linux.deb" \
          "tmux-ws-${artifactVersion}-x86_64-linux.rpm" \
          tmux-ws.AppImage > SHA256SUMS
      )
    '';
in {
  release = mkArtifacts cabalVersion;
  dev = mkArtifacts devVersion;
}
