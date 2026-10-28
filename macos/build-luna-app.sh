#!/bin/bash

set -euo pipefail

make_dmg=0
sign_identity=-
notarize_profile=
while (($#)); do
  case "$1" in
    --dmg) make_dmg=1; shift ;;
    --sign-identity|--notarize-profile)
      option=$1
      (($# >= 2)) && [[ -n $2 && $2 != --* ]] || { echo "$option requires a value" >&2; exit 64; }
      if [[ $option == "--sign-identity" ]]; then
        sign_identity=$2
      else
        notarize_profile=$2
        make_dmg=1
      fi
      shift 2
      ;;
    --help)
      echo 'Usage: macos/build-luna-app.sh [--dmg] [--sign-identity IDENTITY] [--notarize-profile KEYCHAIN_PROFILE]'
      echo 'Development builds seal the app ad hoc. Distribution uses an explicit Developer ID and notarization profile.'
      exit 0
      ;;
    *) echo "Unknown build argument: $1" >&2; exit 64 ;;
  esac
done
if [[ -n $notarize_profile && $sign_identity == "-" ]]; then
  echo 'Notarization requires an explicit Developer ID Application identity' >&2
  exit 64
fi
notarize() {
  local image=$1 result_file=$2 result status
  if xcrun notarytool submit "$image" --keychain-profile "$notarize_profile" --wait --timeout 10m --output-format json >"$result_file"; then
    cat "$result_file"
  else
    status=$?
    cat "$result_file"
    return "$status"
  fi
  result=$(/usr/bin/plutil -extract status raw -o - "$result_file")
  [[ $result == "Accepted" ]] || { echo "Apple notarization status: $result" >&2; return 1; }
}
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
sign_options=(--force --sign "$sign_identity" --identifier io.lunaos.tryluna.preview)
if [[ $sign_identity == "-" ]]; then
  sign_options+=(--timestamp=none)
else
  sign_options+=(--options runtime --timestamp)
fi
codesign "${sign_options[@]}" "$stage/Try Luna.app"
codesign --verify --deep --strict --verbose=2 "$stage/Try Luna.app"
if [[ -n $notarize_profile ]]; then
  ditto -c -k --keepParent "$stage/Try Luna.app" "$stage/Try-Luna-notary.zip"
  notarize "$stage/Try-Luna-notary.zip" "$stage/app-notarization.json"
  xcrun stapler staple "$stage/Try Luna.app"
  xcrun stapler validate "$stage/Try Luna.app"
  spctl --assess --type execute --verbose=4 "$stage/Try Luna.app"
fi
rm -rf -- "$app"
mv "$stage/Try Luna.app" "$app"
printf 'Local preview: %s\n' "$app"
if (( make_dmg )); then
  dmg_stage="$stage/Try Luna"
  mkdir -p "$dmg_stage"
  ditto "$app" "$dmg_stage/Try Luna.app"
  ln -s /Applications "$dmg_stage/Applications"
  staged_dmg="$stage/Try-Luna.dmg"
  if diskutil image create from --help >/dev/null 2>&1 &&
    diskutil image create from --format UDZO "$dmg_stage" "$staged_dmg" >"$stage/diskutil-image.log" 2>&1; then
    cat "$stage/diskutil-image.log"
  else
    printf '%s\n' 'Using hdiutil for development DMG creation'
    staged_dmg="$stage/Try-Luna-hdiutil.dmg"
    hdiutil create -volname 'Try Luna' -srcfolder "$dmg_stage" -format UDZO "$staged_dmg"
  fi
  if [[ $sign_identity != "-" ]]; then
    codesign --force --sign "$sign_identity" --identifier io.lunaos.tryluna.preview.disk-image --timestamp "$staged_dmg"
    codesign --verify --strict --verbose=2 "$staged_dmg"
  fi
  if [[ -n $notarize_profile ]]; then
    notarize "$staged_dmg" "$stage/dmg-notarization.json"
    xcrun stapler staple "$staged_dmg"
    xcrun stapler validate "$staged_dmg"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$staged_dmg"
  fi
  mv -- "$staged_dmg" "$dmg"
  shasum -a 256 "$dmg" >"$dmg.sha256"
  if [[ -n $notarize_profile ]]; then
    printf 'Developer ID signed and notarized DMG: %s\n' "$dmg"
  else
    printf 'Development DMG (not notarized): %s\n' "$dmg"
  fi
fi
