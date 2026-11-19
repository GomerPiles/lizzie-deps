# Prebuilt dependencies

This repository builds and publishes pinned dependencies, Zig toolchains,
and a Linux CI image.

## Use the artifacts

Choose the archive for your target and ABI from [GitHub Releases](https://github.com/GomerPiles/lizzie-deps/releases).
Pin its exact URL and hash. Library archives include matching headers and
licenses. Their `BUILDINFO.txt` records the sources, recipe, and build settings,
plus link requirements where applicable.

The HarfBuzz `wasm32-freestanding` archive links without libc. Supply font data
as a memory blob and use the undefined-symbol list in `BUILDINFO.txt` to
determine which runtime functions your module needs.

Check the archive against the release's SHA-256 checksum. This command verifies
provenance for artifacts built here.

```sh
gh attestation verify path/to/archive --repo GomerPiles/lizzie-deps
```

The Zig mirror publishes upstream archives and their original signatures.
Derived Zig bundles have their own attestations. To use a bundle's cache seed,
set `ZIG_GLOBAL_CACHE_DIR` to its `global-cache` directory. Bundles also limit
compiler workers through the [build runner patch](zig/build_jobs.zig).

The CI image is published at
[`ghcr.io/gomerpiles/lizzie-ci`](https://github.com/GomerPiles/lizzie-deps/pkgs/container/lizzie-ci).
Pin the image by digest.

## Update a dependency

Update the source pin and adjust the recipe as needed in the same pull request.
The workflows define the target matrix and show how to fetch, build, package, and
test each artifact locally.

| Artifact | Source pins | Workflow |
| --- | --- | --- |
| Dawn | [Revision](dawn/REVISION) | [dawn](.github/workflows/dawn.yml) |
| ngtcp2 with BoringSSL | [Sources](ngtcp2/SOURCES) | [ngtcp2](.github/workflows/ngtcp2.yml) |
| HarfBuzz | [Sources](harfbuzz/SOURCES) | [HarfBuzz](.github/workflows/harfbuzz.yml) |
| Crashpad | [Sources](crashpad/SOURCES), [GN](crashpad/GN) | [crashpad](.github/workflows/crashpad.yml) |
| Zig mirror and bundles | [Toolchain](zig/TOOLCHAIN) | [zig](.github/workflows/zig.yml), [zig-bundles](.github/workflows/zig-bundles.yml) |
| CI image | [Containerfile](ci-image/Containerfile), [Ubuntu sources](ci-image/ubuntu.sources) | [ci-image](.github/workflows/ci-image.yml) |

Pull requests validate the affected recipes. The workflows publish from `main`
after their checks pass. Published releases and image tags are immutable.
After publication, update downstream pins. When changing Zig, rebuild packages
compiled against its bundled libc++ and update their pins alongside the compiler.
