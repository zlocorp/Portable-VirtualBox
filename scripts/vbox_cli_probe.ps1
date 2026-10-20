# Read-only, bounded experiment against a prepared VirtualBox app64.
# No installation, VM creation/start, registration, or service/process-name cleanup.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,120)][int]$TimeoutSeconds = 30,
    [switch]$OfficialInstallReference
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path -LiteralPath $AppDir -ErrorAction Stop).Path
$binary = Join-Path $app 'VBoxManage.exe'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'Prepared VBoxManage.exe is missing' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Refusing to overwrite existing probe output' }
$folder = (New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$profile = (New-Item -ItemType Directory -Path (Join-Path $folder 'Профиль VBox Test') -ErrorAction Stop).FullName

function Get-VBoxServiceNames {
    return @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
}
function Get-VBoxServiceDetails {
    param([string[]]$Names)
    return @(foreach ($name in $Names) {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $name
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        [pscustomobject]@{
            name=$name
            image_path=[string]$p.ImagePath
            start=[string]$p.Start
            type=[string]$p.Type
            object_name=[string]$p.ObjectName
        }
    })
}
function Get-VBoxProcessNames {
    return @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(?:VBox|VirtualBox)' } |
        ForEach-Object { "$($_.Id):$($_.ProcessName)" } | Sort-Object -Unique)
}

$servicesBefore = @(Get-VBoxServiceNames)
$processesBefore = @(Get-VBoxProcessNames)
$serviceDetailsBefore = @(Get-VBoxServiceDetails -Names $servicesBefore)
if (($servicesBefore.Count -gt 0 -or $processesBefore.Count -gt 0) -and -not $OfficialInstallReference) {
    throw 'Existing VBox services/processes make this disposable-runner test ambiguous'
}
$commands = @(
    @{ name='version'; args=@('--version') },
    @{ name='list_vms'; args=@('list','vms') },
    @{ name='system_properties'; args=@('list','systemproperties') }
)
$oldHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$results = @()
try {
    $env:VBOX_USER_HOME = $profile
    foreach ($item in $commands) {
        $stdout = Join-Path $folder ($item.name + '.stdout.txt')
        $stderr = Join-Path $folder ($item.name + '.stderr.txt')
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $status = 'LAUNCH_ERROR'
        $exitCode = $null
        $launchError = ''
        $process = $null
        try {
            # Fixed literal argv: never pass arbitrary user-supplied command lines.
            $argsText = $item.args -join ' '
            $process = Start-Process -FilePath $binary -WorkingDirectory $app -ArgumentList $argsText -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow -ErrorAction Stop
            if ($process.WaitForExit($TimeoutSeconds * 1000)) {
                $status = 'EXITED'
                $exitCode = $process.ExitCode
            } else {
                $status = 'TIMEOUT'
                # Only terminate the specific child process we started. Never kill by name.
                try { $process.Kill(); [void]$process.WaitForExit(5000) }
                catch { $launchError = 'Timed-out probe process could not be terminated' }
            }
        } catch {
            $launchError = $_.Exception.Message
        } finally {
            $clock.Stop()
            if ($null -ne $process) { $process.Dispose() }
        }
        $results += [ordered]@{
            name=$item.name; arguments=@($item.args); status=$status
            exit_code=$exitCode; elapsed_ms=$clock.ElapsedMilliseconds
            launch_error=$launchError
            stdout_file=(Split-Path -Leaf $stdout)
            stderr_file=(Split-Path -Leaf $stderr)
        }
        Write-Host "VBoxManage $($item.name): $status (exit=$exitCode, ms=$($clock.ElapsedMilliseconds))"
    }
} finally {
    if ($null -eq $oldHome) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME = $oldHome }
}
$servicesAfter = @(Get-VBoxServiceNames)
$processesAfter = @(Get-VBoxProcessNames)
$serviceDetailsAfter = @(Get-VBoxServiceDetails -Names $servicesAfter)
$changedServices = @((Compare-Object -ReferenceObject $servicesBefore -DifferenceObject $servicesAfter))
$report = [ordered]@{
    experiment=$(if ($OfficialInstallReference) { 'official-installed-reference-cli' } else { 'prepared-app64-vboxmanage-cli-only' })
    source_commit=$env:GITHUB_SHA
    os=[Environment]::OSVersion.VersionString
    profile_location='isolated-new-profile-in-output-directory'
    timeout_seconds=$TimeoutSeconds
    services_before=$servicesBefore
    services_after=$servicesAfter
    service_details_before=$serviceDetailsBefore
    service_details_after=$serviceDetailsAfter
    service_registrations_changed=($changedServices.Count -gt 0)
    processes_before=$processesBefore
    processes_after=$processesAfter
    probes=$results
    vms_started=$false; installer_executed=$false; driver_install_requested=$false
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'probe-results.json') -Encoding utf8
$summary = 'VBoxManage CLI: ' + (($results | ForEach-Object {
    $_.name + '=' + $_.status + '/' + $_.exit_code
}) -join ', ')
Write-Host $summary
if ($env:GITHUB_STEP_SUMMARY) {
    '### Prepared portable app64 (experimental)' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- $summary" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- VBox service registrations changed: $($report.service_registrations_changed)" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    '- A completed experiment is not evidence that a VM can start.' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
if ($report.service_registrations_changed -and -not $OfficialInstallReference) {
    throw 'Read-only CLI probe changed VBox service registrations; investigate before proceeding'
}
# VBoxManage nonzero exits are evidence and intentionally do not fail the harness.
