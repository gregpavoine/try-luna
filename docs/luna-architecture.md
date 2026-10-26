# Try Luna architecture

The repository reuses Try Omarchy at the pinned revision in UPSTREAM.md. LunaOS owns the app identity `io.lunaos.tryluna.preview`; its VM state is separate from Try Omarchy. The current product adds an ISO launch adapter to the existing native Swift executable rather than changing the LunaOS system architecture.

## Current ISO preview

`macos/LunaInfo.plist` selects `LunaLaunchMode=iso`. The Swift entrypoint calls the native ISO launcher, which accepts an explicit local ISO and resource settings. It starts the bundled `try-luna` script through `/bin/bash`, passing an argument array without shell interpolation. The script validates inputs, resolves QEMU and UEFI firmware, owns a lock for the VM lifetime and creates only that VM's qcow2 disk and private variable store. Installation and subsequent boots use the same virtual disk. ISO mode uses standard x86_64 QEMU; an Apple Silicon Mac uses TCG emulation.

The preview has no automatic image download or dependency installation. The app does not request camera, microphone, Accessibility or administrator permissions. QEMU is a separate prerequisite. `make app` compiles the real Swift executable and packages a local app; `make dmg` wraps it in an unsigned development disk image. Apple Developer signing, notarization, native CPU performance and OS acceptance are separate release requirements.

## Native ARM integration

The upstream ARM runtime, factory handling and guest integration sources are retained. Their original guest-specific names remain compatibility identifiers. The default LunaOS Makefile does not build a stock Omarchy image, publish to Omarchy or invoke upstream signing credentials. The preserved Makefile only allows local test goals.

The ARM `factory.json` must retain format `1`, kind `upstream-shell-factory`, platform `aarch64` and boot `uefi-limine`, and add:

```json
{
  "distribution": {
    "id": "lunaos",
    "source_repository": "https://github.com/gregpavoine/LunaOS",
    "source_revision": "0123456789abcdef0123456789abcdef01234567"
  }
}
```

The revision above illustrates the field format only. It is not an approved source or a bootable image. The guard rejects missing or foreign metadata before storage changes; existing digest verification remains in the upstream factory path. This metadata prevents accidental use of a stock image. A trusted image build must additionally verify the disk's actual `/etc/os-release`, included packages and boot/runtime behavior; self-declared JSON is not cryptographic attestation.

## Release dependencies

A testable ISO preview needs a trusted x86_64 LunaOS ISO and a real QEMU boot/install/reboot check. Native Apple Silicon performance additionally needs a signed, verified LunaOS ARM factory image, guest bridge packaging and an end-to-end run on the Mac. No image, package or test fixture is substituted for these requirements.
