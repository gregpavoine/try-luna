#!/bin/bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d /private/tmp/luna-build-path.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/repo/macos" "$work/outside" "$work/bin"
cp "$root/macos/build-luna-app.sh" "$work/repo/macos/"
printf 'protected\n' >"$work/outside/keep"
cat >"$work/bin/swift" <<'STUB'
#!/bin/bash
touch "$LUNA_COMPILER_CALLED"
exit 73
STUB
chmod +x "$work/bin/swift"
export LUNA_COMPILER_CALLED="$work/compiler-called"
reject_symlink() {
  if PATH="$work/bin:$PATH" bash "$work/repo/macos/build-luna-app.sh" "$@" >"$work/output" 2>&1; then
    echo 'unsafe build path was accepted' >&2
    exit 1
  fi
  [[ ! -e $LUNA_COMPILER_CALLED && $(cat "$work/outside/keep") == "protected" ]] || {
    echo 'unsafe output reached a build tool or changed external data' >&2
    exit 1
  }
}
mkdir -p "$work/repo/dist"
ln -s "$work/outside" "$work/repo/dist/app.noindex"
reject_symlink
rm "$work/repo/dist/app.noindex"
ln -s "$work/outside" "$work/repo/.build"
reject_symlink
rm "$work/repo/.build"
dmg="$work/repo/dist/Try-Luna-0.1.0-preview-$(uname -m).dmg"
ln -s "$work/outside/keep" "$dmg.sha256"
reject_symlink --dmg
rm "$dmg.sha256"
ln -s "$work/outside/keep" "$dmg"
reject_symlink --dmg
printf 'ok: symlinked app, build, DMG and checksum paths are rejected before compiler execution\n'
