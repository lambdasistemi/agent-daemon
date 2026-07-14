{ pkgs }:
pkgs.writeShellApplication {
  name = "linux-artifact-smoke";
  runtimeInputs =
    [ pkgs.coreutils pkgs.findutils pkgs.dpkg pkgs.rpm pkgs.cpio ];
  text = ''
    usage() {
      echo "usage: linux-artifact-smoke --artifacts-dir DIR --artifact-version VERSION" >&2
    }

    artifactsDir=""
    artifactVersion=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --artifacts-dir)
          artifactsDir="$2"
          shift 2
          ;;
        --artifact-version)
          artifactVersion="$2"
          shift 2
          ;;
        --help)
          usage
          exit 0
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done

    test -n "$artifactsDir"
    test -n "$artifactVersion"

    tmpDir="$(mktemp -d)"
    trap 'rm -rf "$tmpDir"' EXIT

    findTmuxWs() {
      executable="$1"
      test -n "$executable"
      "$executable" --help >/dev/null
    }

    smokeAppImage() {
      appImage="$1"
      destination="$2"
      cp "$appImage" "$destination/tmux-ws.AppImage"
      chmod +x "$destination/tmux-ws.AppImage"
      (
        cd "$destination"
        ./tmux-ws.AppImage --appimage-extract >/dev/null
      )
      findTmuxWs "$(find "$destination/squashfs-root" -type f -name tmux-ws -perm -u+x -print -quit)"
    }

    versionedPrefix="tmux-ws-$artifactVersion-x86_64-linux"
    versionedAppImage="$artifactsDir/$versionedPrefix.AppImage"
    deb="$artifactsDir/$versionedPrefix.deb"
    rpm="$artifactsDir/$versionedPrefix.rpm"
    stableAppImage="$artifactsDir/tmux-ws.AppImage"

    test -f "$versionedAppImage"
    test -f "$deb"
    test -f "$rpm"
    test -f "$stableAppImage"
    test -f "$artifactsDir/SHA256SUMS"

    mkdir -p "$tmpDir/versioned-appimage" "$tmpDir/stable-appimage" "$tmpDir/deb" "$tmpDir/rpm"
    smokeAppImage "$versionedAppImage" "$tmpDir/versioned-appimage"
    smokeAppImage "$stableAppImage" "$tmpDir/stable-appimage"
    dpkg-deb -x "$deb" "$tmpDir/deb"
    findTmuxWs "$(find "$tmpDir/deb" -type f -name tmux-ws -perm -u+x -print -quit)"
    (
      cd "$tmpDir/rpm"
      rpm2cpio "$rpm" | cpio -idm --quiet
    )
    findTmuxWs "$(find "$tmpDir/rpm" -type f -name tmux-ws -perm -u+x -print -quit)"
  '';
}
