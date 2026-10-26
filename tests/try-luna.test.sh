#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d)
scratch=$(cd "$scratch" && pwd -P)
cleanup() {
  if [[ -f $scratch/vm.pid ]]; then kill -TERM "$(cat "$scratch/vm.pid")" 2>/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/tools" "$scratch/firmware" "$scratch/input with spaces,comma"
iso="$scratch/input with spaces,comma/luna.iso"
dd if=/dev/zero of="$iso" bs=32774 count=1 >/dev/null 2>&1
printf CD001 | dd of="$iso" bs=1 seek=32769 conv=notrunc >/dev/null 2>&1
printf firmware >"$scratch/firmware/code.fd"
printf variables >"$scratch/firmware/vars.fd"
cat >"$scratch/tools/qemu" <<'SH'
#!/bin/bash
set -eu
printf '%s\n' "$@" >"$TRY_LUNA_TEST_QEMU_LOG"
[[ -d $TRY_LUNA_TEST_STATE/vms/default/.run-lock ]]
if [[ ${TRY_LUNA_TEST_WAIT:-0} == 1 ]]; then
  trap 'rm -f "$TRY_LUNA_TEST_READY" "$TRY_LUNA_TEST_VM_PID"; exit 0' TERM HUP
  printf '%s\n' "$$" >"$TRY_LUNA_TEST_VM_PID"
  printf ready >"$TRY_LUNA_TEST_READY"
  while :; do sleep 0.05; done
fi
exit "${TRY_LUNA_TEST_QEMU_EXIT:-0}"
SH
cat >"$scratch/tools/qemu-img" <<'SH'
#!/bin/bash
set -eu
printf '%s\n' "$@" >>"$TRY_LUNA_TEST_IMG_LOG"
if [[ $1 == create ]]; then
  printf 'test external disk boundary' >"${@: -2:1}"
elif [[ $1 == info ]]; then
  printf 'file format: qcow2\n'
  if [[ ${TRY_LUNA_TEST_BACKING:-0} == 1 ]]; then
    printf 'backing file: /outside/private.img\n'
  fi
else
  exit 3
fi
SH
chmod +x "$scratch/tools/"*
export TRY_LUNA_QEMU="$scratch/tools/qemu"
export TRY_LUNA_QEMU_IMG="$scratch/tools/qemu-img"
export TRY_LUNA_UEFI_CODE="$scratch/firmware/code.fd"
export TRY_LUNA_UEFI_VARS="$scratch/firmware/vars.fd"
export TRY_LUNA_TEST_QEMU_LOG="$scratch/qemu.log"
export TRY_LUNA_TEST_IMG_LOG="$scratch/img.log"
export TRY_LUNA_STATE_DIR="$scratch/state with spaces,comma"
export TRY_LUNA_TEST_STATE="$TRY_LUNA_STATE_DIR"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }
run() { /bin/bash "$root/try-luna" "$@" >"$scratch/output" 2>&1; }
expect_failure() {
  expected=$1
  shift
  if run "$@"; then fail "expected refusal: $*"; fi
  if ! grep -Fq "$expected" "$scratch/output"; then cat "$scratch/output" >&2; fail "missing refusal: $expected"; fi
}

if ! run --help; then cat "$scratch/output" >&2; fail 'launcher help is unavailable'; fi
grep -Fq 'try-luna run' "$scratch/output" || fail 'help omits run'
ok 'help works without creating a VM'

run run --iso "$iso" --memory 4096 --cpus 4 --disk-gib 32 --dry-run
grep -Fq 'Command:' "$scratch/output" || fail 'dry-run omits command'
grep -Fq 'luna-disk' "$scratch/output" || fail 'dry-run omits own disk'
[[ ! -e $TRY_LUNA_STATE_DIR && ! -e $TRY_LUNA_TEST_IMG_LOG && ! -e $TRY_LUNA_TEST_QEMU_LOG ]] || fail 'dry-run created state or invoked VM tools'
ok 'dry-run plans a VM without disk creation or tool execution'

expect_failure 'VM name' run --iso "$iso" --name ../outside --dry-run
expect_failure 'memory' run --iso "$iso" --memory 0 --dry-run
expect_failure 'cpus' run --iso "$iso" --cpus 0 --dry-run
expect_failure 'disk-gib' run --iso "$iso" --disk-gib 0 --dry-run
expect_failure 'Unknown option' run --iso "$iso" --wipe
expect_failure 'requires a value' run --iso
ok 'invalid options fail before creating state'

