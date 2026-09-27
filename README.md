# lizzie-deps

Prebuilt third-party libraries for [Lizzie](https://github.com/GomerPiles/lizzie),
built from upstream source by GitHub Actions and published as GitHub Releases.
Nothing here is stored as an Actions artifact; binaries go straight to a release,
which does not count against Actions or Packages storage.

Every published archive has a `.sha256` file beside it and a signed build
provenance attestation that ties it to the workflow run and recipe commit:

```sh
gh attestation verify dawn-<rev>-<target>.tar.gz --repo GomerPiles/lizzie-deps
```

Consumers pin the archive URL and SHA-256. Releases are never replaced; a new
recipe or upstream revision produces a new release.

## Dawn

| File | Owns |
| --- | --- |
| `dawn/REVISION` | Upstream [google/dawn](https://github.com/google/dawn) commit |
| `dawn/common.cmake` | Settings shared by every target |
| `dawn/<target>.cmake` | Backends, library type and platform settings for one target |
| `dawn/package.cmake` | Install, license collection, `BUILDINFO.txt`, archives and checksums |
| `dawn/zig/` | `zig cc`/`c++`/`ar`/`ranlib` wrappers and the pinned Zig (`TOOLCHAIN`) for Linux |
| `.github/workflows/dawn.yml` | Runner per target, build, attestation and release |

| Target | Runner | Output |
| --- | --- | --- |
| `aarch64-macos` | `macos-26` | Metal; static `lib/libwebgpu_dawn.a`; macOS 26.0+; system libc++ |
| `x86_64-linux-gnu` | `ubuntu-24.04` | Vulkan, Wayland WSI; static `lib/libwebgpu_dawn.a`; built by `zig c++`; glibc 2.28+, Zig's libc++ |
| `aarch64-linux-gnu` | `ubuntu-24.04-arm` | Same as x86_64 |
| `x86_64-windows` | `windows-2025` | D3D12, D3D11, Vulkan; `bin/webgpu_dawn.dll` + `lib/webgpu_dawn.lib`; static MSVC runtime; system FXC, no DXC; PDB in `-symbols` archive |

Each archive is `dawn-<rev12>-<target>.tar.gz` with a single root directory of
the same name containing `include/`, `lib/`, `bin/` (Windows), Dawn's `LICENSE`,
`notices/` for compiled-in dependencies, and `BUILDINFO.txt` with the exact
revisions, compiler and effective CMake settings. Release builds carry no debug
info, except Windows: its `webgpu_dawn.pdb` ships separately as
`dawn-<rev12>-x86_64-windows-symbols.tar.gz` (PDB, `LICENSE`, `BUILDINFO.txt`).

Linux archives are compiled by the Zig pinned in `dawn/zig/TOOLCHAIN` against
Zig's bundled libc++, so they carry no libstdc++ dependency. Consumers must link
libc++ from the same Zig version (`linkLibCpp()`); keep `TOOLCHAIN` equal to
Lizzie's `zig-toolchain.lock` and rebuild Dawn when that pin changes.

### Changing the build

- **Bump Dawn:** edit `dawn/REVISION`.
- **Change settings:** edit `dawn/common.cmake` or a target file.
- **Add a target:** add `dawn/<target>.cmake` and a matrix entry in
  `dawn.yml`. If its library layout differs, extend the check in `package.cmake`.

Pull requests that touch `dawn/` or `dawn.yml` build every target without
publishing. Merging such a pull request builds again on `main` and publishes
release `dawn-<rev12>-<recipe7>`; then copy each archive's URL, byte size and
SHA-256 from the release notes into Lizzie's pins. To retry a failed publish,
run the **dawn** workflow on `main` manually (Actions → dawn → Run workflow).

### Building locally

Requires CMake 3.22+, Ninja (or Visual Studio on Windows), Python 3 and Git.
Linux targets also need the pinned Zig as `zig` on `PATH` or in `$ZIG`; they
cross-compile from any host.

```sh
git init -q d && git -C d fetch --depth 1 https://github.com/google/dawn.git $(cat dawn/REVISION)
git -C d checkout -q FETCH_HEAD
cmake -S d -B b -G Ninja -C dawn/aarch64-macos.cmake
cmake --build b --config Release
cmake -D SOURCE_DIR=d -D BINARY_DIR=b -D TARGET=aarch64-macos -D RECIPE_COMMIT=local -D OUTPUT_DIR=o -P dawn/package.cmake
```
