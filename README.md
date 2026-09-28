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

Windows provides separate static and shared packages from one compilation. The
static package contains `webgpu_dawn.lib`; the shared package contains
`webgpu_dawn.dll` and its import library, `webgpu_dawn_dll.lib`. Both packages
include `dxcompiler.dll` and the Windows SDK's `dxil.dll` in `bin/` for Dawn's
built DXC support; applications using Dawn's `use_dxc` toggle must ship those
DLLs beside the executable. D3D11 continues to use FXC. DLL symbols ship
separately. Both packages use the static MSVC runtime; static consumers need a
compatible MSVC C++ runtime and Windows SDK libraries.

Linux uses the pinned Zig and its libc++; macOS uses the system libc++ and requires
macOS 26+. Change the revision or recipe, validate the pull request, then merge
to publish new archives. Existing release assets are never replaced.