expect_failure 'regular ISO' run --iso /dev/null --dry-run
ln -s "$iso" "$scratch/luna-link.iso"
expect_failure 'symlink' run --iso "$scratch/luna-link.iso" --dry-run
printf junk >"$scratch/junk.iso"
expect_failure 'ISO9660' run --iso "$scratch/junk.iso" --dry-run
ok 'devices, symlinks and non-ISO input are rejected'

expect_failure 'No existing VM disk' run --dry-run
expect_failure 'Automatic release downloads' run --release
[[ ! -e $TRY_LUNA_STATE_DIR ]] || fail 'refusal created state'
ok 'absent images fail without downloads or empty disks'

ln -s "$scratch/firmware" "$TRY_LUNA_STATE_DIR"
expect_failure 'symlink' run --iso "$iso" --dry-run
rm "$TRY_LUNA_STATE_DIR"
mkdir -m 700 -p "$TRY_LUNA_STATE_DIR/vms"
chmod 700 "$TRY_LUNA_STATE_DIR" "$TRY_LUNA_STATE_DIR/vms"
ln -s "$scratch/firmware" "$TRY_LUNA_STATE_DIR/vms/default"
expect_failure 'symlink' run --iso "$iso" --dry-run
rm "$TRY_LUNA_STATE_DIR/vms/default"
mkdir -m 700 "$TRY_LUNA_STATE_DIR/vms/default"
printf unowned >"$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2"
chmod 600 "$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2"
expect_failure 'ownership marker' run --iso "$iso" --dry-run
rm "$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2"
rmdir "$TRY_LUNA_STATE_DIR/vms/default"
ok 'state symlinks and unrecognized disks are rejected'

export TRY_LUNA_TEST_QEMU_EXIT=17
if run run --iso "$iso" --memory 4096 --cpus 4 --disk-gib 32; then fail 'QEMU failure was hidden'; else status=$?; fi
[[ $status == 17 ]] || fail "QEMU exit status changed: $status"
[[ -f $TRY_LUNA_STATE_DIR/vms/default/disk.qcow2 && -f $TRY_LUNA_STATE_DIR/vms/default/uefi-vars.fd ]] || fail 'own disk or vars not prepared'
[[ ! -e $TRY_LUNA_STATE_DIR/vms/default/.run-lock ]] || fail 'lock not released after QEMU failure'
grep -Fq 'input with spaces,,comma/luna.iso' "$TRY_LUNA_TEST_QEMU_LOG" || fail 'QEMU keyval path commas not escaped'
grep -Fq 'state with spaces,,comma/vms/default/disk.qcow2' "$TRY_LUNA_TEST_QEMU_LOG" || fail 'disk comma path not escaped'
if grep -Eq 'hostfwd|virtfs|fsdev|/dev/(disk|sd|nvme)' "$TRY_LUNA_TEST_QEMU_LOG"; then fail 'unsafe host resource added'; fi
ok 'launch prepares isolated storage, holds lock and preserves QEMU failure status'

disk_before=$(cksum "$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2")
vars_before=$(cksum "$TRY_LUNA_STATE_DIR/vms/default/uefi-vars.fd")
rm "$TRY_LUNA_TEST_IMG_LOG" "$TRY_LUNA_TEST_QEMU_LOG"
run run --memory 2048 --cpus 2 --dry-run
[[ ! -e $TRY_LUNA_TEST_IMG_LOG && ! -e $TRY_LUNA_TEST_QEMU_LOG ]] || fail 'resume dry-run invoked VM tools'
export TRY_LUNA_TEST_QEMU_EXIT=0
run run --memory 2048 --cpus 2
[[ $disk_before == "$(cksum "$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2")" && $vars_before == "$(cksum "$TRY_LUNA_STATE_DIR/vms/default/uefi-vars.fd")" ]] || fail 'resume reset existing VM files'
if grep -Fq 'create' "$TRY_LUNA_TEST_IMG_LOG"; then fail 'resume recreated the disk'; fi
if grep -Fq 'luna-iso' "$TRY_LUNA_TEST_QEMU_LOG"; then fail 'resume attached installer without request'; fi
ok 'installed boot preserves disk and firmware variables without an ISO'

