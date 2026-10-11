# Linux build validation: 6.18.54.1

Validated locally on **2026-10-11**, using an isolated AMD64 Ubuntu 24.04
container emulated by Docker on an ARM64 host. GCC was 13.3.0, pahole 1.25,
and qemu-img 8.2.2. The upstream source was
`d504d40ab83839cb61942a812a99d183c42227b9` (`linux-msft-wsl-6.18.54.1`).

The input was a temporary commit of the local review snapshot,
`a1ba8c34ce479f0fc9852636efb26d3869f7415d`, inside the disposable container.
It is not a GitHub commit or published release. Later documentation additions
record the results; they are not included in that build-source archive.

The [assurance case](ASSURANCE_CASE.md) links the preserved compilation,
packaging, artifact-check, config, and digest records to these conclusions.
Those records are unsigned local observations; the artifact manifest refers to
the original flat build assets, not a future release.

## Results

- Linux Kconfig resolution and the complete fragment validator passed.
- The full kernel and loadable modules compiled; kernel and sample-module BTF
  sections were present. The x86 boot header was valid.
- Perf compiled with the documented flags and ran as
  `perf version 6.18.54.1.gd504d40ab838`.
- The corrected release script completed, producing kernel and build-source
  archives, binaries, metadata, installer, and the SHA-256 manifest.
- All 13 checksum entries passed.
- The VHDX was converted to raw and inspected without mounting it. Extracted
  `modules.dep`, `modules.alias`, a sample module, UAPI `linux/types.h`, and
  `perf/bin/perf` matched the staged files byte-for-byte. The extracted perf
  binary ran, and the module's vermagic matched the recorded kernel release.
- The build script in the packaged build-source archive matched the executed
  script.
- All 14 Python tests, ShellCheck, documentation freshness, and local links
  passed inside AMD64 Linux. Local Actionlint, Compose parsing, and PowerShell
  installer mock suites also passed during the review.

The recorded kernel release is
`6.18.54.1-microsoft-standard-WSL2-ebpf+`. Use the full value from
`kernel-release.txt`; do not construct it by assuming the trailing `+` is absent.

| Artifact | Size (bytes) | SHA-256 |
|---|---:|---|
| `bzImage` | 20788224 | `8556b3b0f912a96d9b3ec9cb4d9925f458a27abb6a5177cbe10bf4bac8c43558` |
| `modules.vhdx` | 1115684864 | `05da7be1d27fdbf33cddb3a4787ce36d3fec8a9a0d2e356c5851daac57b88702` |

## Packaging fix found by the clean build

Without `kmod`, `make modules_install` reported that `depmod` was missing and
continued without module dependency/alias metadata. The release workflow and
README now install `kmod` explicitly, with `e2fsprogs` for image tooling. The
build script checks for `depmod` before compilation and refuses to package a
VHDX unless `modules.dep` and `modules.alias` are populated. A negative check
confirmed that hiding `depmod` fails before `dist/` is created. The corrected
build then passed the artifact checks above.

## Remaining acceptance

This validates Linux compilation and packaging. It does not validate Windows
installation, WSL boot, the minimum WSL version for the artifact layout, actual
module loading, OBI attachment or propagation, Tetragon enforcement, Cilium
networking, or rollback. Follow [release acceptance](RELEASE_ACCEPTANCE.md) on
the target Windows/WSL host.

Local checksums are integrity evidence, not signed origin proof. GitHub release
immutability and build attestations were not generated or exercised by this
local build. Verify those against the eventual release's exact assets using the
[README policy](../README.md).
