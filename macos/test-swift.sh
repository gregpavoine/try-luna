#!/bin/bash

set -euo pipefail
native_dir=$(cd "$(dirname "$0")" && pwd -P)
compiler=$(xcrun --find swiftc)
plugin="$(dirname "$compiler")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
flags=()
if [[ -f $plugin ]]; then
  flags=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi
cd "$native_dir"
swift test --disable-sandbox ${flags[@]+"${flags[@]}"} "$@"
