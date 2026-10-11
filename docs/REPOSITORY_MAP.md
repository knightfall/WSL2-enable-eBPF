# Repository map

This project supplies a WSL2 kernel configuration/build guide and supporting
tooling. It has no application server or persistent data store. Bash orchestrates
Git and Kconfig; Python validates configuration and chooses upstream release tags.

## Read first

- [Agent instructions](../AGENTS.md): scope, indexing boundaries, invariants, and checks.
- [Installation and runtime guide](../README.md): the complete WSL setup and rollback flow.
- [Kernel option explanations](../KERNEL_CONFIG_EXPLAINED.md): the requested profile and dependencies.
- [Source lock](../kernel-version.env): current release tag, upstream URL, and immutable commit.

## File responsibilities

| Path | Responsibility |
|---|---|
| `.gitmodules`, `WSL2-Linux-Kernel/` | Registered Microsoft kernel submodule; the gitlink is the build's source pin |
| `kernel-version.env` | Human-readable release/commit lock checked against the gitlink |
| `ebpf-kernel.config` | Requested built-in eBPF, tracing, network, storage, and enforcement options |
| `scripts/build-release.sh` | Compile and package binaries, checksums, metadata, and exact source archives |
| `scripts/Install-WslEbpfKernel.ps1` | Verify immutable assets and signed provenance for an explicit tag; back up and merge Windows settings |
| `.github/workflows/release.yml` | Pinned Actions, version-tag build, provenance attestation, and draft release publication |
| `scripts/prepare-kernel.sh` | Check lock/gitlink agreement and initialize the pinned submodule |
| `scripts/configure-kernel.sh` | Back up `.config`, merge the fragment, preserve LSMs, resolve dependencies |
| `scripts/check-config.py` | Fail on missing/changed options, invalid input, or absent BPF LSM activation |
| `scripts/verify-runtime.sh` | Compare the running release; check BTF, mounts, LSMs, BPF probes, optional Tetragon probes |
| `scripts/update-kernel.py` | Discover stable tags in the pinned series and stage a verified submodule/lock update |
| `scripts/write-update-pr-body.py` | Render the kernel-update PR description from release and GitHub run metadata |
| `scripts/validate-repository.sh` | Run lint, link/bundle checks, unit tests, and Compose parsing |
| `scripts/check-links.py` | Validate local links in project docs and LLM navigation files |
| `scripts/build-llms.py` | Generate or check the combined documentation bundle |
| `tests/` | Standard-library Python tests for config parsing/requirements and release selection |
| `examples/compose.yaml`, `examples/.env.example` | Versioned OBI agent and optional HTTP smoke target |
| `.github/dependabot.yml` | Weekly grouped updates for SHA-pinned GitHub Actions |
| `.github/workflows/validate.yml` | Repository checks and pinned-kernel Kconfig resolution on Linux |
| `.github/workflows/update-kernel.yml` | Weekly/manual discovery, candidate validation, managed branch, update PR |
| `llms.txt`, `llms-full.txt` | Curated navigation index and generated documentation bundle |

The source directory may be uninitialized until `scripts/prepare-kernel.sh` runs.
Do not treat its absence as an application source-code gap.

## OBI-only flow

The README provides a managed-kernel path: check the running version and exposed
BTF, supply the selected OBI capabilities and example mounts, then run the OBI
Compose smoke test on Docker Engine inside the target WSL distro. A custom
kernel, BPF LSM activation, and the combined-profile validators are not baseline
OBI prerequisites. Microsoft 6.6.123.2 and 6.18.54.1 source configs already supply
core BPF/BTF/tracing support; runtime compatibility remains separately tested.

## Custom kernel build and verification flow

```text
Git submodule pin + source lock
  -> prepare-kernel.sh verifies and initializes source
  -> configure-kernel.sh merges Microsoft base + ebpf-kernel.config
  -> preserve existing CONFIG_LSM, append bpf
  -> olddefconfig resolves dependencies
  -> check-config.py verifies requested values
  -> README build commands compile kernel and package modules.vhdx
  -> Windows .wslconfig selects artifacts
  -> verify-runtime.sh probes the running WSL kernel
  -> OBI / Tetragon / Cilium workload-specific smoke tests
```

The PowerShell installer downloads published versioned artifacts and updates
`.wslconfig` with a backup. The release workflow creates drafts for manual Windows
acceptance testing before publication. Kernel support
does not install the agents or prove a particular enforcement/networking policy.

## Upstream update flow

The update workflow checks release metadata before downloading source. If a newer
stable tag exists in the current major/minor series, it initializes the existing
pin, fetches and verifies the new tag's commit, then stages both the gitlink and
source lock. Repository checks and Linux Kconfig resolution must pass before it
publishes `automation/update-wsl-kernel` and opens/refreshes a PR.

Numeric comparison avoids lexicographic tag ordering. Annotated tags use their
peeled commit. Prereleases and different series are excluded. A missing/moved
current tag fails for manual investigation. Identical pending trees retain their
existing commit; changed trees use an explicit lease when updating the managed
branch. A maintainer reviews and merges; Windows boot and workload validation
remain separate acceptance checks.

## Where to investigate a problem

| Symptom | Start here |
|---|---|
| Fresh clone cannot fetch/initialize the kernel | `.gitmodules`, source lock, `prepare-kernel.sh` |
| An option disappears or becomes modular | Fragment, `check-config.py`, and the exact pinned upstream Kconfig dependency |
| BPF LSM compiled but unavailable | `configure-kernel.sh`, active LSM list, Windows `lsm=` override |
| OBI fails a custom-profile verifier | README OBI-only path; these validators require the whole custom profile |
| OBI cannot observe another process/container | Compose capabilities, daemon host, host PID namespace, mount types |
| Updater selects an unexpected release | `select_release` in `update-kernel.py` and `tests/test_update_kernel.py` |
| CI fails | The failing workflow step, then the corresponding script; do not weaken checks to hide a dependency |
| Agent index is too large or duplicated | Exclude the upstream submodule/artifacts; choose individual docs or the full bundle |

## Indexing boundaries

Index first-party scripts, tests, workflows, examples, root configuration, and
documentation. Exclude the upstream kernel tree from default indexing, and fetch
specific upstream paths at the source-lock commit when needed. Exclude Git
metadata, caches, compiled kernel/modules, VHDX images, and the local `.env`.

`llms.txt` and `AGENTS.md` are guidance and navigation, not crawler enforcement.
The full bundle is generated from a fixed documentation allowlist; use the
source pages when exact implementation behavior matters.

## Evidence

- [Source initialization](../scripts/prepare-kernel.sh)
- [Kernel configuration](../scripts/configure-kernel.sh)
- [Configuration validation](../scripts/check-config.py)
- [Runtime validation](../scripts/verify-runtime.sh)
- [Release selection/update](../scripts/update-kernel.py)
- [Update PR description](../scripts/write-update-pr-body.py)
- [Validation workflow](../.github/workflows/validate.yml)
- [Scheduled update workflow](../.github/workflows/update-kernel.yml)
