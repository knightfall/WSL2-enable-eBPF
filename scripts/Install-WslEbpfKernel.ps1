#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^ebpf-v[0-9][A-Za-z0-9._-]*$')][string]$ReleaseTag
)
$ErrorActionPreference = 'Stop'
# The trust identity is fixed; changing download location must not change policy.
$Repository = 'knightfall/WSL2-enable-eBPF'
function Invoke-CheckedGh {
    param([string[]]$Arguments)
    & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub verification failed: $($Arguments -join ' ')" }
}
function Assert-ReleaseAsset {
    param([string]$Path, [string]$Bundle)
    Invoke-CheckedGh -Arguments @('release', 'verify-asset', $ReleaseTag, $Path, '--repo', $Repository)
    Invoke-CheckedGh -Arguments @('attestation', 'verify', $Path, '--repo', $Repository,
        '--bundle', $Bundle, '--signer-workflow', "$Repository/.github/workflows/release.yml",
        '--source-ref', "refs/tags/$ReleaseTag", '--deny-self-hosted-runners')
}
if ($env:OS -ne 'Windows_NT') { throw 'Run this installer on Windows.' }
# Win32_Processor describes the platform, including when PowerShell is emulated.
$architectures = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
    Select-Object -ExpandProperty Architecture -Unique)
if ($architectures.Count -ne 1 -or $architectures[0] -ne 9) {
    throw 'Only native x86-64 Windows hosts are supported.'
}
Get-Command wsl.exe -ErrorAction Stop | Out-Null
Get-Command gh -ErrorAction Stop | Out-Null
$configPath = Join-Path $env:USERPROFILE '.wslconfig'
$installDir = Join-Path $env:USERPROFILE "wsl-kernel\$ReleaseTag"
if (Test-Path $installDir) { throw "Installation directory already exists: $installDir" }
if (-not $PSCmdlet.ShouldProcess($configPath, "Install $ReleaseTag for all WSL2 distributions")) { return }
$stage = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $stage | Out-Null
$createdInstallDir = $false
$configCommitted = $false
try {
    Invoke-CheckedGh -Arguments @('release', 'verify', $ReleaseTag, '--repo', $Repository)
    Invoke-CheckedGh -Arguments @('release', 'download', $ReleaseTag, '--repo', $Repository, '--pattern', 'SHA256SUMS', '--dir', $stage)
    $bundle = Join-Path $stage 'provenance.sigstore.json'
    Invoke-CheckedGh -Arguments @('release', 'download', $ReleaseTag, '--repo', $Repository, '--pattern', 'provenance.sigstore.json', '--dir', $stage)
    Invoke-CheckedGh -Arguments @('release', 'verify-asset', $ReleaseTag, $bundle, '--repo', $Repository)
    Assert-ReleaseAsset -Path (Join-Path $stage 'SHA256SUMS') -Bundle $bundle
    foreach ($name in @('bzImage', 'modules.vhdx', 'kernel-release.txt', 'verify-runtime.sh', 'check-config.py', 'ebpf-kernel.config')) {
        $matches = @(Get-Content (Join-Path $stage 'SHA256SUMS') | Where-Object { $_ -match "^[a-fA-F0-9]{64}  $([regex]::Escape($name))$" })
        if ($matches.Count -ne 1) { throw "Missing or ambiguous checksum for $name" }
        $expected = $matches[0].Substring(0, 64)
        $file = Join-Path $stage $name
        Invoke-CheckedGh -Arguments @('release', 'download', $ReleaseTag, '--repo', $Repository, '--pattern', $name, '--dir', $stage)
        Assert-ReleaseAsset -Path $file -Bundle $bundle
        if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $expected) { throw "Checksum mismatch: $name" }
    }
    $lines = @()
    if (Test-Path $configPath) { $lines = @(Get-Content $configPath) }
    $sections = @($lines | Select-String '^\s*\[wsl2\]\s*(?:[#;].*)?$')
    if ($sections.Count -gt 1) { throw 'Duplicate [wsl2] sections; consolidate them before installing.' }
    $result = [Collections.Generic.List[string]]::new()
    $inWsl = $false
    $inserted = $false
    $keys = @("kernel=$($installDir.Replace('\', '\\'))\\bzImage", "kernelModules=$($installDir.Replace('\', '\\'))\\modules.vhdx")
    foreach ($line in $lines) {
        if ($line -match '^\s*\[') {
            if ($inWsl -and -not $inserted) {
                $result.AddRange([string[]]$keys); $inserted = $true
            }
            $inWsl = $line -match '^\s*\[wsl2\]\s*(?:[#;].*)?$'
        }
        if ($inWsl -and $line -match '^\s*(kernel|kernelModules)\s*=') { continue }
        if ($inWsl -and $line -match '^\s*kernelCommandLine\s*=.*\blsm=') {
            throw 'Existing lsm= override: preserve its LSMs and append bpf before installing.'
        }
        $result.Add($line)
    }
    if (-not $inserted) {
        if (-not $inWsl) { $result.Add(''); $result.Add('[wsl2]') }
        $result.AddRange([string[]]$keys)
    }
    $backup = $null
    if (Test-Path $configPath) {
        $backup = "$configPath.backup-$([guid]::NewGuid().ToString())"
        Copy-Item $configPath $backup
    }
    New-Item -ItemType Directory -Path $installDir | Out-Null
    $createdInstallDir = $true
    New-Item -ItemType Directory -Path (Join-Path $installDir 'scripts') | Out-Null
    foreach ($name in @('verify-runtime.sh', 'check-config.py')) {
        Copy-Item (Join-Path $stage $name) (Join-Path (Join-Path $installDir 'scripts') $name)
    }
    foreach ($name in @('bzImage', 'modules.vhdx', 'kernel-release.txt', 'ebpf-kernel.config', 'SHA256SUMS', 'provenance.sigstore.json')) {
        Copy-Item (Join-Path $stage $name) (Join-Path $installDir $name)
    }
    $tempConfig = "$configPath.$([guid]::NewGuid().ToString()).tmp"
    try {
        [IO.File]::WriteAllLines($tempConfig, $result, [Text.UTF8Encoding]::new($false))
        Move-Item $tempConfig $configPath -Force
        $configCommitted = $true
    } finally {
        if (Test-Path $tempConfig) { Remove-Item $tempConfig -Force }
    }
    Write-Output "Installed $ReleaseTag in $installDir"
    if ($backup) { Write-Output "Rollback: restore $backup to $configPath" }
    else { Write-Output 'Rollback: remove kernel and kernelModules from [wsl2].' }
    Write-Output 'When ready, run wsl --shutdown, start WSL, and run the documented runtime checks.'
} catch {
    # Remove only this invocation's directory, and only before config points to it.
    if ($createdInstallDir -and -not $configCommitted) {
        Remove-Item $installDir -Recurse -Force -ErrorAction Continue
    }
    throw
} finally {
    Remove-Item $stage -Recurse -Force
}
