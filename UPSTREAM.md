# Upstream provenance

This repository derives from [omacom/try-omarchy](https://github.com/omacom/try-omarchy), commit `13d63df8da2947f833c04025ff5ade187d39ba81`. Its complete Git history and MIT license are retained. Copyright remains with the upstream contributors for their work.

Try Luna adds a native macOS ISO preview, a Bash/QEMU x86_64 launch adapter, isolated LunaOS VM storage and an ARM factory provenance gate. The inherited Swift package and QEMU bridge sources remain available for native ARM integration. Internal Swift module names, `try-omarchy` guest package names and protocol identifiers remain upstream compatibility names; they do not imply the guest runs LunaOS or that the integrations have passed LunaOS acceptance.

The original app, ARM runtime, guest builder and manuals describe Try Omarchy. They are references until their LunaOS adaptations have passed a real VM test. `Makefile.upstream` exposes only the local test harness; upstream build and publication targets are blocked. Active GitHub Actions are LunaOS checks only.

No Omarchy image is silently downloaded, installed or relabeled as LunaOS. A future ARM factory must be built from the LunaOS source/package/ISO repositories and include the provenance fields documented in [the architecture](docs/luna-architecture.md).
