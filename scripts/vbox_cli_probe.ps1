# Read-only, bounded experiment against a prepared VirtualBox app64.
# No installation, VM creation/start, registration, or service/process-name cleanup.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,120)][int]$TimeoutSeconds = 30,
    [switch]$OfficialInstallReference,
    [switch]$ExpectPortableSds
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# VBoxManage can auto-register a persistent LocalSystem VBoxSDS service on first run.
# Prevent accidental invocation against a developer's normal Windows installation.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Disposable GitHub Actions runner required: VBoxManage may auto-register VBoxSDS'
}
if ($ExpectPortableSds) {
    if ($OfficialInstallReference -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
        throw 'Expected portable VBoxSDS side-effect mode is disposable hosted-Windows-only'
    }
}
$app = (Resolve-Path -LiteralPath $AppDir -ErrorAction Stop).Path
if ($ExpectPortableSds) {
    $runner = (Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\') + '\'
    if (-not ($app + '\').StartsWith($runner, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Expected portable VBoxSDS experiment must remain beneath RUNNER_TEMP'
    }
}

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
            object_name=$(if ($p.PSObject.Properties['ObjectName']) { [string]$p.ObjectName } else { '' })
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

# Oracle auto-registration is a known system side effect of bare VBoxManage.
# Accept it ONLY when the explicit one-shot hosted test asks for that exact
# service, with a clean baseline and a verified Oracle-signed expected image.
# This does not grant ownership or permission to clean the service on a user PC.
$verifiedPortableSds = $false
if ($ExpectPortableSds) {
    $sdsExe = Join-Path $app 'VBoxSDS.exe'
    $signature = Get-AuthenticodeSignature -LiteralPath $sdsExe
    $probeSuccess = ($results.Count -eq 3 -and
        @($results | Where-Object { $_.status -ne 'EXITED' -or $_.exit_code -ne 0 }).Count -eq 0)
    $foreignProcess = @($processesAfter | Where-Object {
        $_ -notmatch '^[0-9]+:(VBoxSVC|VBoxSDS)
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
    expected_portable_sds_verified=[bool]$verifiedPortableSds
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
if ($ExpectPortableSds -and -not $verifiedPortableSds) {
    throw 'Unexpected VBox service/process state: not the exact Oracle signed portable VBoxSDS auto-registration'
}
if ($report.service_registrations_changed -and -not $OfficialInstallReference -and -not $ExpectPortableSds) {
    throw 'Read-only CLI probe changed VBox service registrations; investigate before proceeding'
}
# VBoxManage nonzero exits are evidence and intentionally do not fail the harness.

    }).Count -gt 0
    $systemVBox = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')
    $detail = if ($serviceDetailsAfter.Count -eq 1) { $serviceDetailsAfter[0] } else { $null }
    $verifiedPortableSds = (
        $servicesBefore.Count -eq 0 -and $processesBefore.Count -eq 0 -and
        $servicesAfter.Count -eq 1 -and $servicesAfter[0] -eq 'VBoxSDS' -and
        $changedServices.Count -eq 1 -and $probeSuccess -and
        $null -ne $detail -and
        ([string]$detail.image_path).Trim().Trim('"') -ieq $sdsExe -and
        [int]$detail.type -eq 16 -and [int]$detail.start -eq 3 -and
        [string]$detail.object_name -eq 'LocalSystem' -and
        $signature.Status -eq 'Valid' -and
        $null -ne $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match 'Oracle' -and
        -not $foreignProcess -and -not $systemVBox
    )
}

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
