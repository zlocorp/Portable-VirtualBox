# Exact-owned rollback from a protected, INTERRUPTED VBoxSup prepare.
# No operation is permitted without the original exclusive PnP receipt, a
# pinned Oracle payload, and a departed original controller. This is a
# disposable-host-only research primitive; NEVER general Windows cleanup.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$SessionDir,
    [Parameter(Mandatory)][string]$PartialRecoveryReport,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][long]$OriginalControllerCreated,
    [ValidateRange(10,75)][int]$TimeoutSeconds = 45
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:PVBOX_FIXED_HELPER_MODE -eq 'ALPHA') {
    if (-not (Get-Command -Name Assert-PortableFixedHelper -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'Alpha effects require the embedded fixed-helper worker function'
    }
    Assert-PortableFixedHelper
} elseif ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Exact partial recovery restricted to disposable Windows'
}
if (-not $env:RUNNER_TEMP) { throw 'Protected runtime boundary absent' }
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
$session=(Resolve-Path -LiteralPath $SessionDir).Path
$app=(Resolve-Path -LiteralPath $AppDir).Path
$proofPath=(Resolve-Path -LiteralPath $PartialRecoveryReport).Path
$outPath=[IO.Path]::GetFullPath($OutputDirectory)
if (-not ($session+'\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
    $app -ine (Join-Path $session 'app64') -or
    $proofPath -ine (Join-Path $session 'partial-recovery-quiescent.json') -or
    $outPath -ine (Join-Path $session 'cleanup')) { throw 'Recovery outside exact protected session' }
if ((Test-Path -LiteralPath $outPath) -or (Test-Path -LiteralPath (Join-Path $session 'session.json')) -or
    (Test-Path -LiteralPath (Join-Path $session 'payload-removed.json'))) { throw 'Session has already been committed or recovered' }

$stagePath=Join-Path $session 'stage\sup-standalone.json'
$startPath=Join-Path $session 'start\sup-start-results.json'
$sdsMarkerPath=Join-Path $session 'sds-registered.json'
$intent=Get-Content -LiteralPath (Join-Path $session 'prepare-intent.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
$stage=Get-Content -LiteralPath $stagePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
$proof=Get-Content -LiteralPath $proofPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
function Test-OriginalControllerAbsent([int]$OldPid) {
    if ($OldPid -le 0) { return $false }
    return $null -eq (Get-CimInstance Win32_Process -Filter "ProcessId=$OldPid" -ErrorAction Stop)
}
function Get-VBoxNames {
    return @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object PSChildName -match '^VBox' | ForEach-Object PSChildName | Sort-Object -Unique)
}
function Get-VBoxProcesses {
    return @(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)' | ForEach-Object Id)
}
function Require-Quiescent {
    if (@(Get-VBoxProcesses).Count -ne 0) { throw 'Running VBox process forbids partial recovery' }
    if (-not (Test-OriginalControllerAbsent ([int]$proof.original_controller_pid))) {
        throw 'Original controller is live or its state is unknown'
    }
    $controller=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
    try {
        if ($controller.StartTime.ToFileTimeUtc().ToString() -ne $proof.controller_created_filetime -or
            $controller.MainModule.FileName -ine $proof.controller_image) {
            throw 'Recovery controller generation changed'
        }
    } finally { $controller.Dispose() }
}
if ($proof.experiment -ne 'partial-protected-manager-quiescent' -or $proof.schema -ne 1 -or
    $proof.protected_app -ine $app -or $intent.phase -ne 'pre-system-effects' -or
    $intent.schema -ne 1 -or $intent.protected_app -ine $app -or $intent.portable_root -ine $proof.portable_root -or
    $intent.controller_pid -ne $proof.original_controller_pid -or
    $intent.controller_created_filetime -ne $proof.original_controller_created_filetime -or
    $OriginalControllerCreated.ToString() -ne $proof.original_controller_created_filetime -or
    $proof.controller_pid -le 0 -or $proof.original_controller_pid -le 0 -or
    $proof.original_controller_pid -eq $proof.controller_pid -or
    $proof.controller_image -notin @((Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe'), (Join-Path $proof.portable_root 'Portable-VirtualBox.exe')) -or
    -not $proof.no_vbox_processes_verified) { throw 'Incomplete preparation ownership proof mismatch' }
# Before *any* system mutation, require old owner absence and live/new owner.
Require-Quiescent
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    throw 'Foreign system Oracle installation detected'
}
$pinSys='4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be'
$pinInf='2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4'
$stageServices=@($stage.services_after)
if ($stage.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
    $stage.oracle_version -ne '7.2.22' -or $stage.pnputil_status -ne 'EXITED' -or
    $stage.pnputil_exit_code -ne 0 -or -not $stage.package_verified -or
    -not $stage.service_registered -or -not $stage.system_driver_matches_package -or
    $stage.system_driver_sha256 -ne $pinSys -or
    @($stage.services_before).Count -ne 0 -or $stageServices.Count -ne 1 -or
    $stageServices[0] -ne 'VBoxSup' -or $stage.service_type -ne 1 -or $stage.service_start -ne 1) {
    throw 'No exact exclusive VBoxSup staging receipt for this interrupted attempt'
}
$sys=Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
$packageInf=Join-Path $app 'drivers\vboxsup\VBoxSup.inf'
if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
    (Get-FileHash -LiteralPath $packageInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Pinned VBoxSup driver/INF differed; no cleanup'
}
$sig=Get-AuthenticodeSignature -LiteralPath $sys
if ($sig.Status -ne 'Valid') { throw 'Installed VBoxSup not properly signed' }
$pnputilLog=Join-Path $session 'stage\pnputil.stdout.txt'
if (-not (Test-Path -LiteralPath $pnputilLog -PathType Leaf)) { throw 'Missing original driver installation transcript' }
$installText=Get-Content -LiteralPath $pnputilLog -Raw -ErrorAction Stop
$publishedMatches=[regex]::Matches($installText,'(?im)^\s*Published Name:\s*(oem[0-9]{1,6}\.inf)\s*$')
if ($publishedMatches.Count -ne 1) { throw 'Ambiguous published OEM INF name' }
$published=$publishedMatches[0].Groups[1].Value.ToLowerInvariant()
$installedInf=Join-Path (Join-Path $env:SystemRoot 'INF') $published
if ((Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Published INF identity differs from this signed package'
}
$driverSvc=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
if ([int]$driverSvc.Type -ne 1 -or [int]$driverSvc.Start -ne 1 -or
    [string]$driverSvc.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys') {
    throw 'Kernel service does not match pinned owner'
}
$startExists=Test-Path -LiteralPath $startPath -PathType Leaf
if ((Test-Path -LiteralPath (Join-Path $session 'start')) -and -not $startExists) {
    throw 'Interrupted driver activation without a committed start report'
}
$phase='Stage'
if ($startExists) {
    $started=Get-Content -LiteralPath $startPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($started.experiment -ne 'owned-standalone-VBoxSup-start' -or
        $started.start_exit_code -ne 0 -or $started.start_status -ne 'EXITED' -or
        -not $started.driver_running -or $started.initial_status -ne 'Stopped' -or
        $started.service_status_after -ne 'Running') {
        throw 'Unverified driver activation receipt'
    }
    $phase='Start'
}
$names=@(Get-VBoxNames)
$sdsExists=Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
$markerExists=Test-Path -LiteralPath $sdsMarkerPath -PathType Leaf
if ($sdsExists -ne $markerExists) { throw 'SDS service and its committed protected marker disagree' }
if (-not $markerExists -and ((Test-Path -LiteralPath (Join-Path $session 'sds-register.stdout.txt')) -or
                            (Test-Path -LiteralPath (Join-Path $session 'sds-register.stderr.txt')))) {
    throw 'SDS may have registered without a durable marker'
}
if ($markerExists) {
    if (-not $startExists) { throw 'SDS registered before proven driver start' }
    $marker=Get-Content -LiteralPath $sdsMarkerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sdsExe=Join-Path $app 'VBoxSDS.exe'
    if ($marker.schema -ne 1 -or -not $marker.registered -or
        $marker.protected_app -ine $app -or
        $marker.controller_pid -ne $proof.original_controller_pid -or
        $marker.controller_created_filetime -ne $proof.original_controller_created_filetime -or
        $marker.sds_image -ine $sdsExe) { throw 'SDS marker owner differs' }
    $sds=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
    if ([string]$sds.ImagePath.Trim().Trim('"') -ine $sdsExe -or [int]$sds.Type -ne 16 -or
        [int]$sds.Start -ne 3 -or [string]$sds.ObjectName -ne 'LocalSystem' -or
        (Get-Service VBoxSDS -ErrorAction Stop).Status -ne 'Stopped') {
        throw 'SDS service is not the exact stopped protected session service'
    }
    $publisher=Get-AuthenticodeSignature -LiteralPath $sdsExe
    if ($publisher.Status -ne 'Valid' -or $publisher.SignerCertificate.Subject -notmatch 'Oracle') {
        throw 'Untrusted SDS signer'
    }
    if ($names.Count -ne 2 -or $names -notcontains 'VBoxSup' -or $names -notcontains 'VBoxSDS') {
        throw 'Unexpected VBox service in registered phase'
    }
    $phase='Sds'
} elseif ($names.Count -ne 1 -or $names[0] -ne 'VBoxSup') {
    throw 'Unexpected VBox service in interrupted stage/start phase'
}
$driverStatus=(Get-Service -Name 'VBoxSup' -ErrorAction Stop).Status
if ($driverStatus -ne $(if ($startExists) {'Running'} else {'Stopped'})) {
    throw 'Driver service does not match last durable start checkpoint'
}
Require-Quiescent
# All observations above must pass before the FIRST destructive operation.
$out=(New-Item -Path $outPath -ItemType Directory -ErrorAction Stop).FullName
$report=[ordered]@{experiment='exact-partial-preparation-recovery';source_commit=$env:GITHUB_SHA;
    cleanup_basis='PartialRecovery';validated_checkpoint=$phase;published_inf=$published;
    sds_cleanup='NOT_ATTEMPTED';service_stop='NOT_ATTEMPTED';driver_package_removal='NOT_ATTEMPTED';
    service_delete='NOT_ATTEMPTED';cleanup_verified=$false;driver_package_removed=$false;errors=@()}
function Run-Bounded([string]$Command,[string]$Arguments,[string]$Label) {
    $p=$null
    try {
        $p=Start-Process -FilePath $Command -ArgumentList $Arguments -NoNewWindow -PassThru -ErrorAction Stop `
            -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Recovery tool process handle unavailable' }
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) {
            # This is a one-shot recovery mutation; never lose the live child.
            $p.WaitForExit()
            throw "$Label exceeded deadline; child has exited, recovery state requires inspection"
        }
        return [int]$p.ExitCode
    } finally { if ($null -ne $p) { $p.Dispose() } }
}
try {
    if ($markerExists) {
        Require-Quiescent
        $result=Run-Bounded $sdsExe '--unregservice' 'sds-unregister'
        if ($result -ne 0 -or (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
            throw 'Owned SDS unregistration unconfirmed'
        }
        $report.sds_cleanup='CLEAN'
    }
    if (@(Get-VBoxNames).Count -ne 1 -or @(Get-VBoxNames)[0] -ne 'VBoxSup') {
        throw 'Driver service not exclusive after SDS checkpoint'
    }
    Require-Quiescent
    $sc=Join-Path $env:SystemRoot 'System32\sc.exe'
    if ($startExists) {
        $status=Run-Bounded $sc 'stop VBoxSup' 'sup-stop'
        $report.service_stop="EXIT_$status"
        if ($status -ne 0) { throw 'Owned driver stop failed' }
        for($i=0;$i -lt 25;$i++) {
            if ((Get-Service VBoxSup).Status -eq 'Stopped') { break }
            Start-Sleep -Seconds 1
        }
    }
    if ((Get-Service VBoxSup).Status -ne 'Stopped') { throw 'Owned driver not stopped, package retained' }
    Require-Quiescent
    if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
        (Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
        throw 'Changed driver package before removal'
    }
    # Only the exact published OEM INF created on an initially clean host.
    # No /force and never a blanket service/driver-name wildcard.
    $pnputil=Join-Path $env:SystemRoot 'System32\pnputil.exe'
    $status=Run-Bounded $pnputil "/delete-driver $published /uninstall" 'sup-package-remove'
    $report.driver_package_removal="EXIT_$status"
    if ($status -ne 0) { throw 'PnPUtil refused exact owned package deletion' }
    for($i=0;$i -lt 25;$i++) {
        if (-not (Test-Path $installedInf) -and -not (Test-Path $sys)) { break }
        Start-Sleep -Seconds 1
    }
    $report.driver_package_removed=(-not (Test-Path $installedInf) -and -not (Test-Path $sys))
    if (-not $report.driver_package_removed) { throw 'Driver bytes or INF remain; no service-delete fallback' }
    $names=@(Get-VBoxNames)
    if ($names.Count -eq 1 -and $names[0] -eq 'VBoxSup') {
        if ((Get-Service VBoxSup).Status -ne 'Stopped' -or
            [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup').Type -ne 1 -or
            @(Get-VBoxProcesses).Count -ne 0) { throw 'Residual service not exclusively ours' }
        $result=Run-Bounded $sc 'delete VBoxSup' 'sup-service-delete'
        $report.service_delete="EXIT_$result"
        if ($result -ne 0) { throw 'Stopped owned service delete failed' }
        for($i=0;$i -lt 25;$i++) {
            if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup')) { break }
            Start-Sleep -Seconds 1
        }
    }
    $report.cleanup_verified=(@(Get-VBoxNames).Count -eq 0 -and @(Get-VBoxProcesses).Count -eq 0 -and
        -not (Test-Path $installedInf) -and -not (Test-Path $sys))
    if (-not $report.cleanup_verified) { throw 'Incomplete preparation cleanup did not leave clean host' }
} catch { $report.errors+= $_.Exception.Message }
finally {
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'cleanup-results.json') -Encoding utf8
}
if ($report.errors.Count -ne 0) { throw ($report.errors -join '; ') }
Write-Host ("PARTIAL_PREPARATION_CLEAN checkpoint="+$phase+" exact_owned_driver_package_removed=true")
