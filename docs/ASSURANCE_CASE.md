# Factual assurance case and validation evidence

**Review date:** 2026-10-11

**Status:** Source and local Linux build evidence established; release and WSL acceptance open.

**Repository baseline:** `40ce0af43f82550b1ec31061d32e73bd2b2d3ffd` plus the uncommitted local changes described here.

This document records an evidence-supported argument for the repository's
technical claims. It is not a mathematical proof, signed certification, or
claim that every application mode works. It connects each conclusion to its
source or observed result and states what remains to be demonstrated.

## 1. Scope and identities

The argument covers the x86-64 custom kernel profile, documentation, source
selection, local build and packaging, and the stated verification policy.
It distinguishes kernel mechanisms from application integration and runtime
behavior. ARM64 custom-kernel support is outside this profile.

| Input | Reviewed identity | Role |
|---|---|---|
| Previous Microsoft kernel | `linux-msft-wsl-6.6.123.2`, commit `a07f9ea8a99139913acbcc1c160b132cb2a49c81` | Source-config comparison |
| Current Microsoft kernel | `linux-msft-wsl-6.18.54.1`, commit `d504d40ab83839cb61942a812a99d183c42227b9` | Pinned build source |
| OBI | `v0.14.0` | Versioned support and implementation evidence for the example |
| Local build tooling snapshot | `a1ba8c34ce479f0fc9852636efb26d3869f7415d` | Temporary commit inside the disposable build container |
| Linux build environment | AMD64 Ubuntu 24.04 emulated on ARM64 Docker; GCC 13.3.0, pahole 1.25, qemu-img 8.2.2 | Observed compilation/packaging environment |

The temporary tooling commit is not a repository or GitHub commit. The built
assets belong to that snapshot. Subsequent documentation and comment changes,
including this evidence document and the config checker's docstring, are not
contained in its source archive. Evidence of that build does not establish the
identity of binaries produced by a later commit.

## 2. Argument and supported conclusions

**G0 — The repository may describe the mechanisms enabled by its pinned profile
and the observed local Linux build, provided application and WSL claims retain
their stated conditions.**

| Claim | Argument | Evidence | Disposition |
|---|---|---|---|
| C1: Source selection is explicit | Lock, gitlink, and tracking series identify the current source; saved config targets match upstream blob identities | E1, E2 | Established for this snapshot |
| C2: The compared bases contain core OBI prerequisites | Config values plus OBI's versioned baseline support starting with the managed kernel; this is not a stock-WSL smoke test | E2, E3, E4 | Source-supported; runtime conditional |
| C3: The custom fragment has a defined delta | All 95 assignments are compared; 39 differ from the 6.18 base: five disabled/absent to built-in, 33 modular to built-in, and the version suffix | E2, E3 | Reproducible explicit-assignment comparison |
| C4: Kconfig preserves the requested profile | Resolved config satisfies every fragment assignment and includes `bpf` in `CONFIG_LSM` | E5, E6 | Configuration established; active LSM remains a runtime check |
| C5: The Linux build and packaging path works for the tested inputs | Kernel/modules/perf built; corrected packaging completed; extracted image contents matched staging | E6, E7, E8 | Established for the dated local build |
| C6: Documentation claims have traceable factual review | Mechanisms, conditions, and contracts were audited; incorrect and unsupported groups were corrected and rechecked | E9, E10 | Bounded source/contract review |
| C7: The verification policy demands origin and integrity evidence | Installer and draft instructions bind verification to repository, workflow, tag and hosted runner policy; publication adds immutable-release checks | E11 | Policy/source and mock-test evidence; live release verification open |
| C8: No WSL or application certification follows from C1–C7 | Boot, module discovery/loading, application hooks, propagation and rollback need target-host tests | E12 | Open acceptance obligations |

### Key deductions and boundaries

- Microsoft source configs already enable core BPF/BTF/tracing prerequisites;
  this does not identify the kernel actually installed on a user's machine.
- `NET_SOCK_MSG` and receive-side `BPF_STREAM_PARSER` are different mechanisms.
  The latter's disabled base value does not establish absent SK_MSG support.
- `CONFIG_LSM` is configuration evidence. Only the running system's active list
  establishes BPF LSM activation for that boot.
- Classic tc classifier/qdisc attachment is distinct from TCX. The pinned base
  disables netkit and the fragment does not enable it; no netkit deployment is
  certified by this profile.
- Kernel options enable infrastructure. Child dependencies, selected backend,
  privileges, runtime policy, routing, keys and application configuration can
  still be required. No comparative performance result is inferred.

