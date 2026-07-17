{ pkgs }:
pkgs.writeShellApplication {
  name = "linux-artifact-smoke";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.cpio
    pkgs.curl
    pkgs.dpkg
    pkgs.findutils
    pkgs.gnugrep
    pkgs.rpm
  ];
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

    findUi() {
      root="$1"
      staticLink="$(find "$root" -type l -path '*/share/tmux-ws/static' -print -quit)"
      test -n "$staticLink" || {
        echo "artifact smoke: missing share/tmux-ws/static link in $root" >&2
        exit 1
      }
      staticTarget="$(readlink "$staticLink")"
      case "$staticTarget" in
        /nix/store/*) packagedStatic="$root$staticTarget" ;;
        *) packagedStatic="$(dirname "$staticLink")/$staticTarget" ;;
      esac
      test -s "$packagedStatic/index.html" || {
        echo "artifact smoke: missing share/tmux-ws/static/index.html in $root" >&2
        exit 1
      }
      test -s "$packagedStatic/index.js" || {
        echo "artifact smoke: missing share/tmux-ws/static/index.js in $root" >&2
        exit 1
      }
    }

    smokeUi() {
      appImage="$1"
      destination="$2"
      port="$(shuf -i 20000-40000 -n 1)"
      mkdir -p "$destination/base" "$destination/run"
      (
        cd "$destination/run"
        APPIMAGE_EXTRACT_AND_RUN=1 "$appImage" \
          --host 127.0.0.1 \
          --port "$port" \
          --base-dir "$destination/base"
      ) >"$destination/server.log" 2>&1 &
      pid="$!"
      response="$destination/index.html"
      status=1
      for _attempt in 1 2 3 4 5; do
        if curl --silent --show-error --fail \
          --output "$response" "http://127.0.0.1:$port/"; then
          status=0
          break
        fi
        sleep 1
      done
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      if test "$status" -ne 0; then
        cat "$destination/server.log" >&2
        exit 1
      fi
      grep -Fq '<title>tmux-ws</title>' "$response"
      grep -Fq 'src="index.js' "$response"
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
      findUi "$destination/squashfs-root"
      findTmuxWs "$(find "$destination/squashfs-root" -type f -name tmux-ws -perm -u+x -print -quit)"
      smokeUi "$destination/tmux-ws.AppImage" "$destination"
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
    findUi "$tmpDir/deb"
    findTmuxWs "$(find "$tmpDir/deb" -type f -name tmux-ws -perm -u+x -print -quit)"
    (
      cd "$tmpDir/rpm"
      rpm2cpio "$rpm" | cpio -idm --quiet
    )
    findUi "$tmpDir/rpm"
    findTmuxWs "$(find "$tmpDir/rpm" -type f -name tmux-ws -perm -u+x -print -quit)"
  '';
}
