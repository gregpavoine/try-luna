#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
policy="$root/macos/luna-factory-policy.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/luna-factory-policy.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat >"$work/valid.json" <<'JSON'
{"format":1,"kind":"upstream-shell-factory","platform":"aarch64","boot":"uefi-limine","distribution":{"id":"lunaos","source_repository":"https://github.com/gregpavoine/LunaOS","source_revision":"0123456789abcdef0123456789abcdef01234567"}}
JSON

/bin/bash "$policy" "$work/valid.json"
printf '%s\n' 'ok: an aarch64 LunaOS factory with source provenance passes'

reject() {
  local manifest=$1
  local description=$2
  if /bin/bash "$policy" "$manifest" >"$work/output" 2>&1; then
    printf 'FAIL: %s was accepted\n' "$description" >&2
    exit 1
  fi
  printf 'ok: %s is rejected\n' "$description"
}

cp "$work/valid.json" "$work/stock.json"
/usr/bin/plutil -remove distribution "$work/stock.json"
reject "$work/stock.json" 'an unlabelled stock Omarchy factory'

cp "$work/valid.json" "$work/wrong-os.json"
/usr/bin/plutil -replace distribution.id -string omarchy "$work/wrong-os.json"
reject "$work/wrong-os.json" 'a non-LunaOS factory'

cp "$work/valid.json" "$work/wrong-platform.json"
/usr/bin/plutil -replace platform -string x86 "$work/wrong-platform.json"
reject "$work/wrong-platform.json" 'an incompatible x86 factory'

cp "$work/valid.json" "$work/wrong-boot.json"
/usr/bin/plutil -replace boot -string bios "$work/wrong-boot.json"
reject "$work/wrong-boot.json" 'a non-UEFI factory'

cp "$work/valid.json" "$work/wrong-format.json"
/usr/bin/plutil -replace format -string 1 "$work/wrong-format.json"
reject "$work/wrong-format.json" 'a string instead of the numeric format version'

cp "$work/valid.json" "$work/wrong-repo.json"
/usr/bin/plutil -replace distribution.source_repository -string https://github.com/omacom/omarchy "$work/wrong-repo.json"
reject "$work/wrong-repo.json" 'an upstream Omarchy source repository'

cp "$work/valid.json" "$work/repo-newline.json"
/usr/bin/plutil -replace distribution.source_repository -string $'https://github.com/gregpavoine/LunaOS\n' "$work/repo-newline.json"
reject "$work/repo-newline.json" 'a source repository containing a trailing newline'

cp "$work/valid.json" "$work/no-revision.json"
/usr/bin/plutil -remove distribution.source_revision "$work/no-revision.json"
reject "$work/no-revision.json" 'missing source revision'

cp "$work/valid.json" "$work/bad-revision.json"
/usr/bin/plutil -replace distribution.source_revision -string main "$work/bad-revision.json"
reject "$work/bad-revision.json" 'a mutable source revision'

printf '{"format":' >"$work/malformed.json"
reject "$work/malformed.json" 'malformed JSON'

ln -s "$work/valid.json" "$work/symlink.json"
reject "$work/symlink.json" 'a symlinked manifest'
