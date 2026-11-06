# Durable-checkpoint recovery of an interrupted signed-driver preparation.
# Faults are injected AFTER recorded operations, not mid-PnP mutation.
# This validates exactly three proven checkpoints on disposable Windows only.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot,
    [ValidateSet('normal','tamper-stage','tamper-sds')][string]$Scenario='normal')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Disposable hosted Windows runner only'
}
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not ($root+'\').StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Untrusted test input path' }
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$exe=Join-Path $root 'Portable-VirtualBox-Session-Test.exe'
$helper=Join-Path $root 'Portable-VirtualBox-Helper-Test.exe'
$store=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment'
$out=Join-Path $env:RUNNER_TEMP 'partial-preparation-proof'
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
Add-Type -Path @((Join-Path $repo 'source/privilege/TokenFacts.cs'), (Join-Path $PSScriptRoot 'MediumProcess.cs'))
$old=$null;$new=$null
$proof=[ordered]@{source_commit=$env:GITHUB_SHA;scenario=$Scenario;interactive_uac_verified=$false;
    guest_os_booted=$false;validated_checkpoints=@();original_data_preserved=$false;
    two_copies=$false;live_owner_denied=$false;missing_receipt_denied=$false;
    all_owned_services_removed=$false;forged_receipts_denied=$false;
    system_effects_retained_due_to_refusal=$false;unauthorized_cleanups=0}
