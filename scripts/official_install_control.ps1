# Controlled reference installation on a disposable, isolated GitHub-hosted runner.
# Deliberately system-changing: NEVER invoke this on a regular user's PC.
# No VM starts. No unscoped process termination or service deletion.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(30,300)][int]$TimeoutSeconds = 210
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Disposable GitHub Actions test runner required; refusing host installation'
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Refusing to replace existing control output directory' }
$msi = (Resolve-Path -LiteralPath $MsiPath -ErrorAction Stop).Path
if ((Split-Path $msi -Leaf) -ne 'VirtualBox-7.2.20-r175154-MultiArch_amd64.msi') {
    throw 'Unexpected MSI package name'
}
$msiSha = 'ae40bb2b2770fcd264cb9d03de2d278a621997b33956e88a2de5edc900873d2a'
if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant() -ne $msiSha) {
    throw 'MSI is not the pinned Oracle package'
}
$cab = Join-Path (Split-Path $msi -Parent) 'common.cab'
if ((Get-FileHash -LiteralPath $cab -Algorithm SHA256).Hash.ToLowerInvariant() -ne '65a3ac87ff3be03e4db4837139eb286e4e1387e1fd5d758d72c6ff745f6e10db') {
    throw 'Common cabinet does not match signed package'
}
$target = (New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$log = Join-Path $target 'msi-verbose.log'
$tail = Join-Path $target 'msi-tail.txt'
function Get-VBoxServiceNames {
    return @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
}
$before = @(Get-VBoxServiceNames)
if ($before.Count -ne 0) { throw 'Runner already has VBox service registrations; not an isolated reference baseline' }
$installer = Join-Path $env:SystemRoot 'System32\msiexec.exe'
$argsText = '/i "' + $msi + '" ADDLOCAL=VBoxApplication /qn /norestart REBOOT=ReallySuppress VBOX_INSTALLDESKTOPSHORTCUT=0 VBOX_INSTALLQUICKLAUNCHSHORTCUT=0 /L*v "' + $log + '"'
Write-Host 'Starting bounded official MSI control: VBoxApplication only, no guest VM launch.'
$elapsed = [Diagnostics.Stopwatch]::StartNew()
$status = 'LAUNCH_ERROR'
$exitCode = $null
$failure = ''
$p = $null
try {
    $p = Start-Process -FilePath $installer -ArgumentList $argsText -WorkingDirectory (Split-Path $msi -Parent) -NoNewWindow -PassThru -ErrorAction Stop
    if ($p.WaitForExit($TimeoutSeconds * 1000)) {
        $status = 'EXITED'
        $exitCode = $p.ExitCode
    } else {
        $status = 'TIMEOUT'
        try { $p.Kill(); [void]$p.WaitForExit(5000) }
        catch { $failure = 'Timed-out direct msiexec process could not be stopped' }
    }
} catch {
    $failure = $_.Exception.Message
} finally {
    $elapsed.Stop()
    if ($null -ne $p) { $p.Dispose() }
}
$after = @(Get-VBoxServiceNames)
$installation = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue
$installDir = if ($null -ne $installation) { [string]$installation.InstallDir } else { '' }
$cli = if ($installDir) { Join-Path $installDir 'VBoxManage.exe' } else { '' }
$ready = ($status -eq 'EXITED' -and $exitCode -in @(0,3010) -and $cli -and (Test-Path -LiteralPath $cli -PathType Leaf))
$report = [ordered]@{
    experiment='official-oracle-7.2.20-VBoxApplication-only'
    installer_sha256=$msiSha; feature='VBoxApplication'
    status=$status; exit_code=$exitCode; elapsed_ms=$elapsed.ElapsedMilliseconds
    exception=$failure; reboot_requested=($exitCode -eq 3010)
    installed_binary_present=[bool]$ready
    install_directory=$installDir
    services_before=$before
    services_after=$after
    vm_started=$false
    source_commit=$env:GITHUB_SHA
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $target 'install-results.json') -Encoding utf8
if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Tail 220 -ErrorAction SilentlyContinue | Set-Content -LiteralPath $tail -Encoding utf8
}
Write-Host "Official MSI: $status, exit=$exitCode, installed-cli-ready=$ready, services=$($after -join ',')"
if ($env:GITHUB_STEP_SUMMARY) {
    '### Disposable official Oracle installation reference' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- MSI: $status / exit $exitCode; VBoxManage present: $ready" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Services after install: $($after -join ', ')" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
# Non-zero MSI exit is research evidence, NOT permission for an unsafe retry.
# Publish metadata even when installation cannot succeed on a hosted runner.
if ($ready) {
    "OFFICIAL_CLI=$cli" >> $env:GITHUB_ENV
}
