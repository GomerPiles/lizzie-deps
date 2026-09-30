# Prebuilt dependencies

Pinned third-party binaries and Zig toolchains, published as immutable GitHub
Releases with SHA-256 checksums. Built packages include provenance attestations.

## Zig

`zig/TOOLCHAIN` pins the upstream compiler archives. `zig/fetch` downloads and
verifies them from the unmodified mirror maintained by the `zig` workflow.
Bundle creation, Linux Dawn builds and ngtcp2 builds use that mirror without
upstream fallback.

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

## ngtcp2 and BoringSSL

`ngtcp2/SOURCES` pins ngtcp2 and BoringSSL by tag and commit; `ngtcp2/*.cmake`
defines their build settings. The `ngtcp2` workflow builds static libraries for
Linux x86_64/aarch64, macOS aarch64, Windows x86_64 MSVC, and Windows x86_64 GNU
for local cross builds. Archives hold `ngtcp2`, `ngtcp2_crypto_boringssl`,
`ssl` and `crypto` with matching headers and licenses. Minimum CPUs match Dawn's.

BoringSSL needs part of the C++ runtime (`operator delete` and libc++ internals,
with exceptions and RTTI off outside MSVC), so each target is compiled for the
one its final link uses: the pinned Zig's libc++ on Linux and Windows GNU (rebuild
when `zig/TOOLCHAIN` changes), the system libc++ on macOS (26+), and MSVC's on
Windows. MSVC objects name no C runtime, so Zig links the release or debug one.
`BUILDINFO.txt` lists the define and system libraries consumers need.

Each target runs both projects' unit tests and links a smoke test with the
pinned Zig, as Lizzie would: an in-memory QUIC connection to a certificate
pinned by hash. Windows GNU is cross-compiled on Linux, so it runs neither. The
ngtcp2 release lacks `reset_stream_at`, which Safari's WebTransport needs
([ngtcp2#1097](https://github.com/ngtcp2/ngtcp2/pull/1097)).

## CI image

`ci-image/` defines a Linux image with Weston 13, lavapipe, Node, and Playwright's
headless Chromium on a pinned Ubuntu 24.04 snapshot. The `ci-image` workflow
publishes it for amd64 and arm64 as `ghcr.io/gomerpiles/lizzie-ci:<commit>` with a
provenance attestation. Pin its digest. Existing tags are never replaced.
