# Prebuilt dependencies

Pinned third-party binaries and Zig toolchains, published as immutable GitHub
Releases with SHA-256 checksums. Built packages include provenance attestations.

## Zig

`zig/TOOLCHAIN` pins the upstream compiler archives. `zig/fetch` downloads and
verifies them from the unmodified mirror maintained by the `zig` workflow.
Bundle creation and Linux Dawn builds use that mirror without upstream fallback.

The `zig-bundles` workflow adds a compiler-helper cache for Linux x86_64/aarch64,
macOS aarch64, and Windows x86_64. Only the tiny public fixtures under `zig/`
are used. Each bundle is checked on a fresh matching runner before publication.
Set `ZIG_GLOBAL_CACHE_DIR` to its `global-cache` directory to use the seed.
Other CPUs may miss the cache and compile normally. Derived bundles have their
own checksums and attestations; upstream signatures cover only upstream archives.

## Dawn

`dawn/REVISION` pins the source; `dawn/*.cmake` defines build and packaging settings.
The `dawn` workflow builds optimized libraries for Linux x86_64/aarch64, macOS
aarch64, and Windows x86_64. Archives include matching headers and licenses.

Windows provides `webgpu_dawn.dll` and its import library, `webgpu_dawn.lib`,
with D3D12, D3D11 and Vulkan. `bin/` also holds DXC's `dxcompiler.dll`; ship it
beside the executable so D3D12 compiles shaders with DXC on Shader Model 6+
hardware (Dawn falls back to FXC otherwise). `dxil.dll` is not needed. The DLLs
use the static MSVC runtime. Their PDBs ship in a separate symbols archive.

Minimum CPUs are x86-64-v3 (AVX2) on Linux and Windows, ARMv8.2-A on Linux
aarch64, and Apple M1 on macOS.

Linux uses the pinned Zig and its libc++; macOS uses the system libc++ and requires
macOS 26+. Change the revision or recipe, validate the pull request, then merge
to publish new archives. Existing release assets are never replaced.

## CI image

`ci-image/Containerfile` defines the Linux image Lizzie's CI suites and local
container checks run in: Ubuntu 24.04 from a pinned snapshot with Weston 13 and
Mesa lavapipe, Node, and Playwright's headless Chromium with its system libraries.
Node and Playwright match Lizzie's `web/.node-version` and `web/package-lock.json`;
change them together. Zig, Dawn and Wasmtime are not included: Lizzie pins and
caches those itself.

The `ci-image` workflow builds amd64 and arm64 natively and publishes
`ghcr.io/gomerpiles/lizzie-ci:<recipe commit>` with a provenance attestation
(`gh attestation verify oci://ghcr.io/gomerpiles/lizzie-ci@<digest> --repo
GomerPiles/lizzie-deps`). Consumers pin the digest from the run summary. The
package must stay public so pulls need no credentials. Existing tags are never
replaced.
