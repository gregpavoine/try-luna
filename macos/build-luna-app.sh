#!/bin/bash

set -euo pipefail

make_dmg=0
case ${1:-} in
  --dmg) make_dmg=1; shift ;;
  --help)
    echo 'Usage: macos/build-luna-app.sh [--dmg]'
    echo 'Build the local Try Luna ISO preview. QEMU is a separate prerequisite.'
    exit 0
    ;;
esac
(( $# == 0 )) || { echo 'Unknown build argument' >&2; exit 64; }
[[ $(uname -s) == "Darwin" ]] || { echo 'Try Luna requires macOS 15 or newer' >&2; exit 1; }
native_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$native_dir/.." && pwd -P)
build_dir="$repo_dir/.build/luna-app"
dist_dir="$repo_dir/dist"
app="$dist_dir/app.noindex/Try Luna.app"
dmg="$dist_dir/Try-Luna-0.1.0-preview-$(uname -m).dmg"
for path in "$repo_dir/.build" "$build_dir" "$build_dir/module-cache" "$build_dir/TryLuna.iconset" "$dist_dir" "$dist_dir/app.noindex" "$app"; do
  [[ ! -L $path ]] || { echo "Unsafe build output path: $path" >&2; exit 1; }
done
if (( make_dmg )); then
  [[ ! -L $dmg && ! -L $dmg.sha256 ]] || { echo 'Unsafe DMG or checksum output path' >&2; exit 1; }
fi
mkdir -p "$build_dir/module-cache" "$dist_dir/app.noindex"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$build_dir/module-cache"
export MACOSX_DEPLOYMENT_TARGET=15.0
swift build --package-path "$native_dir" --disable-sandbox -c release -debug-info-format none
helper="$native_dir/.build/release/omarchy-vm-helper"
[[ -x $helper ]] || { echo 'Swift build did not produce the launcher' >&2; exit 1; }
stage=$(mktemp -d "$dist_dir/.luna-app.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
contents="$stage/Try Luna.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources/scripts"
install -m 0755 "$helper" "$contents/MacOS/omarchy-vm-helper"
install -m 0644 "$native_dir/LunaInfo.plist" "$contents/Info.plist"
install -m 0755 "$repo_dir/try-luna" "$contents/Resources/scripts/try-luna"
install -m 0644 "$repo_dir/LICENSE" "$repo_dir/UPSTREAM.md" "$contents/Resources/"
xcrun swiftc -module-cache-path "$build_dir/module-cache" -framework AppKit \
  "$native_dir/render-app-icon.swift" -o "$build_dir/render-icon"
iconset="$build_dir/TryLuna.iconset"
mkdir -p "$iconset"
"$build_dir/render-icon" "$native_dir/LunaIcon.svg" "$iconset/icon_512x512@2x.png"
while IFS=' ' read -r name size; do
  sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" --out "$iconset/$name" >/dev/null
done <<'SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
SIZES
iconutil -c icns "$iconset" -o "$contents/Resources/TryLuna.icns"
plutil -lint "$contents/Info.plist"
rm -rf -- "$app"
mv "$stage/Try Luna.app" "$app"
printf 'Local preview: %s\n' "$app"
if (( make_dmg )); then
  dmg_stage="$stage/dmg"
  mkdir -p "$dmg_stage"
  ditto "$app" "$dmg_stage/Try Luna.app"
  ln -s /Applications "$dmg_stage/Applications"
  staged_dmg="$stage/Try-Luna.dmg"
  if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName 'Try Luna' "$dmg_stage" "$staged_dmg"
  else
    hdiutil create -volname 'Try Luna' -srcfolder "$dmg_stage" -format UDZO "$staged_dmg"
  fi
  mv -- "$staged_dmg" "$dmg"
  shasum -a 256 "$dmg" >"$dmg.sha256"
  printf 'Unsigned development DMG: %s\n' "$dmg"
fi
