# Integration fixture, NOT an alternative elevation path in the application.
# The already-elevated disposable test harness invokes the fixed helper directly.
# Real frontend/Manager/VBoxManage/guest tokens remain medium/non-admin. This
# proves helper effects and boundaries, not GUI ShellExecute/UAC consent.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable Windows only' }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not $root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Private runner input required' }
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out=Join-Path $env:RUNNER_TEMP 'helper-boundary-proof'
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
$store=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment'
$exe=Join-Path $root 'Portable-VirtualBox-Session-Test.exe'
$helper=Join-Path $root 'Portable-VirtualBox-Helper-Test.exe'
Add-Type -Path @((Join-Path $repo 'source/privilege/TokenFacts.cs'),(Join-Path $PSScriptRoot 'MediumProcess.cs'))
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$accessProbe=Join-Path $env:RUNNER_TEMP 'BoundaryWriteProbe.exe'
& $csc /nologo /target:exe /platform:x64 ("/out:"+$accessProbe) (Join-Path $PSScriptRoot 'ProtectedWriteProbe.cs')
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
# Only fixture input/data, never helper ProgramData files, receive user ownership.
foreach ($folder in @('data','.\data\.VirtualBox','data\Machines','logs')) {
    New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
}
& (Join-Path $PSScriptRoot 'Set-PortableFixtureOwner.ps1') -PortableRoot $root
function Start-Medium([string]$Image,[string]$Arguments,[string]$Label) {
    $p=[MediumProcess]::Start($Image,$Arguments,$root,(Join-Path $out ($Label+'.stdout.txt')),(Join-Path $out ($Label+'.stderr.txt')))
    [MediumProcess]::LastFacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($Label+'-token.json')) -Encoding utf8
    return $p
}
function Wait-Exit([Diagnostics.Process]$P,[int]$Expected,[string]$Label,[int]$Seconds=120) {
    if (-not $P.WaitForExit($Seconds*1000)) { throw "Timeout: $Label; no guessed termination or cleanup" }
    if ($P.ExitCode -ne $Expected) { throw "$Label exit=$($P.ExitCode), expected=$Expected" }
}
function Helper-Action([string]$Action,[int]$Cycle,[int]$Expected,[string]$Label) {
    $p=Start-Process -FilePath $helper -ArgumentList ($Action+' '+$front.Id+' '+$Cycle) -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
    try { Wait-Exit $p $Expected $Label 170 } finally { $p.Dispose() }
}
function Oracle([string]$Arguments,[string]$Label) {
    $previous=$env:VBOX_USER_HOME
    try {
        $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
        $p=Start-Medium (Join-Path $runtime 'VBoxManage.exe') $Arguments $Label
        try { Wait-Exit $p 0 $Label 40 } finally { $p.Dispose() }
    } finally { $env:VBOX_USER_HOME=$previous }
    return [string](Get-Content -LiteralPath (Join-Path $out ($Label+'.stdout.txt')) -Raw)
}
function Clean-System {
    if (@(Get-Process | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0 -or
        @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object PSChildName -match '^VBox').Count -ne 0 -or
        (Test-Path (Join-Path $env:WINDIR 'System32\drivers\VBoxSup.sys'))) { throw 'VBox resources remain' }
}
function Await-Idle {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while (@(Get-Process | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) {
        if ($timer.Elapsed.TotalSeconds -gt 90) { throw 'Background not idle; no process-name kills' }
        Start-Sleep -Milliseconds 250
    }
}
function Await-GuestLog([Diagnostics.Process]$Process) {
    # showvminfo acquires LockType_Shared. Do not poll it while the direct
    # frontend is still trying to acquire its VM lock (observed race).
    # Wait on this fresh fixture's log, then independently verify VMState.
    $log=Join-Path $root 'data\Machines\pvbox_helper_boundary_fixture\Logs\VBox.log'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 40) {
        if ($Process.HasExited) {
            throw ('Direct guest exited '+$Process.ExitCode+': '+(Get-Content -LiteralPath (Join-Path $out 'direct-headless.stdout.txt') -Raw)+(Get-Content -LiteralPath (Join-Path $out 'direct-headless.stderr.txt') -Raw))
        }
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            $tail=(Get-Content -LiteralPath $log -Tail 1200) -join "`n"
            if ($tail -match "Changing the VM state from .* to 'RUNNING'") { return }
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'Fresh guest log never reached RUNNING'
}
$proof=[ordered]@{source_commit=$env:GITHUB_SHA;fixture='direct-elevated-test-invoker';gui_runas_verified=$false;interactive_uac_consent_verified=$false;guest_os_booted=$false;guest_start_method='direct-VBoxHeadless-passive-log-gate';vboxmanage_headless_spawn_verified=$false;tampered_inventory_rejected=$false;protected_write_denied=$false;manager_guest_medium=$false;live_guest_cleanup_refused=$false;two_cycles_clean=$false;runtime_from_protected_copy=$true}
$front=$null;$manager=$null;$guest=$null
try {
    Clean-System
    if (Test-Path -LiteralPath $store) { throw 'Fixture requires a fresh store' }
    $front=Start-Medium $exe '--lang en --separate-privileges' 'frontend'
    # No GUI Start click: this fixture must not pretend to validate UAC delivery.
    if ($front.WaitForExit(500)) { throw 'Frontend did not remain live' }
    $payload=Join-Path $root 'app64\VBoxRT.dll';$manifest=Join-Path $root 'app64\.prepared.json'
    $original=[IO.File]::ReadAllBytes($payload);$originalManifest=[IO.File]::ReadAllBytes($manifest)
    try {
        $changed=[byte[]]$original.Clone();$changed[128]=$changed[128] -bxor 1
        [IO.File]::WriteAllBytes($payload,$changed)
        $forged=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        ($forged.files | Where-Object path -eq 'VBoxRT.dll').sha256=(Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()
        $forged | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifest -Encoding utf8
        Helper-Action Prepare 1 70 'reject-forged'
        $badSession=Join-Path $store ('pvbox-manager-'+$front.Id+'-1')
        $errors=@(Get-ChildItem -LiteralPath $badSession -File -Filter 'helper-error-*' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join '\n'
        if ($errors -notmatch 'Forged or changed Oracle inventory') { throw ('Rejection did not reach pinned-inventory check: '+$errors) }
        Clean-System
        $proof.tampered_inventory_rejected=$true
    } finally { [IO.File]::WriteAllBytes($payload,$original);[IO.File]::WriteAllBytes($manifest,$originalManifest) }
    $uuid=''
    foreach ($cycle in @(2,3)) {
        Helper-Action Prepare $cycle 0 ('prepare-'+$cycle)
        $session=Join-Path $store ('pvbox-manager-'+$front.Id+'-'+$cycle)
        $runtime=Join-Path $session 'app64'
        $sds=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
        if (([string]$sds.ImagePath).Trim().Trim('"') -ine (Join-Path $session 'app64\VBoxSDS.exe')) { throw 'SDS path is not protected' }
        $p=Start-Medium $accessProbe ('"'+$session+'"') ('deny-write-'+$cycle)
        try { Wait-Exit $p 0 'protected-write-denial' 20 } finally { $p.Dispose() }
        $proof.protected_write_denied=$true
        $null=Oracle ('setproperty machinefolder "'+(Join-Path $root 'data\Machines')+'"') ('configure-'+$cycle)
        $old=$env:VBOX_USER_HOME
        try { $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox';$manager=Start-Medium (Join-Path $runtime 'VirtualBox.exe') '' ('manager-'+$cycle) } finally { $env:VBOX_USER_HOME=$old }
        $timer=[Diagnostics.Stopwatch]::StartNew()
        do {
            $manager.Refresh()
            if ($manager.HasExited -or $timer.Elapsed.TotalSeconds -gt 30) { throw 'Real Manager window absent' }
            Start-Sleep -Milliseconds 250
        } until ($manager.MainWindowHandle -ne [IntPtr]::Zero)
        if ($cycle -eq 2) {
            $created=Oracle 'createvm --name pvbox_helper_boundary_fixture --ostype Other --register' 'create-vm'
            if ($created -notmatch '(?im)^UUID:\s*([0-9a-f-]{36})\s*$') { throw 'Missing fixture UUID' };$uuid=$Matches[1]
            $null=Oracle ('modifyvm '+$uuid+' --memory 128 --nic1 none --audio-driver none') 'configure-vm'
            # The detached-console startup is still unverified under this
            # synthetic restricted token. Use Oracle's supported direct entry
            # to test the helper/driver boundary, never label this as UAC or
            # VBoxManage startvm acceptance.
            $old=$env:VBOX_USER_HOME
            try {
                $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
                $guest=Start-Medium (Join-Path $runtime 'VBoxHeadless.exe') ('--startvm '+$uuid+' --vrde off') 'direct-headless'
            } finally { $env:VBOX_USER_HOME=$old }
            Await-GuestLog $guest
            $running=Oracle ('showvminfo '+$uuid+' --machinereadable') 'running-vm'
            if ($running -notmatch '(?m)^VMState="running"') { throw 'Independent guest state was not running' }
            $guests=@(Get-Process -Name VBoxHeadless -ErrorAction Stop)
            if ($guests.Count -lt 1) { throw 'No headless test guest' }
            foreach ($g in $guests) {
                $facts=[PortableVBox.TokenFacts]::Read($g.Id)
                if ($facts.Administrator -or $facts.Integrity -ne 8192 -or $facts.Image -ine (Join-Path $runtime 'VBoxHeadless.exe')) { throw 'Guest token/image differs' }
                $facts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ('guest-token-'+$g.Id+'.json')) -Encoding utf8
            }
            $proof.manager_guest_medium=$true
            Helper-Action Finish $cycle 70 'refuse-live-guest'
            if ((Get-Service VBoxSup).Status -ne 'Running') { throw 'Live guest lost its driver' }
            $proof.live_guest_cleanup_refused=$true
            $null=Oracle ('controlvm '+$uuid+' poweroff') 'poweroff-vm'
            Wait-Exit $guest 0 'direct guest exit' 30
            $guest.Dispose();$guest=$null
        } else {
            $again=Oracle ('showvminfo '+$uuid+' --machinereadable') 'same-uuid'
            if ($again -notmatch ('(?mi)^UUID="'+[regex]::Escape($uuid)+'"') -or $again -notmatch '(?m)^VMState="poweroff"') { throw 'UUID/state changed on repeat' }
        }
        # Do not race Oracle's deferred window geometry save with teardown.
        Start-Sleep -Milliseconds 1000
        if (-not $manager.CloseMainWindow()) { throw 'Manager did not accept ordinary close' }
        Wait-Exit $manager 0 'Manager close' 40
        $manager.Dispose();$manager=$null
        Await-Idle
        Helper-Action Finish $cycle 0 ('finish-'+$cycle)
        Clean-System
        $receipt=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if (-not $receipt.cleanup_verified -or -not $receipt.driver_package_removed -or $receipt.cleanup_basis -ne 'PrivilegedSession') { throw 'Cleanup not verified' }
        if ((Test-Path (Join-Path $session 'app64')) -or (Test-Path (Join-Path $session 'code')) -or -not (Test-Path (Join-Path $session 'payload-removed.json'))) { throw 'Protected payload not removed' }
    }
    $proof.uuid=$uuid;$proof.two_cycles_clean=$true
    if (-not $front.CloseMainWindow()) { throw 'Idle frontend could not close' }
    Wait-Exit $front 0 'frontend close' 10
    Write-Host 'PASS: direct-invoker helper boundary with actual medium Manager/guest, pinned-input refusal, protected write denial and two clean cycles; UAC NOT VERIFIED'
} catch { $proof.error=$_.Exception.Message;throw } finally {
    $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'helper-boundary-proof.json') -Encoding utf8
    if ($null -ne $front) { $front.Dispose() };if ($null -ne $manager) { $manager.Dispose() };if ($null -ne $guest) { $guest.Dispose() }
}
