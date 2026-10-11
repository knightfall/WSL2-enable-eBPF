# Kernel release acceptance

Use this guide for the pinned custom kernel. Source comparison, configuration
resolution, full compilation, WSL boot, and workload tests are distinct results.
Record failures as well as successes. Do not publish a draft as validated until
its exact binary assets have passed the relevant Windows tests.

This procedure supplies the open runtime and release evidence identified by
the [assurance case](ASSURANCE_CASE.md). Record the tested asset digests and
input/version identities alongside each result; do not mark an obligation
complete merely because its commands are documented here.

## Linux build and artifact checks

Build in a fresh x86-64 Linux checkout using the prerequisites and source pin in
[the README](../README.md). Commit reviewed inputs before running
`scripts/build-release.sh`: the script includes committed source archives and
rejects tracked local changes. During an uncommitted review, use the README's
manual build commands in an isolated checkout to validate those inputs; that
build does not establish the identity of future release assets.

After packaging, check the generated files:

```bash
(cd dist && sha256sum --check SHA256SUMS)
python3 scripts/check-config.py dist/kernel.config
cat dist/kernel-release.txt dist/build-info.txt
qemu-img info dist/modules.vhdx
```

On the disposable Linux build host, inspect a read-only raw copy of the VHDX:

```bash
acceptance_image=$(mktemp /tmp/wsl-kernel-acceptance.XXXXXX.img)
trap 'rm -f -- "$acceptance_image"' EXIT
qemu-img convert -O raw dist/modules.vhdx "$acceptance_image"
sudo debugfs -R "ls /$(cat dist/kernel-release.txt)" "$acceptance_image"
sudo debugfs -R "ls /$(cat dist/kernel-release.txt)/modules" "$acceptance_image"
sudo debugfs -R "ls /$(cat dist/kernel-release.txt)/linux-headers/include" "$acceptance_image"
sudo debugfs -R "ls /$(cat dist/kernel-release.txt)/perf/bin" "$acceptance_image"
rm -f -- "$acceptance_image"
trap - EXIT
```

The expected image
layout is `<kernelrelease>/{modules,linux-headers,perf}`, including module metadata,
UAPI headers, and `bin/perf`. This validates packaging, not WSL's consumption of
it. UAPI headers do not provide a full tree for compiling external modules.

The portable provenance bundle is created by the GitHub release workflow, not
by a local build. For draft acceptance, authenticate and download the draft's
exact assets, then verify their provenance with the README's repository,
workflow, and tag policy. Immutable release and asset verification applies after
publication. Never substitute locally rebuilt binaries for the draft assets
being accepted.

## Stage exact draft assets on Windows

The installer intentionally rejects drafts. Use this PowerShell sequence to
verify and stage the draft's downloaded assets before manual configuration.
It does not run the installer, change `.wslconfig`, or stop WSL. Replace the
example tag with the actual draft tag. Use a current authenticated GitHub CLI
supporting the attestation policy flags in the README.

```powershell
$ErrorActionPreference = 'Stop'
$tag = 'ebpf-v6.18.54.1-r1' # Substitute the actual draft tag.
$repo = 'knightfall/WSL2-enable-eBPF'
$downloadDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $downloadDir | Out-Null

gh release download $tag --repo $repo --dir $downloadDir
if ($LASTEXITCODE -ne 0) { throw 'Draft download failed' }
$bundle = Join-Path $downloadDir 'provenance.sigstore.json'
$assets = @(
    'SHA256SUMS', 'bzImage', 'modules.vhdx', 'kernel.config',
    'ebpf-kernel.config', 'kernel-version.env', 'verify-runtime.sh',
    'check-config.py', 'kernel-release.txt', 'build-info.txt',
    'kernel-source.tar.xz', 'build-source.tar.xz', 'KERNEL-COPYING',
    'Install-WslEbpfKernel.ps1'
)
# The manifest and every object it lists must have valid build provenance.
foreach ($name in $assets) {
    $file = Join-Path $downloadDir $name
    gh attestation verify $file --repo $repo --bundle $bundle --signer-workflow "$repo/.github/workflows/release.yml" --source-ref "refs/tags/$tag" --deny-self-hosted-runners
    if ($LASTEXITCODE -ne 0) { throw "Draft provenance failed: $name" }
}
$manifest = Get-Content (Join-Path $downloadDir 'SHA256SUMS')
foreach ($name in $assets | Where-Object { $_ -ne 'SHA256SUMS' }) {
    $matches = @($manifest | Where-Object {
        $_ -match "^[a-fA-F0-9]{64}  $([regex]::Escape($name))$"
    })
    if ($matches.Count -ne 1) { throw "Missing or ambiguous checksum: $name" }
    $expected = $matches[0].Substring(0, 64)
    $actual = (Get-FileHash (Join-Path $downloadDir $name) -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "Draft checksum failed: $name" }
}
# Create the dependency layout used by verify-runtime.sh and check-config.py.
$candidateDir = Join-Path $env:USERPROFILE "wsl-kernel\candidate-$tag-$([guid]::NewGuid().ToString())"
New-Item -ItemType Directory -Path $candidateDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $candidateDir 'scripts') | Out-Null
foreach ($name in $assets | Where-Object { $_ -notin @('verify-runtime.sh', 'check-config.py') }) {
    Copy-Item (Join-Path $downloadDir $name) $candidateDir
}
foreach ($name in @('verify-runtime.sh', 'check-config.py')) {
    Copy-Item (Join-Path $downloadDir $name) (Join-Path $candidateDir 'scripts')
}
Copy-Item $bundle $candidateDir
$escapedDir = $candidateDir.Replace('\', '\\')
"Candidate directory: $candidateDir"
"kernel=$escapedDir\\bzImage"
"kernelModules=$escapedDir\\modules.vhdx"
```

