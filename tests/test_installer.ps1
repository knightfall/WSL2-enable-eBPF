$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '../scripts/Install-WslEbpfKernel.ps1') -Raw
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$start = $source.IndexOf('    $sections =')
$end = $source.IndexOf('    $backup =', $start)
$merge = [scriptblock]::Create($source.Substring($start, $end - $start))
$installDir = 'C:\Users\Example User\wsl-kernel\ebpf-v1.0.0'
foreach ($inputLines in @(
    @(),
    @('[wsl2]', 'memory=4GB'),
    @('[wsl2]', 'kernel=old', 'kernelModules=old', 'memory=4GB', '[experimental]', 'autoMemoryReclaim=gradual'),
    @('[experimental]', 'autoMemoryReclaim=gradual')
)) {
    $lines = $inputLines
    . $merge
    if (@($result | Where-Object { $_ -match '^kernel=' }).Count -ne 1) { throw 'Expected one kernel key' }
    if (@($result | Where-Object { $_ -match '^kernelModules=' }).Count -ne 1) { throw 'Expected one module key' }
    foreach ($line in $inputLines) {
        if ($line -notmatch '^kernel(?:Modules)?=' -and $result -notcontains $line) { throw "Lost setting: $line" }
    }
    if ($result -notcontains 'kernel=C:\\Users\\Example User\\wsl-kernel\\ebpf-v1.0.0\\bzImage') { throw 'Incorrect path escaping' }
}
foreach ($inputLines in @(
    @('[wsl2]', '[wsl2]'),
    @('[wsl2]', 'kernelCommandLine=quiet lsm=landlock,lockdown')
)) {
    $lines = $inputLines
    $rejected = $false
    try { . $merge } catch { $rejected = $true }
    if (-not $rejected) { throw 'Expected unsafe config rejection' }
}
Write-Output 'Installer configuration merge tests passed.'

# Exercise the native exit-code guard and exact identity policy without network.
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
foreach ($name in @('Invoke-CheckedGh', 'Assert-ReleaseAsset')) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$Repository = 'knightfall/WSL2-enable-eBPF'
$ReleaseTag = 'ebpf-v1.0.0'
$script:calls = @()
$script:failAt = 0
function gh {
    $script:calls += ,@($args)
    $global:LASTEXITCODE = [int]($script:failAt -eq $script:calls.Count)
}
Assert-ReleaseAsset -Path 'bzImage' -Bundle 'provenance.sigstore.json'
$policy = $script:calls[1] -join ' '
foreach ($expected in @('--repo knightfall/WSL2-enable-eBPF', '--signer-workflow knightfall/WSL2-enable-eBPF/.github/workflows/release.yml', '--source-ref refs/tags/ebpf-v1.0.0', '--deny-self-hosted-runners', '--bundle provenance.sigstore.json')) {
    if (-not $policy.Contains($expected)) { throw "Missing trust constraint: $expected" }
}
foreach ($failure in @(1, 2)) {
    $script:calls = @(); $script:failAt = $failure; $rejected = $false
    try { Assert-ReleaseAsset -Path 'bzImage' -Bundle 'bundle' } catch { $rejected = $true }
    if (-not $rejected -or $script:calls.Count -ne $failure) { throw 'Verification did not fail closed' }
}
Remove-Item function:gh
Write-Output 'Installer authenticity policy and failure tests passed.'