mkdir "$TRY_LUNA_STATE_DIR/vms/default/.run-lock"
expect_failure 'locked' run --dry-run
rmdir "$TRY_LUNA_STATE_DIR/vms/default/.run-lock"
mv "$TRY_LUNA_STATE_DIR/vms/default/uefi-vars.fd" "$scratch/saved-vars.fd"
expect_failure 'firmware variables' run --iso "$iso" --dry-run
mv "$scratch/saved-vars.fd" "$TRY_LUNA_STATE_DIR/vms/default/uefi-vars.fd"
export TRY_LUNA_TEST_BACKING=1
expect_failure 'backing' run
unset TRY_LUNA_TEST_BACKING
ok 'concurrent access, incomplete VM state and backing files fail closed'

chmod 755 "$TRY_LUNA_STATE_DIR"
expect_failure 'private' run --dry-run
chmod 700 "$TRY_LUNA_STATE_DIR"
ln "$TRY_LUNA_STATE_DIR/vms/default/disk.qcow2" "$scratch/linked-disk"
expect_failure 'Hard-linked' run --dry-run
rm "$scratch/linked-disk"
ok 'shared permissions and hard-linked VM storage are refused'

unsafe_parent="$scratch/nonsticky-shared-parent"
mkdir -m 777 "$unsafe_parent"
chmod 777 "$unsafe_parent"
mkdir -m 700 "$unsafe_parent/existing-state" "$unsafe_parent/private-parent"
printf 'outside data must survive' >"$scratch/outside-data"
outside_before=$(cksum "$scratch/outside-data")
img_before=$(cksum "$TRY_LUNA_TEST_IMG_LOG")
qemu_before=$(cksum "$TRY_LUNA_TEST_QEMU_LOG")
for unsafe_state in "$unsafe_parent/existing-state" "$unsafe_parent/private-parent/new-state"; do
  TRY_LUNA_STATE_DIR="$unsafe_state" expect_failure 'writable ancestor' run --iso "$iso"
  [[ ! -e $unsafe_state/vms ]] || fail 'untrusted ancestor refusal created VM state'
done
[[ $outside_before == "$(cksum "$scratch/outside-data")" && $img_before == "$(cksum "$TRY_LUNA_TEST_IMG_LOG")" && $qemu_before == "$(cksum "$TRY_LUNA_TEST_QEMU_LOG")" ]] || fail 'untrusted ancestor refusal touched outside data or invoked VM tools'
ok 'private existing and new state below a nonsticky writable ancestor are refused before mutation'

export TRY_LUNA_TEST_WAIT=1
export TRY_LUNA_TEST_READY="$scratch/ready"
export TRY_LUNA_TEST_VM_PID="$scratch/vm.pid"
for signal in TERM HUP; do
  /bin/bash "$root/try-luna" run >"$scratch/signal-output" 2>&1 &
  runner_pid=$!
  for (( attempt=0; attempt<200; attempt++ )); do
    if [[ -e $TRY_LUNA_TEST_READY ]]; then break; fi
    sleep 0.02
  done
  [[ -e $TRY_LUNA_TEST_READY ]] || { cat "$scratch/signal-output" >&2; fail 'external VM process never started'; }
  expect_failure 'locked' run --dry-run
  kill "-$signal" "$runner_pid"
  if wait "$runner_pid"; then fail "$signal status was hidden"; else status=$?; fi
  if [[ $signal == TERM ]]; then expected_status=143; else expected_status=129; fi
  [[ $status == "$expected_status" ]] || fail "$signal status changed: $status"
  [[ ! -e $TRY_LUNA_TEST_READY && ! -e $TRY_LUNA_TEST_VM_PID && ! -e $TRY_LUNA_STATE_DIR/vms/default/.run-lock ]] || fail "$signal did not wait for VM exit before releasing its lock"
done
unset TRY_LUNA_TEST_WAIT
ok 'a concurrent launcher is refused and TERM/HUP wait for VM exit before releasing its lock'

run doctor
grep -Fq 'x86_64 guest' "$scratch/output" || fail 'doctor omits guest architecture'
ok 'doctor reports detected runtime and target without a VM launch'