## 3. Evidence register

All preserved records are under [evidence/2026-10-11](evidence/2026-10-11/).

| ID | Evidence | What it supports and limits |
|---|---|---|
| E1 | [Source lock](../kernel-version.env), [submodule declaration](../.gitmodules), Git gitlink, [upstream identities](evidence/2026-10-11/UPSTREAM_IDENTITIES.json) | Intended source identity; GitHub/TLS and Git object identity remain trust assumptions |
| E2 | [6.6 target config](evidence/2026-10-11/microsoft-6.6.123.2.config), [6.18 target config](evidence/2026-10-11/microsoft-6.18.54.1.config) | Exact saved comparison inputs, verified against upstream config blob IDs |
| E3 | [Explicit config comparison](evidence/2026-10-11/CONFIG_COMPARISON.tsv) | 95 assignments and their base/requested values; `n` represents disabled or absent. Not a full upstream-series diff or Kconfig-resolution result |
| E4 | [OBI v0.14.0 support matrix](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/v0.14.0/SUPPORT_MATRIX.md), [context injector](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/blob/v0.14.0/bpf/tpinjector/tpinjector.c) | Documented baseline and selected implementation paths; not a WSL execution result |
| E5 | [Resolved config](evidence/2026-10-11/resolved-kernel.config), [config validator](../scripts/check-config.py), [fragment](../ebpf-kernel.config) | Exact requested settings and configured LSM inclusion; not runtime availability |
| E6 | [Compilation log](evidence/2026-10-11/compilation.log), [corrected packaging log](evidence/2026-10-11/packaging.log), [build exit code](evidence/2026-10-11/build-exit-code.txt) | Kernel compilation and corrected end-to-end packaging. The first log contains an initial fixture failure and the original missing-depmod warning; that packaging attempt was stopped. The second log and exit code record the corrected run |
| E7 | [Artifact checks](evidence/2026-10-11/artifact-checks.log), [kernel sections](evidence/2026-10-11/vmlinux-sections.txt), [sample-module sections](evidence/2026-10-11/sample-module-sections.log), [artifact manifest](evidence/2026-10-11/artifact-SHA256SUMS), [build metadata](evidence/2026-10-11/build-info.txt) | All 13 manifest hashes passed; BTF, boot header, extracted metadata/header/perf/module comparisons passed. Logs are observations, not signed attestations |
| E8 | [Missing-depmod negative check](evidence/2026-10-11/missing-depmod.log), [build script](../scripts/build-release.sh), [build report](VALIDATION_6.18.54.1.md) | Fail-early dependency fix and populated metadata safeguards; a failed preflight is separate from Windows module loading |
| E9 | [Independent claim ledger](evidence/2026-10-11/CLAIM_AUDIT.md) | 161 grouped review entries, including 92 option headings covering the fragment's 95 settings. Historical statuses and line numbers precede corrections; the resolution section records their disposition. Not an exhaustive proof of every atomic statement or future product version |
| E10 | [Local check record](evidence/2026-10-11/local-checks.log) | Executed tests, lint, navigation and documentation checks, with exit codes; no live GitHub/Windows attestation verification |
| E11 | [Installer](../scripts/Install-WslEbpfKernel.ps1), [release workflow](../.github/workflows/release.yml), [draft procedure](RELEASE_ACCEPTANCE.md), [GitHub attestation model](https://docs.github.com/en/actions/concepts/security/artifact-attestations), [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) | Verification contract and public trust model; authenticity must still be exercised on the exact eventual release |
| E12 | [Release acceptance guide](RELEASE_ACCEPTANCE.md) | Concrete open acceptance procedure; instructions are not evidence of completion |

### Configuration blob identities

The saved inputs are the actual x86 config targets. Their Git blob IDs match
GitHub's contents responses at the immutable upstream commits:

| Config | Git blob ID |
|---|---|
| 6.6.123.2 x86 config | `cc3d37e1d0c41c68a0faa79737b0dd3c7060b9ff` |
| 6.18.54.1 x86 config | `a10691770ef515a454c32f3f4704d37eac6554ad` |

Git blob IDs identify Git content; they are not signed publisher attestations.
The SHA-256 evidence manifest below separately fingerprints the saved records.

## 4. Integrity and reproducible checks

[EVIDENCE_SHA256SUMS](evidence/2026-10-11/EVIDENCE_SHA256SUMS) fingerprints the
preserved records. It excludes itself. It detects changes against the recorded
manifest, but is unsigned and can be replaced together with those records.
It does not independently authenticate the author or prove that a logged
execution occurred.

[REVIEWED_INPUTS_SHA256SUMS](evidence/2026-10-11/REVIEWED_INPUTS_SHA256SUMS)
fingerprints the documentation and first-party inputs at this review boundary.
It excludes this assurance document, the generated bundle, and the raw audit
records to avoid a circular self-hash. If any covered input changes, repeat the
relevant review before refreshing the recorded digest. A stale manifest must
not be treated as proof of current content.

From the repository root:

```bash
(cd docs/evidence/2026-10-11 && sha256sum --check EVIDENCE_SHA256SUMS)
sha256sum --check docs/evidence/2026-10-11/REVIEWED_INPUTS_SHA256SUMS
python3 scripts/check-config.py docs/evidence/2026-10-11/resolved-kernel.config
python3 scripts/build-llms.py --check
python3 scripts/check-links.py
```

On macOS, use `shasum -a 256 -c` in place of `sha256sum --check`.
The saved `artifact-SHA256SUMS` instead refers to the build's flat `dist/`
assets. Those binaries and archives are not included in the documentation
evidence directory; checking that manifest requires the actual matching assets.
The stopped local Docker container `wsl-ebpf-review-20261011` retained them at
`/work/repo/dist` when this record was written. That container name is a local
retrieval aid, not a portable or permanent evidence location.

To reproduce E3 from the preserved config inputs and the current fragment:

```bash
python3 - <<'PY'
from pathlib import Path
import re
root = Path('docs/evidence/2026-10-11')
assignment = re.compile(r'^(CONFIG_\w+)=(.+)$', re.M)
read = lambda path: dict(assignment.findall(path.read_text()))
old = read(root / 'microsoft-6.6.123.2.config')
new = read(root / 'microsoft-6.18.54.1.config')
requested = read(Path('ebpf-kernel.config'))
rows = ['symbol\tmicrosoft_6.6.123.2\tmicrosoft_6.18.54.1\trequested\tdelta_6.18']
for symbol, value in requested.items():
    a, b = old.get(symbol, 'n'), new.get(symbol, 'n')
    delta = 'same' if b == value else 'changed'
    rows.append(f'{symbol}\t{a}\t{b}\t{value}\t{delta}')
assert '\n'.join(rows) + '\n' == (root / 'CONFIG_COMPARISON.tsv').read_text()
changes = [new.get(k, 'n') for k, v in requested.items() if new.get(k, 'n') != v]
assert len(requested) == 95 and len(changes) == 39
assert changes.count('n') == 5 and changes.count('m') == 33
print('Preserved comparison reproduced: 95 settings; 39 explicit deltas.')
PY
```

This comparison treats absent settings as `n` for this y/string fragment. It
does not resolve dependencies, model runtime feature availability, or establish
all differences between the two upstream kernels.

## 5. Assumptions, limitations, and open obligations

| ID | Assumption or obligation | Effect on the argument |
|---|---|---|
| A1 | Trust the reviewed primary sources and GitHub/TLS retrieval for the identified versions | Sources can be wrong; documentation at moving official URLs can change. Recheck version-sensitive statements |
| A2 | Trust the recorded local observations and reviewer reports | Evidence is unsigned; the independent assistant review is not an external certification or a human approval |
| A3 | Keep the snapshot boundary explicit | A successful historical build does not validate a later executable change or authenticate a future release |
| O1 | Verify exact signed release subjects, immutable assets, and installer flow after publication | Current evidence establishes a policy and local hashes, not live release authenticity |
| O2 | Record Windows/WSL version; boot candidate; load a genuinely modular feature; confirm BTF/LSM/mounts; test rollback | Minimum compatible WSL version and target-host behavior remain unproven |
| O3 | Test OBI attachment/output and two-service propagation with the intended runtime/protocol/TLS configuration | Source prerequisites do not prove application compatibility |
| O4 | Test actual Tetragon policies and selected Cilium/Envoy modes if claiming their support | Kernel feature inclusion alone is insufficient |
| O5 | Measure performance if making quantitative or comparative claims | No benchmark result is supplied by this assurance case |

## 6. Maintenance rule

Treat each claim as version-bound. When the kernel, fragment, packaging,
installer, workflow or application version changes, identify the claims it
invalidates, recheck their primary evidence, rerun relevant validation, and
record the new snapshot and results. Keep old evidence dated rather than
rewriting it to imply a test on new inputs. Do not turn a conditional statement
into a universal requirement or a successful probe into a workload certificate.

The assurance case can be closed for source/configuration/local packaging at
this boundary. Release authenticity and Windows/application acceptance remain
open until their own evidence is recorded.