The bundle is an untrusted evidence carrier until GitHub CLI validates its
embedded signatures. It is not itself a subject of this build attestation.
Draft assets are mutable: the verified copies in `$downloadDir` and
`$candidateDir` are the candidate being tested. Keep them intact; if the draft
changes, download, verify, and accept the new candidate again. Published release
immutability and release-asset verification are separate checks after publication.

Retain `$downloadDir` for checks against the original flat `SHA256SUMS` layout.
Staging moves the verifier and checker into `scripts/`, so that manifest cannot
be checked directly against the staged directory without accounting for those
paths. Keep the candidate directory until testing and rollback are complete.

## Windows and WSL checks

Record Windows build, `wsl --version`, distro, source commit, release tag, and
asset checksums. Preserve the previous `.wslconfig` and binaries using README section 5's
PowerShell backup step. Stage the exact draft assets as above; skip section 5's
Linux commands for copying locally built binaries. Merge the printed `kernel`
and `kernelModules` lines into the existing `[wsl2]` section using section 6.
Restart WSL when workloads can be stopped.

Inside the booted distro, replace the placeholder with the Windows candidate
path printed by the staging sequence. Convert that path with `wslpath`:

```bash
CANDIDATE_WINDOWS_PATH='C:\Users\YOUR-PROFILE\wsl-kernel\candidate-YOUR-TAG-YOUR-ID'
RELEASE_DIR=$(wslpath -u "$CANDIDATE_WINDOWS_PATH")
uname -r
cat /sys/kernel/security/lsm
sudo bash "$RELEASE_DIR/scripts/verify-runtime.sh" "$(cat "$RELEASE_DIR/kernel-release.txt")"
```

Mount the README's filesystems first. Confirm the release matches, BTF is
readable, BPF LSM is active, and the combined-profile probes pass. Test a module
that remains modular in the resolved config: inspect `modinfo` and load it using
`modprobe`, then inspect kernel logs. A feature made built-in by the fragment
does not test that WSL located the modules VHDX. Also confirm the bundled perf
and headers are exposed where the target WSL version expects them.

No minimum WSL version for this artifact layout is asserted here. Record the
actual tested version. Perform the README rollback procedure, confirm the prior
kernel boots, then return to the candidate and repeat its identity check.

After publication, run the authenticated installer verification sequence and
exercise the normal installer and rollback paths on Windows. PowerShell mock
tests do not replace this check.

## OBI and other workload checks

Run the README's HTTP smoke example with the pinned OBI image, waiting for probe
attachment before generating requests. Record the image digest, effective
capabilities, startup diagnostics, and emitted traces. The single-server demo
does not establish distributed propagation.

For propagation, use two services where A calls B, enable the intended OBI mode,
and instrument both. Send fresh requests after attachment and verify that the
spans share a trace ID with the expected parent relationship. Check tracefs,
cgroup mounts, tc modules when needed, socket BPF features, and OBI's capability
and lockdown diagnostics. Test the actual language, protocol, TLS, and connection
reuse conditions you intend to support; one HTTP test does not cover them all.

If claiming Tetragon enforcement or a Cilium networking mode, record application
versions and exercise the actual policy or connectivity/encryption behavior.
Kernel probes alone do not validate those integrations.
