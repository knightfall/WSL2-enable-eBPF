# Agent guide

## Project and scope

This repository builds and documents a custom x86-64 WSL2 kernel profile for
eBPF observability and networking. It contains Bash/Python tooling, a kernel
configuration fragment, Compose examples, and GitHub Actions workflows. It does
not implement Linux, Tetragon, Cilium, Envoy, or OBI themselves.

Start with [the repository map](docs/REPOSITORY_MAP.md) and [README.md](README.md).
Use [llms.txt](llms.txt) as the navigation index. [llms-full.txt](llms-full.txt)
is a generated documentation bundle for consumers that prefer one input file.
Source files remain authoritative when prose and implementation disagree.

## Browsing and indexing

- Search this project's `scripts/`, `tests/`, `examples/`, `.github/workflows/`,
  root documentation, and configuration first.
- Treat `WSL2-Linux-Kernel/` as vendored upstream source. Exclude it from default
  repository indexing and broad searches; inspect specific upstream files only
  when a kernel dependency or behavior needs verification.
- Exclude `.git/`, Python caches, the local `examples/.env`, kernel build output,
  modules/VHDX images, and `kernel-release.txt` from knowledge indexes.
- Index individual documentation pages or `llms-full.txt`, rather than both,
  when duplicate text would impair retrieval.
- Relative links in `llms.txt` resolve against the checked-out repository or
  the URL serving that file. These files guide browsing; they do not force a
  crawler to index the repository or enforce access restrictions.

## Source and update invariants

- Keep the kernel submodule gitlink and `KERNEL_COMMIT` in `kernel-version.env`
  identical. `KERNEL_TAG` must resolve to that commit.
- Keep the repository URL and tracking series consistent between `.gitmodules`
  and the source lock. The scheduled updater stays in the current stable series.
- Initialize with `scripts/prepare-kernel.sh`; ordinary builds must use the
  committed pin, not `git submodule update --remote`.
- Preserve local source/configuration changes. Review `git status --short`
  before edits and do not reset a dirty submodule to make validation pass.
- Keep changes to upstream kernel files separate from this repository's tooling.
  A kernel-series upgrade requires review of symbols, packaging, and runtime
  compatibility; it is not an automatic weekly bump.

## Kernel configuration

- Add desired options to `ebpf-kernel.config`; do not edit Microsoft's tracked
  base config. Add missing parent dependencies instead of weakening the validator.
- `scripts/configure-kernel.sh` starts from the pinned Microsoft base, merges the
  fragment, appends `bpf` to the existing LSM order, resolves Kconfig, and checks
  all requested values. Preserve the other LSMs when changing this flow.
- `CONFIG_BPF_LSM=y` alone does not activate BPF LSM. Runtime activation also
  depends on the LSM list and any `lsm=` command-line override.
- Tetragon's kprobe `Override` requires `FUNCTION_ERROR_INJECTION` and
  `BPF_KPROBE_OVERRIDE`. These requirements differ from ordinary observation.
- Keep the custom local-version suffix so the runtime check can distinguish
  this profile from the managed Microsoft kernel.

## Validation and environments

Run lightweight checks from the repository root:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/build-llms.py --check
python3 scripts/check-links.py
for script in scripts/*.sh; do bash -n "$script"; done
```

`scripts/validate-repository.sh` additionally needs ShellCheck and Docker Compose
v2. Compose parsing does not require a running Docker daemon. Use Actionlint for
workflow changes when available. Tests use Python's standard-library `unittest`;
no Python package installation is needed for the tooling.

Kernel configuration/builds require x86-64 Linux and the prerequisites in the
README. Use a case-sensitive Linux filesystem. macOS and Windows host filesystems
may collapse distinct upstream kernel filenames and create apparent source
changes. Hosted Linux CI validates Kconfig resolution, not a full kernel build.

Only claim checks that were actually executed. Distinguish static/lint/unit
checks, Linux configuration resolution, full compilation, WSL boot, runtime BPF
probes, and application smoke tests. Follow the README's rollback and runtime
verification procedures when testing on Windows/WSL.

## Workflows and containers

The scheduled update workflow creates/refreshes
`automation/update-wsl-kernel` and an update PR after configuration validation.
It never merges automatically. Keep no-op discovery lightweight, preserve an
identical pending commit, and retain the explicit force-with-lease check for
changed managed branches. The repository's default workflow token remains
read-only; the update job requests contents and pull-request writes, while the release draft
job requests contents writes. Release builds request OIDC and attestation writes,
keep contents read-only, and create drafts
for Windows acceptance testing before publication. Preserve fail-closed verification
of immutable assets and provenance against the fixed repository, workflow, and tag.

The Compose example targets Docker Engine inside the WSL distro. Docker Desktop
has a separate daemon environment; do not imply that a user-distro mount or PID
namespace automatically reaches Desktop workloads. Keep broad agent privileges
and relaxed sandbox profiles explicit in documentation.

## Documentation maintenance

Update the README and repository map when entry points or workflow behavior
change. `llms.txt` is the small, curated index; keep it useful without embedding
the full upstream kernel tree. After changing documentation, regenerate the
bundle and verify it:

```bash
python3 scripts/build-llms.py
python3 scripts/build-llms.py --check
```

Do not edit `llms-full.txt` directly. The generator includes a bounded allowlist
of project documentation, normalizes local links, and excludes vendored source,
build artifacts, and local environment files.
