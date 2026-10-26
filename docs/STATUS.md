# Try Luna implementation status

Checkpoint: 2026-10-26, macOS 27, Apple Silicon. This is an unsigned development preview of the Mac launcher, not a LunaOS release or proof that a guest image installs.

## Implemented

- Native Swift/AppKit ISO launcher in `macos/Sources/OmarchyVMHelper/LunaISOApplication.swift`, selected by `LunaLaunchMode=iso` in `macos/LunaInfo.plist` and the existing Swift entrypoint.
- ISO selection, resource fields, installed-disk boot, QEMU diagnosis, exact child errors and protection against quitting while the VM process runs. The app opens without launching a VM.
- `try-luna`: x86_64 QEMU adapter, read-only local ISO, sparse qcow2 disk, private UEFI variables, owned private state, exclusive per-VM lock, TERM/INT/HUP forwarding and child exit propagation. Defaults are 4096 MiB, four vCPUs and a 64 GiB sparse disk. Apple Silicon uses TCG; the virtual disk has boot priority so an installed guest can reboot with the ISO attached.
- Native app and development DMG packaging with `make app` / `make dmg`; output symlink guards and a macOS 27 `diskutil image create from` path with an older-system `hdiutil` fallback. The earlier local hdiutil creation attempt returned Resource busy; the new diskutil path succeeded.
- Upstream native ARM/QEMU/guest integration code retained with provenance. The ARM factory guard requires LunaOS identity, aarch64/UEFI format and a full LunaOS source revision before output/storage changes. A JSON label alone does not prove disk contents.
- LunaOS GitHub Actions: pinned actions, read-only repository permissions, tests and development DMG artifact; inherited nightly/guest workflows removed. No release publication or signing step is active.

## Verified locally

| Check | Actual result |
| --- | --- |
| `make test` | Relevant Swift and host-shell suites passed; 522 Swift tests in 99 suites, including the new ISO request tests. |
| `bash tests/try-luna.test.sh` after final hardening | 13 behavior groups passed under macOS Bash 3.2, including persistence, no-side-effect planning, path/ownership refusal, locking, HUP/TERM and writable-ancestor refusal. VM tools are injected boundaries here; these tests do not boot QEMU. |
| `bash tests/luna-factory-policy.test.sh` | 12 checks passed using real macOS plutil. |
| `bash tests/luna-build-path.test.sh` | App/build/DMG/checksum symlinks rejected before compiler execution. Regressions were observed failing before their fixes. |
| `make dmg` | Exit 0; real arm64 Mach-O executable, app bundle and approximately 2.1 MiB development DMG produced under `dist/`. |
| `shasum -a 256 -c dist/Try-Luna-0.1.0-preview-arm64.dmg.sha256` | Passed. |
| `hdiutil verify dist/Try-Luna-0.1.0-preview-arm64.dmg` | Image checksums valid. |
| Real macOS UI | App opened; window inspected visually; QEMU diagnosis displayed the real missing-binary error; starting without an ISO was refused. No VM launched. |
| Bash syntax, plist/YAML parsing, `git diff --check` | Passed. |
| Local workflow audit | Zero critical, high or medium findings; two low governance findings remain (dependency update policy and structured issue forms). Live GitHub settings were outside this audit. |

The installed Command Line Tools needed a standard EnvironmentKey in place of the upstream SwiftUI Entry macro and an explicit Testing macro plugin path for tests. The build still emits inherited actor-isolation and toolchain search-path warnings; it completes successfully. The entire old upstream build/publish contract suite is not claimed: a diagnostic attempt encountered its obsolete assumptions about the original Makefile. Current `make test` covers the preview and retained Swift/host-shell regressions; old build/release sources remain references.

## Blocked or unverified

- QEMU is not installed on this Mac. The actual GUI diagnostic reports `Missing qemu-system-x86_64`; the application does not install it automatically.
- Live GitHub checks found no public releases in `gregpavoine/LunaOS` or `gregpavoine/LunaOS-iso`. A separately verified local LunaOS ISO is required. Historical tags and authenticated Actions ZIPs are not public release images.
- No actual guest boot, UEFI/QEMU compatibility test, graphical session, disk installation or installed-system reboot was run.
- No LunaOS ARM factory exists here. Native CPU/GPU performance and inherited clipboard, Touch ID, camera, microphone, battery and folder-sharing integrations are not verified LunaOS features.
- The DMG is an unsigned development artifact. Apple Developer signing, notarization, public app release and bundled QEMU distribution remain outstanding. The current preview requires external QEMU and has no automatic image downloader.
- GitHub repository `gregpavoine/try-luna` exists but has no pushed source or Actions run from this work. The owner handles pushes.

No real Linux host was accessed or modified. No existing VM was started, reset or deleted. No camera, microphone, Accessibility or administrator permission was granted.
