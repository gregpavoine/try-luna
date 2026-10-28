#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
if (($# > 1)); then
  printf 'Usage: %s [Try Luna.app]\n' "$0" >&2
  exit 64
fi
[[ $(uname -s) == "Darwin" ]] || {
  printf 'This packaging regression requires macOS and its native codesign verifier.\n' >&2
  exit 1
}
app=${1:-"$root/dist/app.noindex/Try Luna.app"}
[[ -d $app && ! -L $app ]] || {
  printf 'Build the real application first: make app (missing or unsafe bundle: %s)\n' "$app" >&2
  exit 1
}

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
printf 'ok: the built application passes native strict signature verification\n'

work=$(mktemp -d /private/tmp/luna-app-signature.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
copy="$work/Try Luna.app"
/usr/bin/ditto "$app" "$copy"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$copy"
printf 'ok: an intact copy retains its complete resource seal\n'

license="$copy/Contents/Resources/LICENSE"
[[ -f $license && ! -L $license ]] || {
  printf 'The real application must contain a regular bundled LICENSE resource.\n' >&2
  exit 1
}
/bin/chmod u+w "$license"
printf '\nTry Luna packaging resource-tamper regression.\n' >>"$license"
if /usr/bin/codesign --verify --deep --strict --verbose=2 "$copy" >"$work/tampered-codesign.log" 2>&1; then
  printf 'FAIL: native codesign accepted a modified bundled resource.\n' >&2
  exit 1
fi
cat "$work/tampered-codesign.log"
printf 'ok: native codesign rejects tampering with the bundled LICENSE\n'
