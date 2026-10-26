#!/bin/bash

set -euo pipefail

fail() {
  printf 'luna-factory-policy: %s\n' "$*" >&2
  exit 1
}

if (($# != 1)); then
  printf '%s\n' 'Usage: luna-factory-policy.sh FACTORY_JSON' >&2
  exit 64
fi

manifest=$1
[[ -f $manifest && ! -L $manifest ]] || fail 'factory.json must be a regular, non-symlink file'

field() {
  luna_factory_value=$(/usr/bin/plutil -extract "$1" raw -expect "$2" -n -o - -- "$manifest" 2>/dev/null && printf '.') ||
    fail "missing or invalid manifest field: $1"
  luna_factory_value=${luna_factory_value%.}
}

expect_field() {
  field "$1" "$2"
  [[ $luna_factory_value == "$3" ]] || fail "unsupported factory field: $1 (expected $3)"
}

expect_field format integer 1
expect_field kind string upstream-shell-factory
expect_field platform string aarch64
expect_field boot string uefi-limine
expect_field distribution.id string lunaos
expect_field distribution.source_repository string https://github.com/gregpavoine/LunaOS
field distribution.source_revision string
[[ $luna_factory_value =~ ^[0-9a-f]{40}$ ]] || fail 'the LunaOS source revision must be a full lowercase commit SHA'
