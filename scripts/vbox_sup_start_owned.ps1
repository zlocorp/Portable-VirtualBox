# Start ONLY the exclusively staged, SHA-pinned VBoxSup kernel driver on
# an isolated GitHub-hosted disposable Windows instance. No other service
# operations are performed. This is research, not a production installer.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StandaloneReport,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,60)][int]$TimeoutSeconds=30
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Disposable GitHub Actions host required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\') + '\'
$source=(Resolve-Path -LiteralPath $StandaloneReport).Path
$target=[IO.Path]::GetFullPath($OutputDirectory)
if (-not $source.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
    -not $target.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Input report and output must be under RUNNER_TEMP'
}
$report=Get-Content -LiteralPath $source -Raw -ErrorAction Stop | ConvertFrom-Json
if ($report.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
    $report.pnputil_status -ne 'EXITED' -or $report.pnputil_exit_code -ne 0 -or
    -not $report.package_verified -or -not $report.service_registered -or
    -not $report.system_driver_matches_package -or
    $report.service_type -ne 1 -or $report.service_start -ne 1 -or
    @($report.services_before).Count -ne 0 -or @($report.services_after).Count -ne 1 -or
    @($report.services_after)[0] -ne 'VBoxSup') {
    throw 'No exclusive signed VBoxSup staging evidence available'
}
if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') {
    throw 'Official system VirtualBox installation present'
}
$services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
    Where-Object { $_.PSChildName -match '^VBox' } | ForEach-Object { $_.PSChildName })
if ($services.Count -ne 1 -or $services[0] -ne 'VBoxSup') {
    throw 'Other registered VirtualBox services present'
}
$config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
if ([int]$config.Type -ne 1 -or [int]$config.Start -ne 1 -or
    ([string]$config.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys')) {
    throw 'Unexpected VBoxSup driver service configuration'
}
$sys=Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be') {
    throw 'VBoxSup kernel driver has changed from the verified Oracle payload'
}
$signature=Get-AuthenticodeSignature -LiteralPath $sys
if ($signature.Status -ne 'Valid') { throw 'Installed VBoxSup.sys signature is not valid' }
$service=Get-Service -Name VBoxSup -ErrorAction Stop
if ($service.Status -ne 'Stopped') {
    throw 'Refusing to start VBoxSup: driver was not initially Stopped'
}
if (Test-Path -LiteralPath $target) { throw 'Refusing existing output' }
$out=(New-Item -Path $target -ItemType Directory -ErrorAction Stop).FullName
$sc=Join-Path $env:SystemRoot 'System32\sc.exe'
$stdout=Join-Path $out 'driver-start.stdout.txt'
$stderr=Join-Path $out 'driver-start.stderr.txt'
$proc=$null;$status='LAUNCH_ERROR';$exitCode=$null;$problem=''
$clock=[Diagnostics.Stopwatch]::StartNew()
try {
    # Only "sc.exe start VBoxSup", never a driver delete/stop, and only after
    # proving there is no pre-existing VBox service and verifying the driver.
    $proc=Start-Process -FilePath $sc -ArgumentList 'start VBoxSup' -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
    if ($proc.WaitForExit($TimeoutSeconds*1000)) {
        $status='EXITED'; $exitCode=$proc.ExitCode
    } else {
        $status='TIMEOUT'
        try { $proc.Kill(); [void]$proc.WaitForExit(5000) }
        catch { $problem='Timed-out direct service-control command could not be terminated' }
    }
} catch { $problem=$_.Exception.Message }
finally { $clock.Stop(); if ($null -ne $proc) { $proc.Dispose() } }
for($i=0;$i -lt 20;$i++) {
    $service=Get-Service -Name VBoxSup -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -in @('Running','Stopped')) { break }
    Start-Sleep -Seconds 1
}
$wmi=Get-CimInstance Win32_SystemDriver -Filter "Name='VBoxSup'" -ErrorAction SilentlyContinue
$state=if ($null -ne $service) { [string]$service.Status } else { 'MISSING' }
$driverRunning=($state -eq 'Running' -and $null -ne $wmi -and $wmi.State -eq 'Running')
$result=[ordered]@{
    experiment='owned-standalone-VBoxSup-start'
    source_commit=$env:GITHUB_SHA
    initial_status='Stopped'
    start_command='sc.exe start VBoxSup'
    start_status=$status
    start_exit_code=$exitCode
    elapsed_ms=$clock.ElapsedMilliseconds
    failure=$problem
    service_status_after=$state
    wmi_driver_state=$(if ($null -ne $wmi) { [string]$wmi.State } else { 'MISSING' })
    driver_running=[bool]$driverRunning
    no_other_vbox_services_before=$true
    vm_started=$false
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'sup-start-results.json') -Encoding utf8
Write-Host "Owned VBoxSup start: command=$status/$exitCode, service=$state, WMI=$($result.wmi_driver_state), running=$driverRunning"
if ($env:GITHUB_STEP_SUMMARY) {
    '### Signed standalone VBoxSup activation' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- sc.exe start VBoxSup: $status / $exitCode" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Driver running: $driverRunning" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
# Unsupported/failed driver start is diagnostic evidence; do not retry with
# unscoped operations or change any other service automatically.
