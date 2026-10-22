# Explicit recovery acceptance on a disposable hosted Windows environment.
# No general OS rescue/cleanup capability: helper accepts only a protected
# session from this signed, pinned launcher, with an absent former controller.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable hosted Windows test only'
}
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not $root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe recovery fixture root' }
$store=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment'
$exe=Join-Path $root 'Portable-VirtualBox-Session-Test.exe'
$helper=Join-Path $root 'Portable-VirtualBox-Helper-Test.exe'
$out=Join-Path $env:RUNNER_TEMP 'orphan-recovery-proof'
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
Add-Type -Path @((Join-Path $PSScriptRoot '../../source/privilege/TokenFacts.cs'), (Join-Path $PSScriptRoot 'MediumProcess.cs'))
$proof=[ordered]@{source_commit=$env:GITHUB_SHA;orphan_recovery_verified=$false;live_owner_refused=$false;live_guest_refused=$false;
    protected_payload_removed=$false;original_vm_data_preserved=$false;interactive_uac_verified=$false;automatic_cleanup=$false}
$old=$null;$new=$null;$guest=$null
function Start-Medium([string]$Image,[string]$Args,[string]$Label,[string]$Working=$root) {
    $p=[MediumProcess]::Start($Image,$Args,$Working,(Join-Path $out ($Label+'.stdout.txt')),(Join-Path $out ($Label+'.stderr.txt')))
    [MediumProcess]::LastFacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($Label+'-token.json')) -Encoding utf8
    return $p
}
function Wait-Code([Diagnostics.Process]$Process,[int]$Expected,[string]$Label,[int]$Seconds=150) {
    if (-not $Process.WaitForExit($Seconds*1000)) { throw "Timeout: $Label" }
    if ($Process.ExitCode -ne $Expected) { throw "$Label exit=$($Process.ExitCode), expected $Expected" }
}
function Helper([string]$Arguments,[int]$Expected,[string]$Label) {
    $p=Start-Process -FilePath $helper -ArgumentList $Arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
    try { Wait-Code $p $Expected $Label } finally { $p.Dispose() }
}
function Oracle([string]$Arguments,[string]$Label) {
    $prior=$env:VBOX_USER_HOME
    try {
        $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
        $p=Start-Medium (Join-Path $runtime 'VBoxManage.exe') $Arguments $Label $runtime
        try { Wait-Code $p 0 $Label 45 } finally { $p.Dispose() }
    } finally { $env:VBOX_USER_HOME=$prior }
    return [string](Get-Content -LiteralPath (Join-Path $out ($Label+'.stdout.txt')) -Raw)
}
function Assert-Clean {
    if (@(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0 -or
        @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object PSChildName -match '^VBox').Count -ne 0 -or
        (Test-Path (Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'))) { throw 'Orphan recovery host not clean' }
}
function Assert-Driver-StillOwned {
    $service=Get-Service VBoxSup -ErrorAction Stop
    if ($service.Status -ne 'Running' -or -not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
        throw 'Refused recovery unexpectedly changed owned driver services'
    }
}
function Wait-RunningLog([Diagnostics.Process]$G,[string]$Log) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 45) {
        if ($G.HasExited) { throw "Guest terminated early ($($G.ExitCode))" }
        if (Test-Path -LiteralPath $Log -PathType Leaf) {
            $last=(Get-Content -LiteralPath $Log -Tail 1000) -join "`n"
            if ($last -match "Changing the VM state from .* to 'RUNNING'") { return }
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'VM log never reached RUNNING'
}
try {
    Assert-Clean
    foreach ($folder in @('data','.\data\.VirtualBox','data\Machines','logs')) {
        New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
    }
    # Workflow already granted only the ephemeral user-owned INPUT root.
    $old=Start-Medium $exe '--lang en --separate-privileges' 'old-controller'
    if ($old.WaitForExit(500)) { throw 'Original controller quit before session' }
    $oldPid=$old.Id
    $cycle=7
    Helper ('Prepare '+$oldPid+' '+$cycle) 0 'prepare-orphan'
    $session=Join-Path $store ('pvbox-manager-'+$oldPid+'-'+$cycle)
    $runtime=Join-Path $session 'app64'
    $receipt=Join-Path $session 'session.json'
    if (-not (Test-Path -LiteralPath $receipt)) { throw 'No protected original session receipt' }
    $new=Start-Medium $exe '--lang en --separate-privileges' 'new-controller'
    if ($new.WaitForExit(500)) { throw 'New controller unavailable for recovery' }
    # Prevent cleanup while the first controller is still alive.
    Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'live-owner-refusal'
    Assert-Driver-StillOwned
    $proof.live_owner_refused=$true
    if (-not $old.CloseMainWindow()) { throw 'Old controller did not accept ordinary close' }
    Wait-Code $old 0 'original controller close' 20
    $old.Dispose();$old=$null
    if (@(Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid").Count -ne 0) { throw 'Original controller generation still live' }
    # Demonstrate separate safety boundary: even with the original owner gone,
    # a live user VM must keep drivers loaded. No blanket name-based killing.
    $null=Oracle ('setproperty machinefolder "'+(Join-Path $root 'data\Machines')+'"') 'set-machinefolder'
    $created=Oracle 'createvm --name pvbox_orphan_fixture --ostype Other --register' 'create-orphan-vm'
    if ($created -notmatch '(?im)^UUID:\s*([0-9a-f-]{36})\s*$') { throw 'Missing recovered test VM UUID' }
    $uuid=$Matches[1]
    $null=Oracle ('modifyvm '+$uuid+' --memory 128 --nic1 none --audio-driver none') 'modify-orphan-vm'
    $config=Join-Path $root 'data\Machines\pvbox_orphan_fixture\pvbox_orphan_fixture.vbox'
    if (-not (Test-Path -LiteralPath $config)) { throw 'Original VM configuration absent' }
    $prior=$env:VBOX_USER_HOME
    try {
        $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
        $guest=Start-Medium (Join-Path $runtime 'VBoxHeadless.exe') ('--startvm '+$uuid+' --vrde off') 'direct-vm' $runtime
    } finally { $env:VBOX_USER_HOME=$prior }
    Wait-RunningLog $guest (Join-Path $root 'data\Machines\pvbox_orphan_fixture\Logs\VBox.log')
    $info=Oracle ('showvminfo '+$uuid+' --machinereadable') 'running-vm'
    if ($info -notmatch '(?m)^VMState="running"') { throw 'Guest did not reach running state' }
    Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'live-guest-refusal'
    Assert-Driver-StillOwned
    $proof.live_guest_refused=$true
    $null=Oracle ('controlvm '+$uuid+' poweroff') 'poweroff-vm'
    Wait-Code $guest 0 'direct guest shutdown' 40
    $guest.Dispose();$guest=$null
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while (@(Get-Process | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) {
        if ($timer.Elapsed.TotalSeconds -gt 75) { throw 'Background busy; no unverified cleanup' }
        Start-Sleep -Milliseconds 250
    }
    $before=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
    # Only this EXPLICIT request with a new bounded medium controller may
    # remove the exclusively owned, now idle orphan resources.
    Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 0 'recover-orphan'
    Assert-Clean
    $result=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
    if ($result.cleanup_basis -ne 'RecoverySession' -or -not $result.cleanup_verified -or -not $result.driver_package_removed) {
        throw 'Recovery cleanup receipt unverified'
    }
    if ((Test-Path -LiteralPath $runtime) -or (Test-Path -LiteralPath (Join-Path $session 'code')) -or
        -not (Test-Path -LiteralPath (Join-Path $session 'payload-removed.json'))) { throw 'Protected code was retained' }
    $proof.protected_payload_removed=$true
    if ((Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ne $before) { throw 'Original VM data changed during recovery' }
    $proof.original_vm_data_preserved=$true
    Helper ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) 70 'replay-refusal'
    $proof.orphan_recovery_verified=$true
    $proof.uuid=$uuid
    $proof.session=$session
    if (-not $new.CloseMainWindow()) { throw 'New medium controller did not accept close' }
    Wait-Code $new 0 'new controller close' 20
    Write-Host 'PASS: explicit protected abandoned-session recovery, live owner and live guest refusal, protected payload removal, original VM data preserved; interactive UAC NOT VERIFIED'
} catch { $proof.error=$_.Exception.Message;throw } finally {
    $proof | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'orphan-recovery-proof.json') -Encoding utf8
    foreach ($p in @($old,$new,$guest)) { if ($null -ne $p) { $p.Dispose() } }
}