function Start-Medium([string]$Image,[string]$Label) {
    $p=[MediumProcess]::Start($Image,'--lang en --separate-privileges',$root,
        (Join-Path $out ($Label+'.stdout.txt')),(Join-Path $out ($Label+'.stderr.txt')))
    [MediumProcess]::LastFacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($Label+'-token.json')) -Encoding utf8
    if ($p.WaitForExit(500)) { throw "User frontend unexpectedly exited: $Label" }
    return $p
}
function Helper([string]$Arguments,[int]$Expected,[string]$Label) {
    $p=Start-Process -FilePath $helper -ArgumentList $Arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
    try {
        if (-not $p.WaitForExit(150000)) { throw "Helper timeout: $Label" }
        if ($p.ExitCode -ne $Expected) { throw "$Label helper exit=$($p.ExitCode), expected=$Expected" }
    } finally { $p.Dispose() }
}
function Assert-Clean([string]$Label) {
    $services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop | Where-Object PSChildName -match '^VBox')
    $processes=@(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)')
    if ($services.Count -ne 0 -or $processes.Count -ne 0 -or
        (Test-Path (Join-Path $env:WINDIR 'System32\drivers\VBoxSup.sys'))) {
        throw "Unexpected VirtualBox resource after $Label"
    }
}
function Await-Close([Diagnostics.Process]$p,[string]$Label) {
    if (-not $p.CloseMainWindow() -or -not $p.WaitForExit(15000) -or $p.ExitCode -ne 0) {
        throw "$Label could not exit cleanly"
    }
}
try {
    Assert-Clean 'original baseline'
    foreach($sub in @('data','data\.VirtualBox','data\Machines','logs')) {
        New-Item -ItemType Directory -Path (Join-Path $root $sub) -Force -ErrorAction Stop | Out-Null
    }
    $sentinel1=Join-Path $root 'data\Machines\Основа-VM.vbox'
    $sentinel2=Join-Path $root 'data\.VirtualBox\VirtualBox.xml'
    [IO.File]::WriteAllText($sentinel1,'VM data must survive stage/start/SDS recovery')
    [IO.File]::WriteAllText($sentinel2,'portable Oracle settings must survive')
    $hash1=(Get-FileHash -LiteralPath $sentinel1 -Algorithm SHA256).Hash
    $hash2=(Get-FileHash -LiteralPath $sentinel2 -Algorithm SHA256).Hash
    $proof.two_copies=$true
    $i=0
    # A *denied* recovery is one-shot and MUST NOT be rearmed after tampering:
    # each adversarial case gets an independent disposable Windows VM runner.
    # Normal recovery validates all three phases with clean host between cycles.
    $phases=if($Scenario -eq 'tamper-stage') { @('Stage') }
        elseif($Scenario -eq 'tamper-sds') { @('Sds') }
        else { @('Stage','Start','Sds') }
    foreach($phase in $phases) {
        $i++
        $cycle=$i+20
        $label=$phase.ToLowerInvariant()
        $old=Start-Medium $exe ('owner-'+$label)
        $oldPid=$old.Id
        $env:PVBOX_TEST_BREAK_AT=$phase
        try {
            Helper ('Prepare '+$oldPid+' '+$cycle) 70 ('break-after-'+$label)
        } finally { Remove-Item Env:\PVBOX_TEST_BREAK_AT -ErrorAction SilentlyContinue }
        $session=Join-Path $store ('pvbox-manager-'+$oldPid+'-'+$cycle)
        if ((Test-Path -LiteralPath (Join-Path $session 'session.json')) -or
            -not (Test-Path -LiteralPath (Join-Path $session 'prepare-intent.json')) -or
            -not (Test-Path -LiteralPath (Join-Path $session 'stage\sup-standalone.json'))) {
            throw 'Injected break did not leave expected protected incomplete preparation'
        }
        $reason=@(Get-ChildItem -LiteralPath $session -Filter 'helper-Prepare-*.stderr.txt' -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        if ($reason -notmatch ('CI_TEST_BREAK_AFTER_'+$phase.ToUpperInvariant())) { throw 'Break happened before the requested checkpoint' }
        if ($phase -eq 'Stage' -and (Get-Service VBoxSup).Status -ne 'Stopped') { throw 'Stage expected stopped VBoxSup' }
        if ($phase -ne 'Stage' -and (Get-Service VBoxSup).Status -ne 'Running') { throw 'Start expected running VBoxSup' }
        $new=Start-Medium $exe ('rescue-'+$label)
        # A newly started controller must not steal ownership while old PID is live.
        Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 ('live-owner-denied-'+$label)
        $proof.live_owner_denied=$true
        $svc=Get-Service VBoxSup -ErrorAction Stop
        if ($svc.Status -notin @('Running','Stopped')) { throw 'Refusal changed protected driver state' }
        Await-Close $old ('old-'+$label)
        $old.Dispose();$old=$null
        if (@(Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid").Count -ne 0) { throw 'Former controller PID not absent' }
        if ($phase -eq 'Start') {
            # Remove the only exclusive staging receipt to prove refusal.
            # This CI admin is the only writer; restore the exact original bytes.
            $stagePath=Join-Path $session 'stage\sup-standalone.json'
            $stageBytes=[IO.File]::ReadAllBytes($stagePath)
            try {
                [IO.File]::Delete($stagePath)
                Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'missing-receipt-denied'
                $proof.missing_receipt_denied=$true
                if ((Get-Service VBoxSup).Status -ne 'Running') { throw 'Missing proof altered driver' }
            } finally { [IO.File]::WriteAllBytes($stagePath,$stageBytes) }
        }
        if ($Scenario -eq 'tamper-stage' -and $phase -eq 'Stage') {
            # Test-only corruption of protected journal on disposable host.
            # Once denied, DO NOT repair the journal and retry on this host:
            # one-shot quiescence is already consumed, preserving uncertainty.
            $stagePath=Join-Path $session 'stage\sup-standalone.json'
            $record=Get-Content -LiteralPath $stagePath -Raw | ConvertFrom-Json
            $record.system_driver_sha256='0000000000000000000000000000000000000000000000000000000000000000'
            $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $stagePath -Encoding utf8
            Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'forged-stage-receipt-denied'
            if ((Get-Service VBoxSup).Status -ne 'Stopped') { throw 'Forged stage receipt changed service state' }
            $evidence=@(Get-ChildItem -LiteralPath $session -Filter 'helper-Recover-*.stderr.txt' -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
            # Windows PowerShell 5.1 wraps emitted errors at console width.
            # Normalize only whitespace in the diagnostic, never the forged
            # receipt or the independent real driver/service observations.
            $evidence=($evidence -replace '\s+', ' ').Trim()
            if ($evidence -notmatch 'No exact exclusive VBoxSup staging receipt') {
                throw 'Stage receipt refusal did not reach exact ownership check'
            }
            if ((Get-FileHash -LiteralPath $sentinel1 -Algorithm SHA256).Hash -ne $hash1 -or
                (Get-FileHash -LiteralPath $sentinel2 -Algorithm SHA256).Hash -ne $hash2) { throw 'Corrupt stage changed VM data' }
            $proof.forged_receipts_denied=$true
            $proof.original_data_preserved=$true
            $proof.system_effects_retained_due_to_refusal=$true
            Write-Host 'PASS: forged-stage-receipt-denied; protected resources retained, manual inspection required, hosted runner discarded'
            return
        }
        if ($Scenario -eq 'tamper-sds' -and $phase -eq 'Sds') {
            $markerPath=Join-Path $session 'sds-registered.json'
            $record=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
            $record.registered=$false
            $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $markerPath -Encoding utf8
            Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'forged-sds-marker-denied'
            if ((Get-Service VBoxSup).Status -ne 'Running' -or
                -not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
                throw 'Forged SDS marker changed real driver or SDS service'
            }
            $evidence=@(Get-ChildItem -LiteralPath $session -Filter 'helper-Recover-*.stderr.txt' -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
            $evidence=($evidence -replace '\s+', ' ').Trim()
            if ($evidence -notmatch 'SDS marker owner differs') {
                throw 'SDS marker refusal did not reach exact ownership check'
            }
            if ((Get-FileHash -LiteralPath $sentinel1 -Algorithm SHA256).Hash -ne $hash1 -or
                (Get-FileHash -LiteralPath $sentinel2 -Algorithm SHA256).Hash -ne $hash2) { throw 'Corrupt SDS marker changed VM data' }
            $proof.forged_receipts_denied=$true
            $proof.original_data_preserved=$true
            $proof.system_effects_retained_due_to_refusal=$true
            Write-Host 'PASS: forged-sds-marker-denied; protected resources retained, manual inspection required, hosted runner discarded'
            return
        }
        Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 0 ('recover-'+$label)
        Assert-Clean ('after-recovery-clean-'+$label)
        $result=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if ($result.cleanup_basis -ne 'PartialRecovery' -or $result.validated_checkpoint -ne $phase -or
            -not $result.cleanup_verified -or -not $result.driver_package_removed) {
            throw 'Final PartialRecovery evidence does not match exact checkpoint'
        }
        if ((Test-Path (Join-Path $session 'app64')) -or (Test-Path (Join-Path $session 'code')) -or
            -not (Test-Path (Join-Path $session 'payload-removed.json'))) { throw 'Protected executable cache remained' }
        Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 ('replay-denied-'+$label)
        if ((Get-FileHash -LiteralPath $sentinel1 -Algorithm SHA256).Hash -ne $hash1 -or
            (Get-FileHash -LiteralPath $sentinel2 -Algorithm SHA256).Hash -ne $hash2) {
            throw 'Portable VM data altered by driver recovery'
        }
        $proof.validated_checkpoints+= $phase
        Await-Close $new ('rescue-'+$label)
        $new.Dispose();$new=$null
        Write-Host "PASS: $phase partial recovery, owner/refusal/replay proof, after-recovery-clean, VM data preserved"
    }
    $proof.original_data_preserved=$true
    $proof.all_owned_services_removed=$true
    Write-Host 'PASS: protected PartialRecovery at Stage, Start, Sds checkpoints; old owner refused, missing-receipt-denied, forged-receipt-denied, after-recovery-clean, two_copies original_data_preserved; UAC NOT VERIFIED'
} catch { $proof.error=$_.Exception.Message;throw }
finally {
    $proof | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'interrupted-recovery-proof.json') -Encoding utf8
    foreach($proc in @($old,$new)) { if ($null -ne $proc) { $proc.Dispose() } }
    Remove-Item Env:\PVBOX_TEST_BREAK_AT -ErrorAction SilentlyContinue
}
