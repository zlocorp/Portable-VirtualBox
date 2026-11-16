# Proof-only VBoxSup teardown on an exclusive, disposable GitHub Windows runner.
# This NEVER runs on a user's PC and NEVER deletes a pre-existing VBox driver.
# Stop/release only after a verified empty VM powered off and VBoxSDS clients exited.
[CmdletBinding(DefaultParameterSetName="Boot")]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$StandaloneReport,
    [Parameter(Mandatory)][string]$DriverStartReport,
    [Parameter(Mandatory,ParameterSetName="Boot")][string]$BootReport,
    [Parameter(Mandatory,ParameterSetName="Session")][string]$QuiescentReport,
    [Parameter(Mandatory,ParameterSetName="PrivilegedSession")][string]$PrivilegedReport,
    [Parameter(Mandatory,ParameterSetName="RecoverySession")][string]$RecoveryReport,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(ParameterSetName="PrivilegedSession")]
    [Parameter(ParameterSetName="RecoverySession")]
    [string]$ProspectiveProofJson,
    [ValidateRange(5,90)][int]$TimeoutSeconds = 45
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:PVBOX_FIXED_HELPER_MODE -eq 'ALPHA') {
    if (-not (Get-Command -Name Assert-PortableFixedHelper -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'Alpha effects require the embedded fixed-helper worker function'
    }
    Assert-PortableFixedHelper
} elseif ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable GitHub-hosted Windows runner required'
}
if (-not $env:RUNNER_TEMP) { throw 'RUNNER_TEMP missing' }
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
function Under-Runner([string]$Value) {
    $full=[IO.Path]::GetFullPath($Value)
    return $full.StartsWith($runner, [StringComparison]::OrdinalIgnoreCase)
}
$proofPath=if ($PSCmdlet.ParameterSetName -eq "Session") { $QuiescentReport } elseif ($PSCmdlet.ParameterSetName -eq "PrivilegedSession") { $PrivilegedReport } elseif ($PSCmdlet.ParameterSetName -eq "RecoverySession") { $RecoveryReport } else { $BootReport }
foreach ($candidate in @($AppDir,$StandaloneReport,$DriverStartReport,$proofPath,$OutputDirectory)) {
    if (-not (Under-Runner $candidate)) { throw 'All input/output paths must be in RUNNER_TEMP' }
}
$app=(Resolve-Path -LiteralPath $AppDir).Path
$stage=(Get-Content -LiteralPath $StandaloneReport -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json)
$started=(Get-Content -LiteralPath $DriverStartReport -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json)
$cleanupParameterSet=$PSCmdlet.ParameterSetName
$prospective=$PSBoundParameters.ContainsKey('ProspectiveProofJson')
if ($prospective) {
    if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA') -or
        [string]::IsNullOrWhiteSpace($ProspectiveProofJson) -or
        [Text.Encoding]::UTF8.GetByteCount($ProspectiveProofJson) -gt 16384) {
        throw 'Invalid protected prospective cleanup proof'
    }
    # Snapshot once: validate exactly the JSON bytes that will be committed.
    $proofBytes=[Text.Encoding]::UTF8.GetBytes($ProspectiveProofJson)
    $proof=ConvertFrom-Json -InputObject $ProspectiveProofJson -ErrorAction Stop
    if ($proof -isnot [Management.Automation.PSCustomObject]) { throw 'Invalid prospective proof object' }
} else {
    $proof=(Get-Content -LiteralPath $proofPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json)
}
function Assert-ProspectiveCleanupAdmission {
    if (-not $prospective) { return }
    $sessionPath=Split-Path $app -Parent
    $expectedName=if ($cleanupParameterSet -eq 'RecoverySession') { 'recovery-quiescent.json' } else { 'quiescent-session.json' }
    if ([IO.Path]::GetFullPath($proofPath) -ine (Join-Path $sessionPath $expectedName) -or
        [IO.Path]::GetFullPath($OutputDirectory) -ine (Join-Path $sessionPath 'cleanup')) {
        throw 'Prospective cleanup proof path mismatch'
    }
    foreach ($name in @('quiescent-session.json','recovery-quiescent.json',
        'partial-recovery-quiescent.json','cleanup','payload-cleanup.json','payload-removed.json')) {
        if (Test-Path -LiteralPath (Join-Path $sessionPath $name) -ErrorAction Stop) {
            throw 'Refusing existing cleanup admission'
        }
    }
    $live=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
    try {
        if ($live.StartTime.ToFileTimeUtc().ToString() -ne $proof.controller_created_filetime -or
            $live.MainModule.FileName -ine $proof.controller_image) { throw 'Cleanup controller generation changed' }
    } finally { $live.Dispose() }
    if ($cleanupParameterSet -eq 'RecoverySession' -and
        -not (Test-OriginalControllerAbsent ([int]$proof.original_controller_pid))) {
        throw 'Original cleanup owner reappeared'
    }
}
$pinSys='4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be'
$pinInf='2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4'
if ($stage.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
    $stage.oracle_version -ne '7.2.22' -or $stage.pnputil_status -ne 'EXITED' -or
    $stage.pnputil_exit_code -ne 0 -or -not $stage.package_verified -or
    -not $stage.system_driver_matches_package -or
    $stage.system_driver_sha256 -ne $pinSys -or
    @($stage.services_before).Count -ne 0 -or
    @($stage.services_after).Count -ne 1 -or @($stage.services_after)[0] -ne 'VBoxSup' -or
    $stage.service_type -ne 1 -or $stage.service_start -ne 1) {
    throw 'No exclusive and exact signed VBoxSup creation evidence'
}
if ($started.experiment -ne 'owned-standalone-VBoxSup-start' -or
    -not $started.driver_running -or $started.start_exit_code -ne 0) {
    throw 'No proof that our VBoxSup was started'
}
$bootVerified=$false
if ($PSCmdlet.ParameterSetName -eq "Boot") {
    $boot=$proof
    if ($boot.installation_mode -ne 'standalone-prepared-app64' -or
        -not $boot.startvm_returned_zero -or -not $boot.poweroff_succeeded -or
        $boot.final_vm_state -ne 'poweroff' -or $boot.orphaned_vm_process_count -ne 0) {
        throw 'Disposable guest process has not been positively confirmed powered off'
    }
    $bootVerified=$true
} elseif ($PSCmdlet.ParameterSetName -eq "Session") {
    if ($proof.experiment -ne 'compiled-manager-quiescent-session' -or
        $proof.portable_root -ine (Split-Path $app -Parent) -or
        $proof.stage_report -ine $StandaloneReport -or $proof.driver_start_report -ine $DriverStartReport -or
        $proof.no_vbox_processes_verified -ne $true -or $proof.controller_pid -le 0) {
        throw 'No matching Manager-session quiescence evidence'
    }
    # Restrict the CI-only Manager proof to these two exact root-local EXEs.
    # Other cleanup modes retain their stronger original bindings.
    $approvedControllers=@((Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe'),
                           (Join-Path $proof.portable_root 'Portable-VirtualBox.exe'))
    $controller=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
    try {
        if ($controller.StartTime.ToUniversalTime().Ticks.ToString() -ne $proof.controller_created -or
            $controller.MainModule.FileName -notin $approvedControllers) {
            throw 'Manager-session controller changed'
        }
    } finally { $controller.Dispose() }
    if (@(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) {
        throw 'Active VirtualBox process prohibits Manager-session cleanup'
    }
}
if ($PSCmdlet.ParameterSetName -eq "PrivilegedSession") {
    if ($proof.experiment -ne 'privilege-separated-manager-quiescent' -or
        $proof.protected_app -ine $app -or $proof.stage_report -ine $StandaloneReport -or
        $proof.driver_start_report -ine $DriverStartReport -or $proof.no_vbox_processes_verified -ne $true -or
        $proof.controller_image -notin @((Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe'), (Join-Path $proof.portable_root 'Portable-VirtualBox.exe'))) {
        throw 'No matching protected privilege-session proof'
    }
    $controller=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
    try {
        if ($controller.StartTime.ToFileTimeUtc().ToString() -ne $proof.controller_created_filetime -or
            $controller.MainModule.FileName -ine $proof.controller_image) { throw 'Privilege-session controller changed' }
    } finally { $controller.Dispose() }
    if (@(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) {
        throw 'Activity prohibits privileged-session cleanup'
    }
}
if ($PSCmdlet.ParameterSetName -eq "RecoverySession") {
    # Explicit manual recovery: two different controller generations, same
    # pinned launcher image, and the old PID must be ABSENT, not recycled.
    function Test-OriginalControllerAbsent([int]$OldPid) {
        if ($OldPid -le 0) { return $false }
        $observed=Get-CimInstance Win32_Process -Filter "ProcessId=$OldPid" -ErrorAction Stop
        return $null -eq $observed
    }
    if ($proof.experiment -ne 'orphan-manager-quiescent' -or
        $proof.protected_app -ine $app -or
        $proof.stage_report -ine $StandaloneReport -or
        $proof.driver_start_report -ine $DriverStartReport -or
        $proof.no_vbox_processes_verified -ne $true -or
        $proof.original_controller_pid -le 0 -or $proof.controller_pid -le 0 -or
        $proof.original_controller_pid -eq $proof.controller_pid -or
        $proof.original_controller_created_filetime -notmatch '^[1-9][0-9]{10,19}$' -or
        $proof.controller_image -notin @((Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe'), (Join-Path $proof.portable_root 'Portable-VirtualBox.exe'))) {
        throw 'Protected cleanup recovery proof is missing or mismatched'
    }
    $old=Get-Content -LiteralPath (Join-Path (Split-Path $app -Parent) 'session.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if ($old.schema -ne 1 -or -not $old.prepared -or
        $old.controller_pid -ne $proof.original_controller_pid -or
        $old.controller_created_filetime -ne $proof.original_controller_created_filetime -or
        $old.controller_image -ine $proof.controller_image -or
        $old.portable_root -ine $proof.portable_root -or $old.protected_app -ine $app -or
        -not (Test-OriginalControllerAbsent ([int]$proof.original_controller_pid))) {
        throw 'Original protected owner is live, missing or mismatched'
    }
    $current=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
    try {
        if ($current.StartTime.ToFileTimeUtc().ToString() -ne $proof.controller_created_filetime -or
            $current.MainModule.FileName -ine $proof.controller_image) { throw 'Recovery controller generation changed' }
    } finally { $current.Dispose() }
    if (@(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) {
        throw 'Activity prohibits abandoned-session recovery'
    }
}
Assert-ProspectiveCleanupAdmission
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    throw 'Another VirtualBox installation is present'
}
$sys=Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
$packageInf=Join-Path $app 'drivers\vboxsup\VBoxSup.inf'
if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
    (Get-FileHash -LiteralPath $packageInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Driver or INF does not match the verified Oracle package'
}
$sig=Get-AuthenticodeSignature -LiteralPath $sys
if ($sig.Status -ne 'Valid') { throw 'Installed VBoxSup signature invalid' }

# Resolve only the exact new-package identity from the protected stage receipt.
# PnPUtil output is localized and must never authorize package removal.
. (Join-Path $PSScriptRoot 'vbox_sup_package_identity.ps1')
$published=Get-PortableOwnedPublishedInf -InfDirectory (Join-Path $env:SystemRoot 'INF') -Receipt $stage -ExpectedSha256 $pinInf
$installedInf=Join-Path (Join-Path $env:SystemRoot 'INF') $published
if (-not (Test-Path -LiteralPath $installedInf -PathType Leaf) -or
    (Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Published driver INF does not match this exact staged Oracle INF'
}
function Get-VBoxNames {
    return @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
}
function Get-VBoxProcesses {
    return @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(VBox|VirtualBox)' } |
        ForEach-Object { $_.Id } | Sort-Object -Unique)
}
function Run-Bounded([string]$Executable,[string]$Argv,[string]$Label) {
    $stdout=Join-Path $out ($Label+'.stdout.txt')
    $stderr=Join-Path $out ($Label+'.stderr.txt')
    $p=$null
    try {
        $p=Start-Process -FilePath $Executable -ArgumentList $Argv -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Cleanup tool process handle unavailable' }
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) {
            # Service/package teardown may be mutating the host right now.
            # Wait on the exact native child rather than killing/detaching it.
            $p.WaitForExit()
            throw "$Label exceeded safety deadline; native child has exited, ownership must be inspected"
        }
        return [int]$p.ExitCode
    } finally {
        if ($null -ne $p) { $p.Dispose() }
    }
}
    $expectedSds=Join-Path $app 'VBoxSDS.exe'
    $signed=Get-AuthenticodeSignature -LiteralPath $expectedSds
    if ($signed.Status -ne 'Valid' -or $signed.SignerCertificate.Subject -notmatch 'Oracle') { throw 'Unexpected VBoxSDS publisher signature' }
    $services=@(Get-VBoxNames)
    if ($services.Count -ne 2 -or $services -notcontains 'VBoxSup' -or $services -notcontains 'VBoxSDS') {
        throw 'Unexpected registered VirtualBox services after private VM boot'
    }
    $sdsConfig=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
    $sdsImage=([string]$sdsConfig.ImagePath).Trim().Trim('"')
    if ($sdsImage -ine $expectedSds -or [int]$sdsConfig.Type -ne 16 -or
        [int]$sdsConfig.Start -ne 3 -or [string]$sdsConfig.ObjectName -ne 'LocalSystem') {
        throw 'VBoxSDS does not belong to this exact app64'
    }
    for($i=0;$i -lt 45;$i++) {
        $sds=Get-Service -Name VBoxSDS -ErrorAction Stop
        $processes=@(Get-VBoxProcesses)
        if ($sds.Status -eq 'Stopped' -and $processes.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    if ((Get-Service -Name VBoxSDS).Status -ne 'Stopped' -or
        @(Get-VBoxProcesses).Count -ne 0) { throw 'VBoxSDS or another VBox process is still active: no cleanup' }
    # Revalidate service path immediately before Oracle's supported unregister.
    $sdsConfig=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
    if (([string]$sdsConfig.ImagePath).Trim().Trim('"') -ine $expectedSds) { throw 'VBoxSDS changed during idle wait' }
# Commit cleanup admission only after the read-only preflight.
# Failure before this boundary leaves no cleanup proof/output. A new explicit
# call repeats validation. Once a proof exists no uncertain attempt can replay.
Assert-ProspectiveCleanupAdmission
if ($prospective) {
    $proofStream=$null
    try {
        $proofStream=[IO.File]::Open($proofPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $proofStream.Write($proofBytes,0,$proofBytes.Length)
        $proofStream.Flush($true)
    } finally {
        if ($null -ne $proofStream) { $proofStream.Dispose() }
    }
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output evidence directory already exists' }
$out=(New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$report=[ordered]@{
    experiment='disposable-owned-VBoxSup-stop-and-remove'
    source_commit=$env:GITHUB_SHA
    oracle_version='7.2.22'
    published_inf=$published
    original_service_baseline_empty=$true
    vm_powered_off_before_cleanup=$bootVerified
    cleanup_basis=$PSCmdlet.ParameterSetName
    sds_cleanup='NOT_ATTEMPTED'
    service_stop='NOT_ATTEMPTED'
    driver_package_removal='NOT_ATTEMPTED'
    service_delete='NOT_ATTEMPTED'
    # Diagnostics only: entering a dispatch is not proof that a child launched.
    # Null result fields mean the protected boundary returned no observation.
    operation_observations=[ordered]@{
        sds_cleanup=[ordered]@{dispatch_entered=$false;within_deadline=$null;exit_code_known=$null;exit_code=$null}
        service_stop=[ordered]@{dispatch_entered=$false;within_deadline=$null;exit_code_known=$null;exit_code=$null}
        driver_package_removal=[ordered]@{dispatch_entered=$false;within_deadline=$null;exit_code_known=$null;exit_code=$null}
        service_delete=[ordered]@{dispatch_entered=$false;within_deadline=$null;exit_code_known=$null;exit_code=$null}
    }
    final_vbox_services=@()
    cleanup_verified=$false
    driver_package_removed=$false
    errors=@()
}
try {
    # Admission is one-shot even if a late observation now refuses execution.
    # Never infer ownership from preflight alone or erase committed evidence.
    if ($prospective) {
        $live=[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)
        try {
            if ($live.StartTime.ToFileTimeUtc().ToString() -ne $proof.controller_created_filetime -or
                $live.MainModule.FileName -ine $proof.controller_image) { throw 'Cleanup controller changed after admission' }
        } finally { $live.Dispose() }
        if ($cleanupParameterSet -eq 'RecoverySession' -and
            -not (Test-OriginalControllerAbsent ([int]$proof.original_controller_pid))) { throw 'Original owner returned after admission' }
    }
    $sdsConfig=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
    if (([string]$sdsConfig.ImagePath).Trim().Trim('"') -ine $expectedSds -or
        [int]$sdsConfig.Type -ne 16 -or [int]$sdsConfig.Start -ne 3 -or
        [string]$sdsConfig.ObjectName -ne 'LocalSystem' -or
        (Get-Service -Name VBoxSDS -ErrorAction Stop).Status -ne 'Stopped' -or
        @(Get-VBoxProcesses).Count -ne 0) { throw 'VBoxSDS changed after cleanup admission' }
    if ($env:PVBOX_FIXED_HELPER_MODE) {
        if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected SDS mode' }
        $report.sds_cleanup='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.sds_cleanup.dispatch_entered=$true
        $sdsResult=Invoke-ProtectedSds -Operation UnregisterFull -TimeoutSeconds $TimeoutSeconds
        $report.operation_observations.sds_cleanup.within_deadline=[bool]$sdsResult.WithinDeadline
        $report.operation_observations.sds_cleanup.exit_code_known=[bool]$sdsResult.ExitCodeKnown
        if ($sdsResult.ExitCodeKnown) {
            $report.operation_observations.sds_cleanup.exit_code=[int]$sdsResult.ExitCode
            $report.sds_cleanup="EXIT_$([int]$sdsResult.ExitCode)"
        }
        if (-not $sdsResult.WithinDeadline) { throw 'SDS unregistration exceeded safety deadline; child exited, retain resources' }
        if (-not $sdsResult.ExitCodeKnown) { throw 'SDS unregistration exit code unavailable' }
        $sdsExit=[int]$sdsResult.ExitCode
    } else {
        # Explicit standalone fixture path, not a fallback on protected failure.
        $report.sds_cleanup='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.sds_cleanup.dispatch_entered=$true
        $sdsExit=Run-Bounded $expectedSds '--unregservice' 'sds-unregister'
        $report.operation_observations.sds_cleanup.within_deadline=$true
        $report.operation_observations.sds_cleanup.exit_code_known=$true
        $report.operation_observations.sds_cleanup.exit_code=$sdsExit
        $report.sds_cleanup="EXIT_$sdsExit"
    }
    if ($sdsExit -ne 0 -or (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
        throw "Exact VBoxSDS unregistration failed: $sdsExit"
    }
    $report.sds_cleanup='CLEAN'
    $names=@(Get-VBoxNames)
    if ($names.Count -ne 1 -or $names[0] -ne 'VBoxSup' -or @(Get-VBoxProcesses).Count -ne 0) {
        throw 'Unexpected VBox resource remained after VBoxSDS cleanup'
    }
    $service=Get-Service -Name VBoxSup -ErrorAction Stop
    $reg=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
    if ($service.Status -ne 'Running' -or [int]$reg.Type -ne 1 -or
        ([string]$reg.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys') -or
        (Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys) {
        throw 'VBoxSup image/status changed since owned acquisition'
    }
    $sc=Join-Path $env:SystemRoot 'System32\sc.exe'
    if ($env:PVBOX_FIXED_HELPER_MODE) {
        if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected driver mode' }
        $report.service_stop='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.service_stop.dispatch_entered=$true
        $fixed=Invoke-ProtectedDriver -Operation StopSup -TimeoutSeconds $TimeoutSeconds
        $report.operation_observations.service_stop.within_deadline=[bool]$fixed.WithinDeadline
        $report.operation_observations.service_stop.exit_code_known=[bool]$fixed.ExitCodeKnown
        if ($fixed.ExitCodeKnown) {
            $report.operation_observations.service_stop.exit_code=[int]$fixed.ExitCode
            $report.service_stop="EXIT_$([int]$fixed.ExitCode)"
        }
        if (-not $fixed.WithinDeadline) { throw 'sup-stop exceeded safety deadline; native child has exited, ownership must be inspected' }
        if (-not $fixed.ExitCodeKnown) { throw 'Driver cleanup exit code unavailable' }
        $stopExit=[int]$fixed.ExitCode
    } else {
        $report.service_stop='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.service_stop.dispatch_entered=$true
        $stopExit=Run-Bounded $sc 'stop VBoxSup' 'sup-stop'
        $report.operation_observations.service_stop.within_deadline=$true
        $report.operation_observations.service_stop.exit_code_known=$true
        $report.operation_observations.service_stop.exit_code=$stopExit
        $report.service_stop="EXIT_$stopExit"
    }
    $report.service_stop="EXIT_$stopExit"
    if ($stopExit -ne 0) { throw 'VBoxSup stop failed; retain package without deletion' }
    for($i=0;$i -lt 20;$i++) {
        if ((Get-Service -Name VBoxSup -ErrorAction Stop).Status -eq 'Stopped') { break }
        Start-Sleep -Seconds 1
    }
    if ((Get-Service -Name VBoxSup -ErrorAction Stop).Status -ne 'Stopped' -or
        @(Get-VBoxProcesses).Count -ne 0) { throw 'VBoxSup not safely stopped: no package removal' }
    $names=@(Get-VBoxNames)
    if ($names.Count -ne 1 -or $names[0] -ne 'VBoxSup') { throw 'Driver state changed before removal' }
    if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
        (Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
        throw 'Unexpected driver/INF mutation before package removal'
    }
    $pnputil=Join-Path $env:SystemRoot 'System32\pnputil.exe'
    # No /force and no wildcard; Windows PnP manager owns the package teardown.
    if ($env:PVBOX_FIXED_HELPER_MODE) {
        if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected driver mode' }
        $report.driver_package_removal='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.driver_package_removal.dispatch_entered=$true
        $fixed=Invoke-ProtectedDriver -Operation RemoveSupPackage -TimeoutSeconds $TimeoutSeconds
        $report.operation_observations.driver_package_removal.within_deadline=[bool]$fixed.WithinDeadline
        $report.operation_observations.driver_package_removal.exit_code_known=[bool]$fixed.ExitCodeKnown
        if ($fixed.ExitCodeKnown) {
            $report.operation_observations.driver_package_removal.exit_code=[int]$fixed.ExitCode
            $report.driver_package_removal="EXIT_$([int]$fixed.ExitCode)"
        }
        if (-not $fixed.WithinDeadline) { throw 'sup-package-remove exceeded safety deadline; native child has exited, ownership must be inspected' }
        if (-not $fixed.ExitCodeKnown) { throw 'Driver cleanup exit code unavailable' }
        $removeExit=[int]$fixed.ExitCode
    } else {
        $report.driver_package_removal='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
        $report.operation_observations.driver_package_removal.dispatch_entered=$true
        $removeExit=Run-Bounded $pnputil "/delete-driver $published /uninstall" 'sup-package-remove'
        $report.operation_observations.driver_package_removal.within_deadline=$true
        $report.operation_observations.driver_package_removal.exit_code_known=$true
        $report.operation_observations.driver_package_removal.exit_code=$removeExit
        $report.driver_package_removal="EXIT_$removeExit"
    }
    $report.driver_package_removal="EXIT_$removeExit"
    if ($removeExit -ne 0) { throw 'PnPUtil refused driver package deletion' }
    # PnPUtil may defer kernel-service cleanup. Observe for a bounded period
    # before deciding the package was completely removed; never force-delete.
    for($i=0;$i -lt 25;$i++) {
        $afterServices=@(Get-VBoxNames)
        if ($afterServices.Count -eq 0 -and -not (Test-Path -LiteralPath $installedInf)) { break }
        Start-Sleep -Seconds 1
    }
    $afterServices=@(Get-VBoxNames)
    $report.final_vbox_services=$afterServices
    $report.published_inf_present=(Test-Path -LiteralPath $installedInf)
    $report.system_driver_file_present=(Test-Path -LiteralPath $sys)
    $driverSvc=Get-Service -Name VBoxSup -ErrorAction SilentlyContinue
    $report.service_state_after=$(if ($null -eq $driverSvc) { 'ABSENT' } else { [string]$driverSvc.Status })
    # DriverStore cleanup and kernel service deletion are distinct operations.
    # The Oracle primitive driver can leave a STOPPED VBoxSup service entry even
    # after PnPUtil removes both the published INF and VBoxSup.sys.
    $report.driver_package_removed=(-not $report.published_inf_present -and -not $report.system_driver_file_present)
    if (-not $report.driver_package_removed) {
        throw 'Driver package or system driver remains: never manually remove its service'
    }
    if ($afterServices.Count -eq 1 -and $afterServices[0] -eq 'VBoxSup') {
        $remaining=Get-Service -Name VBoxSup -ErrorAction Stop
        $config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
        if ($remaining.Status -ne 'Stopped' -or [int]$config.Type -ne 1 -or
            ([string]$config.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys') -or
            @(Get-VBoxProcesses).Count -ne 0 -or
            (Test-Path -LiteralPath $installedInf) -or (Test-Path -LiteralPath $sys)) {
            throw 'Residual VBoxSup service does not meet exact exclusive-removal conditions'
        }
        # Only on our fresh disposable host after its own exact driver package
        # was removed and only the expected stopped service key remains.
        # This is not an unscoped wildcard deletion or production routine.
        if ($env:PVBOX_FIXED_HELPER_MODE) {
            if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected driver mode' }
            $report.service_delete='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
            $report.operation_observations.service_delete.dispatch_entered=$true
            $fixed=Invoke-ProtectedDriver -Operation DeleteSupService -TimeoutSeconds $TimeoutSeconds
            $report.operation_observations.service_delete.within_deadline=[bool]$fixed.WithinDeadline
            $report.operation_observations.service_delete.exit_code_known=[bool]$fixed.ExitCodeKnown
            if ($fixed.ExitCodeKnown) {
                $report.operation_observations.service_delete.exit_code=[int]$fixed.ExitCode
                $report.service_delete="EXIT_$([int]$fixed.ExitCode)"
            }
            if (-not $fixed.WithinDeadline) { throw 'sup-service-delete exceeded safety deadline; native child has exited, ownership must be inspected' }
            if (-not $fixed.ExitCodeKnown) { throw 'Driver cleanup exit code unavailable' }
            $deleteExit=[int]$fixed.ExitCode
        } else {
            $report.service_delete='DISPATCH_ENTERED_OUTCOME_UNKNOWN'
            $report.operation_observations.service_delete.dispatch_entered=$true
            $deleteExit=Run-Bounded $sc 'delete VBoxSup' 'sup-service-delete'
            $report.operation_observations.service_delete.within_deadline=$true
            $report.operation_observations.service_delete.exit_code_known=$true
            $report.operation_observations.service_delete.exit_code=$deleteExit
            $report.service_delete="EXIT_$deleteExit"
        }
        $report.service_delete="EXIT_$deleteExit"
        if ($deleteExit -ne 0) { throw 'Exact stopped VBoxSup service delete failed' }
        for($i=0;$i -lt 25;$i++) {
            if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup')) { break }
            Start-Sleep -Seconds 1
        }
    }
    $report.final_vbox_services=@(Get-VBoxNames)
    $report.cleanup_verified=($report.final_vbox_services.Count -eq 0 -and
        @(Get-VBoxProcesses).Count -eq 0 -and
        -not (Test-Path -LiteralPath $sys) -and
        -not (Test-Path -LiteralPath $installedInf))
    if (-not $report.cleanup_verified) {
        throw 'Driver package removal returned success, but system is not verified clean'
    }
} catch {
    $report.errors+= $_.Exception.Message
} finally {
    # A failed final observation must not suppress the original error/step
    # evidence, or make an unreadable service namespace look empty. This is
    # diagnostic evidence only: it grants no retry or cleanup authority.
    $report.final_vbox_services=$null
    $report.final_vbox_services_observation='UNKNOWN'
    try {
        $observedServices=@(Get-VBoxNames)
        $report.final_vbox_services=$observedServices
        $report.final_vbox_services_observation='OBSERVED'
        if ($observedServices.Count -ne 0) {
            $report.cleanup_verified=$false
            $report.errors+='VirtualBox services remain at final observation'
        }
    } catch {
        $report.cleanup_verified=$false
        $report.errors+='Final VirtualBox service observation failed; state UNKNOWN'
    }
    # Write failures remain fatal. Never claim that evidence was saved if not.
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'cleanup-results.json') -Encoding utf8
}
Write-Host "VBoxSup cleanup: SDS=$($report.sds_cleanup), stop=$($report.service_stop), PnP=$($report.driver_package_removal), removed=$($report.driver_package_removed)"
if ($report.errors.Count) { throw ($report.errors -join '; ') }
