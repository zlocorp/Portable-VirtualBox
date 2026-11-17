# Private payload continuation only, after verified system teardown.
# This destructive integration fixture is restricted to disposable GitHub hosts.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Disposable hosted Windows runner only'
}
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not ($root+'\').StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Untrusted test input path' }
$exe=Join-Path $root 'Portable-VirtualBox-Session-Test.exe'
$helper=Join-Path $root 'Portable-VirtualBox-Helper-Test.exe'
$store=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment'
$out=Join-Path $env:RUNNER_TEMP 'payload-cleanup-proof'
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
Add-Type -Path @((Join-Path $PSScriptRoot '../../source/privilege/TokenFacts.cs'),(Join-Path $PSScriptRoot 'MediumProcess.cs'))
$old=$null;$new=$null
$proof=[ordered]@{source_commit=$env:GITHUB_SHA;scope='github-hosted';interactive_uac_verified=$false;
    guest_os_booted=$false;completed_cases=@();original_vm_data_preserved=$false;
    cleanup_evidence_unchanged=$false;no_payload_recreation=$false;all_owned_services_removed=$false}
function Start-Controller([string]$Label) {
    $p=[MediumProcess]::Start($exe,'--lang en --separate-privileges',$root,
        (Join-Path $out ($Label+'.stdout.txt')),(Join-Path $out ($Label+'.stderr.txt')))
    [MediumProcess]::LastFacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($Label+'-token.json')) -Encoding utf8
    if ($p.WaitForExit(500)) { throw "Frontend exited before fixture: $Label" }
    return $p
}
function Close-Controller([Diagnostics.Process]$Process) {
    if (-not $Process.CloseMainWindow() -or -not $Process.WaitForExit(20000) -or $Process.ExitCode -ne 0) {
        throw 'Frontend did not accept ordinary cancellation close'
    }
}
function Helper([string]$Arguments,[int]$Expected,[string]$Label) {
    $p=Start-Process -FilePath $helper -ArgumentList $Arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
    try {
        if (-not $p.WaitForExit(150000)) { throw "Helper timeout: $Label" }
        if ($p.ExitCode -ne $Expected) { throw "$Label helper exit=$($p.ExitCode), expected=$Expected" }
    } finally { $p.Dispose() }
}
function Assert-Clean {
    if (@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop | Where-Object PSChildName -match '^VBox').Count -ne 0 -or
        @(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0 -or
        (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\drivers\VBoxSup.sys'))) {
        throw 'VirtualBox system resources not absent'
    }
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Evidence-Hashes([string]$Session) {
    $hashes=@{}
    foreach($file in Get-ChildItem -LiteralPath $Session -File -Recurse -ErrorAction Stop) {
        $relative=$file.FullName.Substring($Session.Length+1).Replace('\','/')
        if ($relative -match '^(app64|code)/' -or $relative -in @('payload-cleanup.journal','payload-removed.json')) { continue }
        $hashes[$relative]=Hash $file.FullName
    }
    return $hashes
}
function Payload-Hashes([string]$Session) {
    $hashes=@{}
    foreach($name in @('app64','code')) {
        foreach($item in @(Get-Item -LiteralPath (Join-Path $Session $name) -ErrorAction Stop)+@(Get-ChildItem -LiteralPath (Join-Path $Session $name) -Recurse -Force -ErrorAction Stop)) {
            $relative=$item.FullName.Substring($Session.Length+1)
            $hashes[$relative]=if($item.PSIsContainer){'directory'}else{Hash $item.FullName}
        }
    }
    return $hashes
}
function Assert-PayloadIntact([string]$Session,[hashtable]$Before) {
    $after=Payload-Hashes $Session
    if ($after.Count -ne $Before.Count) { throw 'Diagnostic failure changed private payload entries' }
    foreach($name in $Before.Keys) {
        if (-not $after.ContainsKey($name) -or $after[$name] -cne $Before[$name]) { throw "Diagnostic failure changed payload: $name" }
    }
}
function Assert-Evidence([string]$Session,[hashtable]$Before) {
    $after=Evidence-Hashes $Session
    if ($after.Count -ne $Before.Count) { throw 'Payload-only continuation created or removed system/worker evidence' }
    foreach($name in $Before.Keys) {
        if (-not $after.ContainsKey($name) -or $after[$name] -cne $Before[$name]) { throw "Preserved evidence changed: $name" }
    }
}
# Independently decode and authenticate framing/hash continuity, without calling
# the production journal reader. This is evidence validation, not authorization.
function Assert-Ledger([string]$Path,[bool]$Complete) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 1 -or $bytes.Length -gt 262144) { throw 'Payload ledger size invalid' }
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $lines=$utf8.GetString($bytes).Split([char]10)
    if ($lines[0] -notmatch '^PVBC1\t([1-9][0-9]*)\t([^\t]+)$' -or $lines[-1] -ne '') { throw 'Payload ledger framing invalid' }
    $steps=[int]$Matches[1]
    if ($steps -lt 193 -or $steps -gt 512) { throw 'Payload ledger does not cover genuine Oracle and embedded code' }
    $events=if($Complete){2*$steps+1}else{1}
    if ($lines.Count -ne $events+2) { throw 'Unexpected payload interruption checkpoint' }
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $previous=[BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($lines[0]+"`n"))).Replace('-','').ToLowerInvariant()
        for($i=0;$i -lt $events;$i++) {
            $kind=if($i -eq 2*$steps){'COMPLETE'}elseif($i%2 -eq 0){'BEGIN'}else{'DONE'}
            $index=[int][Math]::Floor($i/2)
            $prefix="$i`t$kind`t$index`t$previous"
            $previous=[BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($prefix))).Replace('-','').ToLowerInvariant()
            if ($lines[$i+1] -cne ($prefix+"`t"+$previous)) { throw 'Payload ledger sequence or hash mismatch' }
        }
    } finally { $sha.Dispose() }
}
function Resume([string]$Arguments,[string]$Label,[string]$Session,[hashtable]$Before) {
    # Catch transient recreation too, even if a recreated directory is removed
    # before the helper returns. Do not treat watcher overflow as successful QA.
    $watcher=New-Object IO.FileSystemWatcher($Session)
    $watcher.IncludeSubdirectories=$true
    $created='payload-created-'+[guid]::NewGuid().ToString('N')
    $failed='payload-watch-error-'+[guid]::NewGuid().ToString('N')
    $null=Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier $created
    $null=Register-ObjectEvent -InputObject $watcher -EventName Error -SourceIdentifier $failed
    try {
        $watcher.EnableRaisingEvents=$true
        Helper $Arguments 0 $Label
        Start-Sleep -Milliseconds 300
        if (@(Get-Event -SourceIdentifier $failed -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Payload recreation observation overflowed' }
        foreach($event in @(Get-Event -SourceIdentifier $created -ErrorAction SilentlyContinue)) {
            $relative=$event.SourceEventArgs.FullPath.Substring($Session.Length+1).Replace('\','/')
            if ($relative -match '^(app64|code)(/|$)') { throw 'Protected executable payload recreated during resume' }
        }
        Assert-Evidence $Session $Before
    } finally {
        $watcher.EnableRaisingEvents=$false
        foreach($id in @($created,$failed)) {
            Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier $id -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
        }
        $watcher.Dispose()
    }
}
try {
    Assert-Clean
    New-Item -ItemType Directory -Path (Join-Path $root 'data\Machines') -Force | Out-Null
    $sentinel=Join-Path $root 'data\Machines\payload-recovery-sentinel.vbox'
    [IO.File]::WriteAllText($sentinel,'Original user VM data must survive private payload continuation.')
    $original=Hash $sentinel
    $cycle=40
    $cases=@(
        @{point='AfterFirstDelete';resume='Finish'},@{point='BeforeMarker';resume='Recover'}
    )
    foreach($diagnostic in @('BeforeStdout','BeforeStderr','BeforeFacts')) {
        foreach($mode in @('Finish','Recover')) { $cases+=@{point=$diagnostic;resume=$mode} }
    }
    $cases+=@{point='BeforeFacts';resume='Recover';initial='Recover'}
    foreach($case in $cases) {
        $point=$case.point
        $label=$point+'-'+$case.resume
        $initialRecover=$case.ContainsKey('initial') -and $case.initial -eq 'Recover'
        if ($initialRecover) { $label+='-InitialRecover' }
        $beforeDiagnostics=$point -in @('BeforeStdout','BeforeStderr','BeforeFacts')
        $cycle++
        Assert-Clean
        $old=Start-Controller ('owner-'+$label)
        $oldPid=$old.Id
        Helper ('Prepare '+$oldPid+' '+$cycle) 0 ('prepare-'+$label)
        $session=Join-Path $store ('pvbox-manager-'+$oldPid+'-'+$cycle)
        if (-not (Test-Path -LiteralPath (Join-Path $session 'session.json') -PathType Leaf)) { throw 'Missing genuine prepared session' }
        $initialAction='Finish'
        $initialArguments='Finish '+$oldPid+' '+$cycle
        if ($initialRecover) {
            Close-Controller $old
            $old.Dispose();$old=$null
            if (@(Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid").Count -ne 0) { throw 'Former controller PID still present before initial Recover' }
            $new=Start-Controller ('initial-recovery-'+$label)
            $initialAction='Recover'
            $initialArguments='Recover '+$new.Id+' '+$oldPid+' '+$cycle
        }
        if ($beforeDiagnostics) { $payloadBefore=Payload-Hashes $session }
        $env:PVBOX_TEST_PAYLOAD_BREAK_AT=$point
        try { Helper $initialArguments 70 ('interrupt-'+$label) }
        finally { Remove-Item Env:\PVBOX_TEST_PAYLOAD_BREAK_AT -ErrorAction SilentlyContinue }
        Assert-Clean
        $diagnostics=@(Get-ChildItem -LiteralPath $session -File -Filter 'helper-error-*.txt' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        if ($diagnostics -notmatch [regex]::Escape('Controlled private payload interruption: '+$point)) { throw 'Helper failed before requested payload checkpoint' }
        foreach($relative in @('payload-cleanup.json','stage\sup-standalone.json','cleanup\cleanup-results.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $session $relative) -PathType Leaf)) { throw "Missing protected checkpoint: $relative" }
        }
        $cleanup=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if (-not $cleanup.cleanup_verified -or -not $cleanup.driver_package_removed) { throw 'System teardown was not verified before interruption' }
        if (Test-Path -LiteralPath (Join-Path $session 'payload-removed.json')) { throw 'Success marker published before continuation' }
        if ($beforeDiagnostics) {
            Assert-PayloadIntact $session $payloadBefore
            if (Test-Path -LiteralPath (Join-Path $session 'payload-cleanup.journal')) { throw 'Payload deletion started before diagnostic failure' }
            $suffix=switch($point){'BeforeStdout'{'.stdout.txt'} 'BeforeStderr'{'.stderr.txt'} 'BeforeFacts'{'.json'}}
            if (@(Get-ChildItem -LiteralPath $session -File -Filter ('helper-'+$initialAction+'-*'+$suffix)).Count -ne 0) { throw 'Controlled diagnostic write unexpectedly succeeded' }
        } else { Assert-Ledger (Join-Path $session 'payload-cleanup.journal') ($point -eq 'BeforeMarker') }
        if ($point -eq 'AfterFirstDelete') {
            if (Test-Path -LiteralPath (Join-Path $session 'app64\.prepared.json')) { throw 'First planned deletion did not occur' }
            if (-not (Test-Path -LiteralPath (Join-Path $session 'app64') -PathType Container)) { throw 'Unexpected full deletion at first pending item' }
        } elseif ($point -eq 'BeforeMarker') {
            foreach($name in @('app64','code')) { if (Test-Path -LiteralPath (Join-Path $session $name)) { throw 'BeforeMarker retained executable payload' } }
        }
        $before=Evidence-Hashes $session
        $before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out ($label+'-preserved-hashes.json')) -Encoding utf8
        if ($initialRecover) {
            # The recovery initiator remains alive with the same PID/generation;
            # original owner is absent. The checkpoint must preserve both bindings.
            Resume ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) ('resume-same-recovery-'+$label) $session $before
            Close-Controller $new
            $new.Dispose();$new=$null
        } elseif ($case.resume -eq 'Finish') {
            Resume ('Finish '+$oldPid+' '+$cycle) ('resume-same-'+$label) $session $before
            Close-Controller $old
            $old.Dispose();$old=$null
        } else {
            Close-Controller $old
            $old.Dispose();$old=$null
            if (@(Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid").Count -ne 0) { throw 'Former controller PID still present' }
            $new=Start-Controller ('recovery-'+$label)
            Resume ('Recover '+$new.Id+' '+$oldPid+' '+$cycle) ('resume-new-'+$label) $session $before
            Close-Controller $new
            $new.Dispose();$new=$null
        }
        Assert-Clean
        Assert-Ledger (Join-Path $session 'payload-cleanup.journal') $true
        foreach($name in @('app64','code')) { if (Test-Path -LiteralPath (Join-Path $session $name)) { throw 'Protected payload remained after continuation' } }
        $marker=Get-Content -LiteralPath (Join-Path $session 'payload-removed.json') -Raw | ConvertFrom-Json
        if ($marker.protected_payload_removed -ne $true) { throw 'Final success marker missing or false' }
        if ((Hash $sentinel) -cne $original) { throw 'Original VM sentinel altered' }
        $proof.completed_cases+= $label
    }
    $proof.original_vm_data_preserved=$true
    $proof.cleanup_evidence_unchanged=$true
    $proof.no_payload_recreation=$true
    $proof.all_owned_services_removed=$true
    Write-Host 'PASS: same-owner Finish and absent-owner Recover payload-only continuation; immutable teardown evidence; UAC NOT VERIFIED'
} catch { $proof.error=$_.Exception.Message;throw }
finally {
    Remove-Item Env:\PVBOX_TEST_PAYLOAD_BREAK_AT -ErrorAction SilentlyContinue
    $proof | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'payload-cleanup-proof.json') -Encoding utf8
    # No unverified fallback cleanup on failure. The disposable runner is discarded.
    foreach($p in @($old,$new)) { if ($null -ne $p) { $p.Dispose() } }
}
