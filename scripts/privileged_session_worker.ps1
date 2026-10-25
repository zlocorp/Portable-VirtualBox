# Embedded in the fixed compiled helper; never chosen by a frontend argument.
# System effects only. User profile configuration and Manager run in the frontend.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Finish','Recover')][string]$Action,
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$SessionDir,
    [Parameter(Mandatory)][int]$ControllerPid,
    [Parameter(Mandatory)][long]$ControllerCreated,
    [Parameter(Mandatory)][ValidateSet('Portable-VirtualBox.exe','Portable-VirtualBox-Session-Test.exe')][string]$FrontendName,
    [ValidateRange(0,2147483647)][int]$OriginalControllerPid = 0,
    [ValidateRange(0,9223372036854775807)][long]$OriginalControllerCreated = 0,
    [switch]$IncompletePreparation,
    [ValidateSet('None','Stage','Start','Sds')][string]$TestBreakAfter = 'None'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# The system worker is always launched from the OS-owned x64 Windows PowerShell,
# never an optionally installed pwsh or user-selected executable.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Only Windows PowerShell 5.1 is accepted for the protected effect worker'
}
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable Windows only' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated helper token required' }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$session=(Resolve-Path -LiteralPath $SessionDir).Path
$app=Join-Path $session 'app64'
$parentId=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$parent=[Diagnostics.Process]::GetProcessById($parentId)
try {
    if ($parent.MainModule.FileName -ine (Join-Path $root 'Portable-VirtualBox-Helper-Test.exe')) { throw 'Not the fixed compiled helper' }
} finally { $parent.Dispose() }
$caller=[Diagnostics.Process]::GetProcessById($ControllerPid)
try {
    if ($caller.MainModule.FileName -ine (Join-Path $root $FrontendName) -or
        $caller.StartTime.ToFileTimeUtc() -ne $ControllerCreated) { throw 'Controller generation changed' }
    $controllerImage=$caller.MainModule.FileName
} finally { $caller.Dispose() }
# Missing PID means the old controller is gone. A recycled PID or an
# inaccessible process is UNKNOWN and forbids all recovery mutations.
function Test-OriginalControllerAbsent([int]$OldPid) {
    if ($OldPid -le 0) { return $false }
    $observed=Get-CimInstance Win32_Process -Filter "ProcessId=$OldPid" -ErrorAction Stop
    return $null -eq $observed
}
function VBox-Processes { return @(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)') }
function Run-Sds([string]$Argument,[string]$Label) {
    $p=Start-Process -FilePath (Join-Path $app 'VBoxSDS.exe') -ArgumentList $Argument -WorkingDirectory $app -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $session ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $session ($Label+'.stderr.txt'))
    try {
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'SDS process handle unavailable' }
        if (-not $p.WaitForExit(30000) -or $p.ExitCode -ne 0) { throw 'SDS operation unconfirmed; retain resources' }
    } finally { $p.Dispose() }
}
try {
    if ($Action -eq 'Prepare') {
        # Helper created and fsync'd protected prepare-intent.json BEFORE
        # launching any system action. This worker only emits post-effect proof.
        if (-not (Test-Path -LiteralPath (Join-Path $session 'prepare-intent.json') -PathType Leaf)) {
            throw 'Missing durable protected pre-effect intent'
        }
        & (Join-Path $PSScriptRoot 'vbox_sup_standalone.ps1') -AppDir $app -OutputDirectory (Join-Path $session 'stage')
        if ($TestBreakAfter -eq 'Stage') { throw 'CI_TEST_BREAK_AFTER_STAGE: protected installation report committed' }
        & (Join-Path $PSScriptRoot 'vbox_sup_start_owned.ps1') -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -OutputDirectory (Join-Path $session 'start')
        if ($TestBreakAfter -eq 'Start') { throw 'CI_TEST_BREAK_AFTER_START: protected driver start report committed' }
        if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS') { throw 'SDS appeared before our explicit registration' }
        Run-Sds '--regservice' 'sds-register'
        $sds=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
        if (([string]$sds.ImagePath).Trim().Trim('"') -ine (Join-Path $app 'VBoxSDS.exe') -or
            $sds.Type -ne 16 -or $sds.Start -ne 3 -or $sds.ObjectName -ne 'LocalSystem') { throw 'SDS registration identity differs' }
        # The final SDS effect is recorded independently BEFORE the final
        # prepared session receipt. A crash between registration and this marker
        # remains ambiguous and requires manual handling, not guessed cleanup.
        [ordered]@{schema=1;registered=$true;protected_app=$app;
            controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();
            sds_image=(Join-Path $app 'VBoxSDS.exe');source_commit=$env:GITHUB_SHA} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'sds-registered.json') -Encoding utf8
        if ($TestBreakAfter -eq 'Sds') { throw 'CI_TEST_BREAK_AFTER_SDS: protected service registration marker committed' }
        [ordered]@{schema=1;portable_root=$root;protected_app=$app;controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;prepared=$true;source_commit=$env:GITHUB_SHA} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding utf8
        Write-Host 'PRIVILEGED_PREPARED_WITHOUT_USER_PROFILE_EXECUTION'
    } else {
        if ($Action -eq 'Recover' -and $IncompletePreparation) {
            # A protected intent alone is not a driver ownership receipt. Stage
            # result must have committed; earlier and uncertain phases refuse.
            if (-not (Test-Path -LiteralPath (Join-Path $session 'stage\sup-standalone.json') -PathType Leaf)) {
                throw 'Incomplete preparation has no exclusive driver staging proof'
            }
            if (Test-Path -LiteralPath (Join-Path $session 'session.json')) { throw 'Completed session is not an interrupted preparation' }
            $intent=Get-Content -LiteralPath (Join-Path $session 'prepare-intent.json') -Raw | ConvertFrom-Json
            if ($intent.schema -ne 1 -or $intent.phase -ne 'pre-system-effects' -or
                $intent.portable_root -ine $root -or $intent.protected_app -ine $app -or
                $intent.controller_pid -ne $OriginalControllerPid -or
                $intent.controller_created_filetime -ne $OriginalControllerCreated.ToString() -or
                $OriginalControllerPid -le 0 -or $OriginalControllerPid -eq $ControllerPid -or
                -not (Test-OriginalControllerAbsent $OriginalControllerPid) -or
                (Test-Path -LiteralPath (Join-Path $session 'cleanup')) -or
                (Test-Path -LiteralPath (Join-Path $session 'partial-recovery-quiescent.json'))) {
                throw 'Incomplete preparation protected owner mismatch or replay'
            }
            if (@(VBox-Processes).Count -ne 0) { throw 'Active VBox activity; partial preparation recovery denied' }
            $partialProof=Join-Path $session 'partial-recovery-quiescent.json'
            [ordered]@{schema=1;experiment='partial-protected-manager-quiescent';portable_root=$root;
                protected_app=$app;original_controller_pid=$OriginalControllerPid;
                original_controller_created_filetime=$OriginalControllerCreated.ToString();
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();
                controller_image=$controllerImage;no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $partialProof -Encoding utf8
            if (-not (Test-OriginalControllerAbsent $OriginalControllerPid)) { throw 'Old owner reappeared before partial recovery' }
            & (Join-Path $PSScriptRoot 'vbox_sup_partial_cleanup.ps1') -AppDir $app -SessionDir $session -PartialRecoveryReport $partialProof -OutputDirectory (Join-Path $session 'cleanup') -OriginalControllerCreated $OriginalControllerCreated
            $clean=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
            if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or @(VBox-Processes).Count -ne 0) {
                throw 'Partial preparation teardown unconfirmed'
            }
            Write-Host 'PRIVILEGED_INCOMPLETE_PREPARATION_RECOVERED'
            exit 0
        }
        $receipt=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw | ConvertFrom-Json
        if ($receipt.schema -ne 1 -or -not $receipt.prepared -or $receipt.portable_root -ine $root -or $receipt.protected_app -ine $app) {
            throw 'Not our protected session'
        }
        if ($Action -eq 'Recover') {
            if ($OriginalControllerPid -le 0 -or $OriginalControllerPid -eq $ControllerPid -or $OriginalControllerCreated -le 0 -or
                $receipt.controller_pid -ne $OriginalControllerPid -or
                $receipt.controller_created_filetime -ne $OriginalControllerCreated.ToString() -or
                $receipt.controller_image -ine $controllerImage -or
                -not (Test-OriginalControllerAbsent $OriginalControllerPid) -or
                (Test-Path -LiteralPath (Join-Path $session 'cleanup'))) {
                throw 'Untrusted original controller for crash recovery'
            }
        } else {
            if ($receipt.controller_pid -ne $ControllerPid -or $receipt.controller_created_filetime -ne $ControllerCreated.ToString() -or
                $receipt.controller_image -ine $controllerImage) { throw 'Changed controller for regular cleanup' }
        }
        if (@(VBox-Processes).Count -ne 0) { throw 'VM/Manager/background activity still present; refusing cleanup' }
        $proof=Join-Path $session $(if ($Action -eq 'Recover') { 'recovery-quiescent.json' } else { 'quiescent-session.json' })
        if ((Test-Path -LiteralPath $proof) -or (Test-Path -LiteralPath (Join-Path $session 'quiescent-session.json')) -or
            (Test-Path -LiteralPath (Join-Path $session 'recovery-quiescent.json'))) { throw 'Refusing cleanup replay' }
        if ($Action -eq 'Recover') {
            # The new live controller's identity and missing former owner are
            # independently revalidated by the cleanup script before effects.
            [ordered]@{experiment='orphan-manager-quiescent';portable_root=$root;protected_app=$app;
                stage_report=(Join-Path $session 'stage\sup-standalone.json');driver_start_report=(Join-Path $session 'start\sup-start-results.json');
                original_controller_pid=$OriginalControllerPid;original_controller_created_filetime=$OriginalControllerCreated.ToString();
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;
                no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $proof -Encoding utf8
            if (-not (Test-OriginalControllerAbsent $OriginalControllerPid)) { throw 'Old controller reappeared before cleanup' }
            & (Join-Path $PSScriptRoot 'vbox_sup_cleanup.ps1') -AppDir $app -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -DriverStartReport (Join-Path $session 'start\sup-start-results.json') -RecoveryReport $proof -OutputDirectory (Join-Path $session 'cleanup')
        } else {
            [ordered]@{experiment='privilege-separated-manager-quiescent';portable_root=$root;protected_app=$app;
                stage_report=(Join-Path $session 'stage\sup-standalone.json');driver_start_report=(Join-Path $session 'start\sup-start-results.json');
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;
                no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $proof -Encoding utf8
            & (Join-Path $PSScriptRoot 'vbox_sup_cleanup.ps1') -AppDir $app -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -DriverStartReport (Join-Path $session 'start\sup-start-results.json') -PrivilegedReport $proof -OutputDirectory (Join-Path $session 'cleanup')
        }
        $clean=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or @(VBox-Processes).Count -ne 0) { throw 'Cleanup not confirmed' }
        Write-Host 'PRIVILEGED_SESSION_CLEAN'
    }
} catch { Write-Error $_; exit 1 }
exit 0
