# Try Luna contributor instructions

Try Luna is the LunaOS macOS VM launcher, derived from omacom/try-omarchy. Read README.md, UPSTREAM.md and docs/luna-architecture.md before editing.

- The current product is the native Swift/AppKit ISO launcher and root `try-luna` Bash command. Use `make` for builds and tests.
- Keep macOS 15+ and the built-in Bash 3.2 supported for the host launcher. Use native Swift and standard macOS tools; no Python interpreter on the preview launch path.
- Reuse upstream native VM, storage and bridge code. Existing Omarchy-specific sources and docs are upstream references, not evidence of working LunaOS integrations. Do not run their stock-image factory or publishing scripts.
- No public LunaOS release or ARM factory image is currently available. Never substitute Omarchy or a test fixture for LunaOS. The ARM guard requires LunaOS distribution and source provenance metadata before any factory build or launch.
- Keep root ISO-emulation state under a Luna-specific user directory, separate from Try Omarchy data. Only create virtual files there. Never accept host block devices, overwrite an existing VM disk, or remove a user's VM. Treat paths, manifests and guest input as untrusted.
- No remote Linux connection without an owner-provided SSH alias and explicit authorization. No changes to a real Linux installation without verified recovery and explicit authorization. Do not install Omarchy on macOS.
- Mac permissions, developer signing identities, notarization and publication require the owner's action. Local builds do not use credentials or grant Mac permissions. Do not push unless the owner asks; the owner currently handles pushes.
- Tests and build logs prove only what they exercise. Record actual compile, UI and VM results in docs/STATUS.md. A passing source test or compiled app does not prove LunaOS boots, installs or supports the inherited guest bridges.
- Public Mac app releases must pass native bundle signature verification, resource-tamper regression, Developer ID signing, Apple notarization/stapling and Gatekeeper assessment on the distributed copy. An ad hoc CI artifact is a development build, not a Gatekeeper-approved release. Never fix a packaging failure by removing quarantine or disabling Gatekeeper.
- Preserve upstream copyright, licenses and attribution. Commit coherent changes, keep Markdown lines unwrapped, and protect secrets and private data.
