# Try Luna implementation status

Checkpoint: 2026-10-27, macOS 27, Apple Silicon. This is an unsigned development preview of the Mac launcher, not a LunaOS release or proof that a guest image installs.

## GitHub Actions runtime and DMG compatibility — 2026-10-28

[Run 40741960757](https://github.com/gregpavoine/try-luna/actions/runs/40741960757) passed its 522 Swift tests and host-shell suites and compiled the app, then failed packaging because the macOS 15 diskutil rejected `--volumeName`. Its retained artifact contained logs only. The Node.js 20 deprecation warning was emitted afterward and was not the failure cause.

The workflow now pins official `actions/checkout` v7.0.1 (`3d3c42e5aac5ba805825da76410c181273ba90b1`) and `actions/upload-artifact` v7.0.2 (`cf430e030ddbb5b0abf93d22962f4752f3646cd9`); both exact action manifests use Node.js 24. The packager names its source directory `Try Luna` and uses `diskutil image create from --format UDZO` without the unsupported volume-name flag. Failing workflow steps now print their retained logs while preserving the original make exit status.

Local `make dmg`, SHA-256 verification, hdiutil image verification, the output-path regression, YAML/shell parsing and diff checks pass. The local workflow audit reports no critical, high or medium findings. Source and CI results are available on the `codex/try-luna-bootstrap` branch; public app signing/notarization and a Linux installation release are separate requirements. Check the [Actions runs](https://github.com/gregpavoine/try-luna/actions) for each immutable commit's hosted result.

## Latest real-machine validation — 2026-10-27

Fresh `make test` passed the 522 Swift tests and the retained host-shell suites. `make -C lunaos test check` passed in the main source checkout. A real native arm64 QEMU 11.1.2 runtime was staged only under `.build/validation-20261027/runtime` from official Homebrew bottles; every downloaded bottle matched its published SHA-256. Libraries were relocated and signed ad hoc locally, without a developer identity or global installation. The runtime provenance is in the ignored validation folder. The standard app still needs QEMU in its search path or explicit runtime overrides.

The legacy `lunaos-0.1.1-x86_64.iso` matched its published local SHA-256 and booted through the real Try Luna CLI using UEFI, x86_64 TCG, two vCPUs, 3072 MiB RAM and an isolated 32 GiB qcow2 disk. Its serial log reached the systemd graphical target in 70.3 seconds and confirmed credential provisioning, Policy Broker and Core startup. This is not proof of a usable desktop or installation. Serial root login required a password; authenticated guest API exercises, desktop usability, install-to-disk and installed reboot were not completed. It is a legacy image result, not validation of the new Omarchy-style image pipeline.

That real run found a macOS file-mode bug: `stat -f %Lp` omitted sticky bits and caused a trusted temporary directory to be refused. It is corrected to `%p`, with a regression observed failing before the fix and passing afterward. The final focused launcher suite passes 14 behavior groups, including real sticky-directory permission handling. The app and unsigned development DMG were rebuilt with this fix.

At the owner's request, the old VM was stopped and its disposable disk removed, all 16 old GitHub ISO artifacts were deleted, the old main-repository ISO workflow was disabled and archived, and the local old ISO/part copies were removed (8,003,379,756 logical bytes). Both OS repositories have no published GitHub releases. Diagnostic serial logs and the boot result were retained; the historical ISO is no longer available locally. No Linux installation or existing user VM was changed.

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
| `bash tests/try-luna.test.sh` after final hardening | 14 behavior groups passed under macOS Bash 3.2, including persistence, no-side-effect planning, path/ownership refusal, locking, HUP/TERM and writable-ancestor refusal. VM tools are injected boundaries here; these tests do not boot QEMU. |
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

- No global QEMU was installed. An isolated native QEMU runtime is available and its doctor check passes with explicit overrides; a normal Finder launch still requires QEMU in the configured search paths. The application does not install it automatically.
- Live GitHub checks found no public releases in `gregpavoine/LunaOS` or `gregpavoine/LunaOS-iso`. A separately verified local LunaOS ISO is required. Historical tags and authenticated Actions ZIPs are not public release images.
- The withdrawn legacy image passed the real UEFI boot/startup check above. A fresh Omarchy-style image, usable desktop, disk installation and installed-system reboot remain unverified.
- No LunaOS ARM factory exists here. Native CPU/GPU performance and inherited clipboard, Touch ID, camera, microphone, battery and folder-sharing integrations are not verified LunaOS features.
- The DMG is an unsigned development artifact. Apple Developer signing, notarization, public app release and bundled QEMU distribution remain outstanding. The current preview requires external QEMU and has no automatic image downloader.
- Source is pushed to `gregpavoine/try-luna` on `codex/try-luna-bootstrap`. A public signed/notarized app release is not available; development DMG artifacts depend on successful Actions builds.

No real Linux host was accessed or modified. No existing VM was started, reset or deleted. No camera, microphone, Accessibility or administrator permission was granted.
