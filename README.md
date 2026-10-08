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

## Crashpad

`crashpad/SOURCES` pins Crashpad and the dependencies its GN graph uses;
`crashpad/GN` pins and checksums its GN binaries. The Zig recipe in
`crashpad/recipe.zig` fetches, builds, packages and tests four native targets.
It preserves upstream GN/Ninja and upstream Python build actions. First-party
orchestration uses the compiler pinned in `zig/TOOLCHAIN`.

Linux x86_64/aarch64 uses the pinned Zig's libc++ and glibc 2.28, with the same
CPU baselines as Dawn. macOS uses AppleClang, system libc++, Apple M1 and macOS
26. Windows uses native MSVC, AVX2 and the static CRT. Each archive records its
actual compiler, Ninja and GN versions, sources, target and flags in `BUILDINFO.txt`.
Linux runtime dependencies are also recorded and checked for unexpected dynamic
C++/curl libraries. Rebuild Linux packages whenever the Zig pin changes.
Linux embeds the pinned zlib source, keeping host headers and libraries out of
Zig's glibc 2.28 build; macOS uses system zlib and Windows also embeds zlib.

Packages expose only `include/lizzie_crashpad.h`: a small C ABI for registration,
bounded annotations, prepared attachment paths, on-demand capture and releasing
the metadata owner. Native packages contain a complete `liblizzie_crashpad.a`;
Windows contains `lizzie_crashpad.dll` and its import library, serving both Zig
MSVC and GNU builds. All packages include the handler, database utility,
annotation inspector and compiled dependency notices. The public header owns
lifetime constraints; the DLL stays loaded through process exit. This is a
concrete boundary for Lizzie, not a general Crashpad C++ SDK.

Collection is local: the bridge supplies no upload URL, disables database
uploads, and disables periodic tasks and handler restart. Linux uses upstream's
socket HTTP backend without TLS to avoid a curl dependency; adding secure uploads
requires a deliberate recipe change. The application owns diagnostic files and
report retention. Symbols, Wasmtime and application recording policy are outside
this package; the game integration must validate guest-trap coexistence separately.

The `crashpad` workflow runs package smoke tests through Zig on each native
runner: on-demand capture, Zig panic and worker-thread fault, checking dump
streams, copied evidence, annotations and disabled uploads. Windows runs those
tests using both Zig ABIs against the same DLL. These are dependency-production
checks, separate from game CI. PRs publish nothing; main publishes checksummed,
attested archives only after every target passes.

For local development, set `ZIG` to the pinned compiler and put Ninja, CMake,
Python 3, Git and curl on PATH. Windows
needs Visual Studio C++ tools and a Windows SDK. Use fresh output and smoke
directories:

```sh
"$ZIG" build-exe crashpad/recipe.zig -O ReleaseSafe -femit-bin=recipe
./recipe fetch s
./recipe tools t
./recipe build aarch64-macos s b t
./recipe package aarch64-macos s b o "$(git rev-parse HEAD)"
./recipe smoke aarch64-macos o/crashpad-*-aarch64-macos smoke
```

The Windows build forwards GN's extra compiler flags into the pinned
mini_chromium x64 MSVC invocation, which otherwise ignores them. This narrowly
checked recipe patch ensures `/MT` and `/arch:AVX2` reach every translation unit;
remove it when upstream forwards those args itself.
Linux also narrowly patches upstream's zlib selection to use its existing
embedded build and applies that build's existing warning settings on Linux;
remove those patches when GN supports this configuration directly.

## CI image

`ci-image/` defines a Linux image with Weston 13, lavapipe, Node, and Playwright's
headless Chromium on a pinned Ubuntu 24.04 snapshot. The `ci-image` workflow
publishes it for amd64 and arm64 as `ghcr.io/gomerpiles/lizzie-ci:<commit>` with a
provenance attestation. Pin its digest. Existing tags are never replaced.
