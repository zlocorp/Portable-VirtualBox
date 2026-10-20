# Experimental signed Oracle VBoxSup primitive INF staging/installation.
# CRITICAL: only on a fresh, disposable GitHub-hosted Windows runner.
# No service stop, driver removal, VM start or unscoped process termination.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(15,120)][int]$TimeoutSeconds = 75
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Driver research requires a disposable GitHub-hosted runner'
}
if (-not $env:RUNNER_TEMP) { throw 'RUNNER_TEMP must be provided' }
$runner = (Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\') + '\'
$app = (Resolve-Path -LiteralPath $AppDir).Path.TrimEnd('\')
$target = [IO.Path]::GetFullPath($OutputDirectory)
if (-not ($app + '\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
    -not $target.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Both application tree and report must remain under temporary runner root'
}
if (Test-Path -LiteralPath $target) { throw 'Evidence output already exists' }

$driverRoot = Join-Path $app 'drivers\vboxsup'
$sys = Join-Path $driverRoot 'VBoxSup.sys'
$inf = Join-Path $driverRoot 'VBoxSup.inf'
$cat = Join-Path $driverRoot 'VBoxSup.cat'
$pinned = [ordered]@{
    'VBoxSup.sys'='a4d29ed6ba1c9ad74110cb86d10c0d8c9f492a1b3f6836963139380b02b3ed90'
    'VBoxSup.inf'='afc573f92fd4ff8393aea521c664fde36e62a0d9aa4a42d392e485f37d4b2a13'
    'VBoxSup.cat'='af50de8913a6dccb6471f8c775a4b56bf5caf6932b90da17f819e8cb210c2a35'
}
foreach ($name in $pinned.Keys) {
    $file = Join-Path $driverRoot $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required driver package file missing: $name" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinned[$name]) {
        throw "Unexpected VBoxSup package SHA-256: $name"
    }
}
foreach ($file in @($sys,$cat)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Untrusted signed VBoxSup payload: $(Split-Path $file -Leaf)"
    }
}
function Get-VBoxServiceKeys {
    return @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
}
function Get-VBoxProcesses {
    return @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(?:VBox|VirtualBox)' } |
        ForEach-Object { "$($_.Id):$($_.ProcessName)" } | Sort-Object -Unique)
}
$beforeServices = @(Get-VBoxServiceKeys)
$beforeProcesses = @(Get-VBoxProcesses)
if ($beforeServices.Count -ne 0 -or $beforeProcesses.Count -ne 0 -or
    (Test-Path 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
    (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    throw 'Existing VirtualBox state: refusing to stage or install VBoxSup'
}

$out = (New-Item -ItemType Directory -Path $target -ErrorAction Stop).FullName
$stdout = Join-Path $out 'pnputil.stdout.txt'
$stderr = Join-Path $out 'pnputil.stderr.txt'
$pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
$arguments = '/add-driver "' + $inf + '" /install'
$clock = [Diagnostics.Stopwatch]::StartNew()
$status = 'LAUNCH_ERROR'
$exitCode = $null
$exception = ''
$process = $null
try {
    $process = Start-Process -FilePath $pnputil -ArgumentList $arguments -WorkingDirectory $driverRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow -ErrorAction Stop
    if ($process.WaitForExit($TimeoutSeconds * 1000)) {
        $status = 'EXITED'
        $exitCode = $process.ExitCode
    } else {
        $status = 'TIMEOUT'
        try { $process.Kill(); [void]$process.WaitForExit(5000) }
        catch { $exception = 'Bounded pnputil process could not be terminated' }
    }
} catch {
    $exception = $_.Exception.Message
} finally {
    $clock.Stop()
    if ($null -ne $process) { $process.Dispose() }
}
$afterServices = @(Get-VBoxServiceKeys)
$afterProcesses = @(Get-VBoxProcesses)
$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup'
$registered = Test-Path -LiteralPath $key
$config = if ($registered) { Get-ItemProperty -LiteralPath $key -ErrorAction Stop } else { $null }
$scm = Get-Service -Name 'VBoxSup' -ErrorAction SilentlyContinue
$wmi = Get-CimInstance Win32_SystemDriver -Filter "Name='VBoxSup'" -ErrorAction SilentlyContinue
$installed = Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
$exists = Test-Path -LiteralPath $installed -PathType Leaf
$installedHash = if ($exists) {(Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash.ToLowerInvariant()} else {''}
$installedSig = if ($exists) { Get-AuthenticodeSignature -LiteralPath $installed } else {$null}
$report = [ordered]@{
    experiment='standalone-VBoxSup-primitive-INF-pnputil'
    source_commit=$env:GITHUB_SHA
    oracle_version='7.2.20'
    package_verified=$true
    services_before=$beforeServices
    services_after=$afterServices
    processes_before=$beforeProcesses
    processes_after=$afterProcesses
    pnputil_status=$status
    pnputil_exit_code=$exitCode
    pnputil_elapsed_ms=$clock.ElapsedMilliseconds
    pnputil_exception=$exception
    service_registered=[bool]$registered
    service_type=$(if ($null -ne $config) {[int]$config.Type} else {$null})
    service_start=$(if ($null -ne $config) {[int]$config.Start} else {$null})
    service_image=$(if ($null -ne $config) {[string]$config.ImagePath} else {''})
    service_state=$(if ($null -ne $scm) {[string]$scm.Status} else {'ABSENT'})
    wmi_state=$(if ($null -ne $wmi) {[string]$wmi.State} else {'ABSENT'})
    system_driver_present=[bool]$exists
    system_driver_sha256=$installedHash
    system_driver_matches_package=[bool]($exists -and $installedHash -eq $pinned['VBoxSup.sys'])
    system_driver_signature=$(if ($null -ne $installedSig) {[string]$installedSig.Status} else {''})
    installed_or_uninstalled_other_vbox_components=$false
    vm_started=$false
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'sup-standalone.json') -Encoding utf8
Write-Host "Standalone VBoxSup: pnputil=$status/$exitCode, service=$($report.service_state), wmi=$($report.wmi_state), installed=$exists, SHA-equal=$($report.system_driver_matches_package)"
if ($env:GITHUB_STEP_SUMMARY) {
    '### Standalone signed VBoxSup primitive driver experiment' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- pnputil: $status / code $exitCode" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- service: $($report.service_state); driver file: $exists; SHA match: $($report.system_driver_matches_package)" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    '- This is an isolated disposable-runner experiment, not a safe production driver installer.' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
# Driver PnP success with no kernel service is useful evidence. Do not
# auto-install via undocumented fallback or perform unowned cleanup.
