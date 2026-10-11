$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '../scripts/Install-WslEbpfKernel.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wsl-installer-test-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $testRoot | Out-Null
$savedEnvironment = @{}
foreach ($key in @('OS', 'USERPROFILE', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$global:wslInstallerTestState = [pscustomobject]@{ architecture = 9; failure = ''; downloads = 0; stageDir = $null }
function Get-CimInstance {
    param($ClassName, $ErrorAction)
    if ($ClassName -ne 'Win32_Processor') { throw 'Unexpected CIM query' }
    if ($global:wslInstallerTestState.architecture -eq -1) { throw 'Injected CIM failure' }
    if ($null -ne $global:wslInstallerTestState.architecture) { [pscustomobject]@{ Architecture = $global:wslInstallerTestState.architecture } }
}
function wsl.exe { throw 'The installer must not restart WSL' }
function gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'release' -and $args[1] -eq 'download') {
        $global:wslInstallerTestState.downloads++
        $name = $args[([array]::IndexOf($args, '--pattern') + 1)]
        $directory = $args[([array]::IndexOf($args, '--dir') + 1)]
        $global:wslInstallerTestState.stageDir = $directory
        $content = $name
        if ($name -eq 'SHA256SUMS') {
            $content = ''
            foreach ($asset in @('bzImage', 'modules.vhdx', 'kernel-release.txt', 'verify-runtime.sh')) {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($asset)) }
                finally { $sha.Dispose() }
                $digest = ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
                $content += "$digest  $asset`n"
            }
        }
        [IO.File]::WriteAllBytes((Join-Path $directory $name), [Text.Encoding]::UTF8.GetBytes($content))
    }
}
function Copy-Item {
    param([string]$Path, [string]$Destination)
    if ($global:wslInstallerTestState.failure -eq 'copy' -and (Split-Path $Path -Leaf) -eq 'modules.vhdx') {
        throw 'Injected asset copy failure'
    }
    Microsoft.PowerShell.Management\Copy-Item $Path $Destination
}
function Move-Item {
    param([string]$Path, [string]$Destination, [switch]$Force)
    if ($global:wslInstallerTestState.failure -eq 'config') { throw 'Injected config commit failure' }
    Microsoft.PowerShell.Management\Move-Item $Path $Destination -Force:$Force
}
function Test-NativeArchitecture {
    $env:USERPROFILE = Join-Path $testRoot 'architecture'
    New-Item -ItemType Directory $env:USERPROFILE | Out-Null
    # Emulate the misleading process-level variables on an ARM64 machine.
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
    foreach ($native in @(12, 0, 65535, $null, -1)) {
        $global:wslInstallerTestState.architecture = $native
        $errorMessage = ''
        try { & $installer -ReleaseTag ebpf-v1.0.0 | Out-Null }
        catch { $errorMessage = $_.Exception.Message }
        if ($errorMessage -notmatch 'native x86-64|Injected CIM failure') { throw "Architecture $native was not rejected: $errorMessage" }
        if ($global:wslInstallerTestState.downloads -ne 0) { throw 'Unsupported host downloaded assets' }
        if (Test-Path (Join-Path $env:USERPROFILE '.wslconfig')) { throw 'Unsupported host changed configuration' }
    }
    Write-Output 'Test-NativeArchitecture passed (ARM64 emulation, x86, unknown, missing, CIM failure).'
}
function Test-FailedInstallationRetry {
    param([string]$Failure)
    $global:wslInstallerTestState.architecture = 9
    $global:wslInstallerTestState.failure = $Failure
    $env:USERPROFILE = Join-Path $testRoot $Failure
    New-Item -ItemType Directory $env:USERPROFILE | Out-Null
    $config = Join-Path $env:USERPROFILE '.wslconfig'
    $original = "[wsl2]`r`nmemory=4GB`r`nkernel=old`r`n"
    [IO.File]::WriteAllText($config, $original)
    $directory = Join-Path $env:USERPROFILE 'wsl-kernel/ebpf-v1.0.0'
    $errorMessage = ''
    try { & $installer -ReleaseTag ebpf-v1.0.0 | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    if ($errorMessage -notmatch 'Injected .* failure') { throw "Expected injected $Failure failure, got: $errorMessage" }
    if (Test-Path $directory) { throw "Partial installation survived $Failure failure" }
    if (Test-Path $global:wslInstallerTestState.stageDir) { throw 'Download staging survived failure' }
    if ([IO.File]::ReadAllText($config) -ne $original) { throw 'Failed installation changed original configuration' }
    if (@(Get-ChildItem $env:USERPROFILE -Filter '*.tmp' -Force).Count) { throw 'Temporary config survived failure' }
    $global:wslInstallerTestState.failure = ''
    & $installer -ReleaseTag ebpf-v1.0.0 | Out-Null
    if (@(Get-ChildItem $directory -File).Count -ne 6) { throw 'Retry did not install all verified assets' }
    if (Test-Path $global:wslInstallerTestState.stageDir) { throw 'Download staging survived success' }
    $installedConfig = [IO.File]::ReadAllText($config)
    if ($installedConfig -notmatch 'memory=4GB' -or $installedConfig -notmatch 'kernelModules=') { throw 'Successful retry lost settings or kernel paths' }
    Write-Output "Test-FailedInstallationRetry ($Failure) passed."
}
function Test-ExistingInstallationPreserved {
    $env:USERPROFILE = Join-Path $testRoot 'existing'
    $directory = Join-Path $env:USERPROFILE 'wsl-kernel/ebpf-v1.0.0'
    New-Item -ItemType Directory $directory | Out-Null
    $sentinel = Join-Path $directory 'keep.txt'
    [IO.File]::WriteAllText($sentinel, 'existing installation')
    $errorMessage = ''
    try { & $installer -ReleaseTag ebpf-v1.0.0 | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    if ($errorMessage -notmatch 'already exists') { throw 'Expected existing installation refusal' }
    if ([IO.File]::ReadAllText($sentinel) -ne 'existing installation') { throw 'Existing installation modified' }
    Write-Output 'Test-ExistingInstallationPreserved passed.'
}
try {
    $env:OS = 'Windows_NT'
    Test-NativeArchitecture
    Test-FailedInstallationRetry -Failure copy
    Test-FailedInstallationRetry -Failure config
    Test-ExistingInstallationPreserved
} finally {
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
    Microsoft.PowerShell.Management\Remove-Item $testRoot -Recurse -Force
    Remove-Variable wslInstallerTestState -Scope Global
}
