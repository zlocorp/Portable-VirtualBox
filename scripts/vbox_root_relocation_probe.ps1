# CI-only relocation experiment: entire portable root, including app64, profile
# and an attached tiny VDI, from one Unicode path to another. No VM boot.
# Never run this on a normal PC; VBoxManage auto-registers VBoxSDS.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,120)][int]$TimeoutSeconds=30,
    [switch]$VhdDriveLetterChange,
    [string]$VhdBackingFile=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable GitHub-hosted Windows runner required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
$oldRoot=(Resolve-Path -LiteralPath $PortableRoot -ErrorAction Stop).Path
$newRoot=[IO.Path]::GetFullPath($DestinationRoot)
$evidence=[IO.Path]::GetFullPath($OutputDirectory)
if (-not ($evidence.TrimEnd('\')+'\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence directory must be beneath RUNNER_TEMP'
}
if ($VhdDriveLetterChange) {
    $backing=[IO.Path]::GetFullPath($VhdBackingFile)
    if (-not $backing.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $backing -PathType Leaf) -or
        -not $oldRoot.StartsWith('P:\',[StringComparison]::OrdinalIgnoreCase) -or
        -not $newRoot.StartsWith('Q:\',[StringComparison]::OrdinalIgnoreCase) -or
        $oldRoot.Substring(3) -ine $newRoot.Substring(3) -or
        -not (Test-Path -LiteralPath 'P:\') -or (Test-Path -LiteralPath 'Q:\')) {
        throw 'Expected the exact same folder on an owned mounted P: VHD; Q: must be unused'
    }
} else {
    foreach ($path in @($oldRoot,$newRoot)) {
        if (-not ($path.TrimEnd('\')+'\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Physical directory relocation must stay under RUNNER_TEMP'
        }
    }
    if ([IO.Path]::GetPathRoot($oldRoot) -ine [IO.Path]::GetPathRoot($newRoot)) {
        throw 'Ordinary root move must stay on the same volume'
    }
}
if ($oldRoot -ieq $newRoot -or (Test-Path -LiteralPath $newRoot) -or
    (Test-Path -LiteralPath $evidence)) { throw 'Target root/evidence exists or overlaps source' }
$oldApp=Join-Path $oldRoot 'app64'
$oldCli=Join-Path $oldApp 'VBoxManage.exe'
$oldSds=Join-Path $oldApp 'VBoxSDS.exe'
foreach ($exe in @($oldCli,$oldSds)) {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Expected Oracle executable is missing' }
    $sig=Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Oracle') {
        throw 'Expected Oracle executable signature is invalid'
    }
}
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    throw 'System VirtualBox installation present: refusing experiment'
}

function Get-VBox-HostState {
    $services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
    $processes=@(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(?:VBox|VirtualBox)' } |
        ForEach-Object { $_.Id })
    return [pscustomobject]@{services=$services; processes=$processes}
}
$baseline=Get-VBox-HostState
if (@($baseline.services).Count -ne 0 -or @($baseline.processes).Count -ne 0) {
    throw 'Existing VirtualBox services or processes: refusing experiment'
}
$out=(New-Item -ItemType Directory -Path $evidence -ErrorAction Stop).FullName
$oldHome=Join-Path $oldRoot 'data\.VirtualBox'
$oldMachines=Join-Path $oldRoot 'data\Machines Тест'
New-Item -ItemType Directory -Path $oldHome -Force | Out-Null
New-Item -ItemType Directory -Path $oldMachines -Force | Out-Null
$vm='portable_relocation_fixture'
$results=@()
$serviceCleanups=@()
$problems=@()
$originalUuid=''
$relocatedUuid=''
$oldDiskHash=''
$newDiskHash=''
$originalVboxHash=''
$snapshotName='portable-relocation-baseline'
$originalSnapshotHash=''
$relocatedSnapshotHash=''
$originalSnapshotPath=''
$relocatedSnapshotPath=''
$originalSnapshotUuid=''
$relocatedSnapshotUuid=''
$snapshotChainRestored=$false
$profileMoved=$false
$diskAttachedNewRoot=$false
$machinefolderNewRoot=$false
$finished=$false
$originalEnvironment=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$script:cli=$oldCli
$script:app=$oldApp

function Invoke-Bounded-CLI {
    param([string]$Name,[string[]]$Arguments,[switch]$AllowNonzero)
    $stdout=Join-Path $out ($Name+'.stdout.txt')
    $stderr=Join-Path $out ($Name+'.stderr.txt')
    $argv=($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','') + '"' } else { $_ } }) -join ' '
    $p=$null;$status='LAUNCH_ERROR';$exitCode=$null;$errorText=''
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try {
        $p=Start-Process -FilePath $script:cli -ArgumentList $argv -WorkingDirectory $script:app -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Exact VBoxManage child handle unavailable' }
        if ($p.WaitForExit($TimeoutSeconds*1000)) { $status='EXITED';$exitCode=$p.ExitCode }
        else {
            # VBoxManage may be changing the media/registration graph. Never
            # detach or kill the exact child while that mutation is in flight.
            $status='TIMEOUT'
            $p.WaitForExit()
            $exitCode=$p.ExitCode
            $errorText='VBoxManage completed after deadline; preserve state and fail closed'
        }
    } catch { $errorText=$_.Exception.Message }
    finally { $clock.Stop(); if ($null -ne $p) { $p.Dispose() } }
    $record=[pscustomobject]@{name=$Name;status=$status;exit_code=$exitCode;ms=$clock.ElapsedMilliseconds;error=$errorText;stdout_file=(Split-Path -Leaf $stdout);stderr_file=(Split-Path -Leaf $stderr)}
    $script:results+= $record
    Write-Host "$Name : $status/$exitCode"
    if (-not $AllowNonzero -and ($status -ne 'EXITED' -or $exitCode -ne 0)) {
        throw "VBoxManage command failed: $Name : $status / $exitCode ($errorText)"
    }
    return $record
}
function Assert-Vm-Uuid([string]$Log) {
    $text=Get-Content -LiteralPath (Join-Path $out ($Log+'.stdout.txt')) -Raw -ErrorAction Stop
    if ($text -notmatch '(?m)^UUID="([0-9a-fA-F-]{36})"\r?$') {
        throw "Cannot obtain registered VM UUID from $Log"
    }
    $foundUuid=$Matches[1].ToLowerInvariant()
    if ($text -notmatch '(?m)^VMState="poweroff"\r?$') {
        throw "VM is not powered off in $Log"
    }
    return $foundUuid
}
function Clear-Exact-VBoxSDS([string]$Binary,[string]$Phase) {
    $state=Get-VBox-HostState
    if (@($state.services).Count -ne 1 -or $state.services[0] -ne 'VBoxSDS') {
        throw 'Unexpected service list during owner-only VBoxSDS cleanup'
    }
    $key='HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
    $info=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    $servicePath=([string]$info.ImagePath).Trim().Trim('"')
    if ($servicePath -ine $Binary -or [int]$info.Start -ne 3 -or [int]$info.Type -ne 16 -or
        [string]$info.ObjectName -ne 'LocalSystem') {
        throw 'VBoxSDS registration does not match the just-launched signed Oracle binary'
    }
    # Do not terminate a shared process or force-stop the service.
    for ($i=0;$i -lt 60;$i++) {
        $svc=Get-Service -Name VBoxSDS -ErrorAction Stop
        $state=Get-VBox-HostState
        if ($svc.Status -eq 'Stopped' -and @($state.processes).Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    if ((Get-Service -Name VBoxSDS).Status -ne 'Stopped' -or
        @((Get-VBox-HostState).processes).Count -ne 0) {
        throw 'VBoxSDS or client processes still active: cannot relocate root'
    }
    $current=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    if (([string]$current.ImagePath).Trim().Trim('"') -ine $Binary) {
        throw 'VBoxSDS service path changed before unregistration'
    }
    $outputName=$Phase+'-sds-unregister'
    $stdout=Join-Path $out ($outputName+'.stdout.txt')
    $stderr=Join-Path $out ($outputName+'.stderr.txt')
    $p=$null; $exitCode=$null
    try {
        $p=Start-Process -FilePath $Binary -ArgumentList '--unregservice' -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Exact VBoxSDS child handle unavailable' }
        if (-not $p.WaitForExit(20000)) {
            # Unregistering this precise signed service is an irreversible
            # system effect: retain the process through its actual exit.
            $p.WaitForExit()
            throw 'Owned VBoxSDS unregistration exceeded deadline; inspect host state'
        }
        $exitCode=$p.ExitCode
    } finally { if ($null -ne $p) { $p.Dispose() } }
    for ($i=0;$i -lt 20;$i++) {
        $state=Get-VBox-HostState
        if (@($state.services).Count -eq 0 -and @($state.processes).Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    $final=Get-VBox-HostState
    if ($exitCode -ne 0 -or @($final.services).Count -ne 0 -or @($final.processes).Count -ne 0) {
        throw 'Oracle unregistration left system resources, no root move authorized'
    }
    $script:serviceCleanups+= [pscustomobject]@{phase=$Phase;image_path=$Binary;image_matches_expected=$true;idle_before_cleanup=$true;exit_code=$exitCode;clean=$true}
    Write-Host "VBoxSDS $($Phase): clean"
}
try {
    $env:VBOX_USER_HOME=$oldHome
    Invoke-Bounded-CLI 'old_set_machinefolder' @('setproperty','machinefolder',$oldMachines) | Out-Null
    Invoke-Bounded-CLI 'old_createvm' @('createvm','--name',$vm,'--platform-architecture','x86','--register') | Out-Null
    Invoke-Bounded-CLI 'old_add_sata' @('storagectl',$vm,'--name','SATA','--add','sata','--controller','IntelAhci') | Out-Null
    $vmDirectory=Join-Path $oldMachines $vm
    $vboxFile=Join-Path $vmDirectory ($vm+'.vbox')
    $diskFile=Join-Path $vmDirectory 'attached Test Диск.vdi'
    if (-not (Test-Path -LiteralPath $vboxFile -PathType Leaf)) { throw 'Original machine definition missing' }
    Invoke-Bounded-CLI 'old_create_disk' @('createmedium','disk','--filename',$diskFile,'--size','8','--format','VDI') | Out-Null
    Invoke-Bounded-CLI 'old_attach_disk' @('storageattach',$vm,'--storagectl','SATA','--port','0','--device','0','--type','hdd','--medium',$diskFile) | Out-Null
    # Deliberately capture the *entire* powered-off snapshot media graph,
    # not just a .vbox and a base VDI. No guest or VM process may be running.
    Invoke-Bounded-CLI 'old_snapshot_take' @('snapshot',$vm,'take',$snapshotName) | Out-Null
    Invoke-Bounded-CLI 'old_snapshot_list' @('snapshot',$vm,'list','--machinereadable') | Out-Null
    $snapshotText=Get-Content -LiteralPath (Join-Path $out 'old_snapshot_list.stdout.txt') -Raw -Encoding UTF8
    if ($snapshotText -notmatch [regex]::Escape($snapshotName) -or
        $snapshotText -notmatch '(?im)^SnapshotUUID="([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})"\r?$') {
        throw 'Oracle did not list the exact named snapshot UUID'
    }
    $originalSnapshotUuid=$Matches[1].ToLowerInvariant()
    $snapshotFiles=@(Get-ChildItem -LiteralPath (Join-Path $vmDirectory 'Snapshots') -File -Filter '*.vdi' -ErrorAction Stop)
    if ($snapshotFiles.Count -ne 1 -or $snapshotFiles[0].Length -lt 4096) {
        throw 'Exactly one Oracle differencing VDI was not created'
    }
    $originalSnapshotPath=$snapshotFiles[0].FullName
    $originalSnapshotHash=(Get-FileHash -LiteralPath $originalSnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Bounded-CLI 'old_showvminfo' @('showvminfo',$vm,'--machinereadable') | Out-Null
    $originalUuid=Assert-Vm-Uuid 'old_showvminfo'
    Invoke-Bounded-CLI 'old_list_hdds' @('list','hdds') | Out-Null
    if ((Get-Content -LiteralPath (Join-Path $out 'old_list_hdds.stdout.txt') -Raw) -notmatch [regex]::Escape($diskFile)) {
        throw 'Original disk is not visible in media registry'
    }
    $oldDiskHash=(Get-FileHash -LiteralPath $diskFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $originalVboxHash=(Get-FileHash -LiteralPath $vboxFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $globalXml=Join-Path $oldHome 'VirtualBox.xml'
    if (-not (Test-Path -LiteralPath $globalXml -PathType Leaf)) { throw 'Original global XML missing' }
    $backup=Join-Path $out 'private-backup-not-for-upload'
    New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $globalXml -Destination (Join-Path $backup 'VirtualBox.xml') -ErrorAction Stop
    Copy-Item -LiteralPath $vboxFile -Destination (Join-Path $backup 'original-machine.vbox') -ErrorAction Stop
    # Supported API removes ONLY registration; no --delete or XML string replacement.
    Invoke-Bounded-CLI 'old_unregistervm' @('unregistervm',$originalUuid) | Out-Null
    Invoke-Bounded-CLI 'old_after_unregister' @('list','vms') | Out-Null
    if ((Get-Content -LiteralPath (Join-Path $out 'old_after_unregister.stdout.txt') -Raw) -match [regex]::Escape($vm)) {
        throw 'VM still registered after non-deleting unregister'
    }
    if (-not (Test-Path -LiteralPath $vboxFile -PathType Leaf) -or
        (Get-FileHash -LiteralPath $diskFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDiskHash -or
        -not (Test-Path -LiteralPath $originalSnapshotPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $originalSnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalSnapshotHash) {
        throw 'Unregister unexpectedly deleted/modified VM, base disk or snapshot media'
    }
    Clear-Exact-VBoxSDS -Binary $oldSds -Phase 'old'
    # Move the whole portable folder, INCLUDING app64, profile and VDI.
    if ($VhdDriveLetterChange) {
        # No user-session SUBST aliases: VBoxSDS LocalSystem must see the real
        # NTFS volume created from our isolated and known VHDX backing file.
        & (Join-Path $PSScriptRoot 'vbox_vhd_volume.ps1') -Action Reletter -BackingFile $backing
        if (-not (Test-Path -LiteralPath 'Q:\') -or (Test-Path -LiteralPath 'P:\')) {
            throw 'VHD letter reassignment did not complete'
        }
    } else {
        Move-Item -LiteralPath $oldRoot -Destination $newRoot -ErrorAction Stop
    }
    $profileMoved=$true
    if ((Test-Path -LiteralPath $oldRoot) -or -not (Test-Path -LiteralPath $newRoot)) {
        throw 'Entire root was not moved cleanly'
    }
    $script:app=Join-Path $newRoot 'app64'
    $script:cli=Join-Path $script:app 'VBoxManage.exe'
    $newHome=Join-Path $newRoot 'data\.VirtualBox'
    $newMachines=Join-Path $newRoot 'data\Machines Тест'
    $newVbox=Join-Path (Join-Path $newMachines $vm) ($vm+'.vbox')
    $newDisk=Join-Path (Join-Path $newMachines $vm) 'attached Test Диск.vdi'
    $relocatedSnapshotPath=Join-Path (Join-Path (Join-Path $newMachines $vm) 'Snapshots') (Split-Path -Leaf $originalSnapshotPath)
    $env:VBOX_USER_HOME=$newHome
    foreach ($path in @($newVbox,$newDisk,$relocatedSnapshotPath,(Join-Path $newHome 'VirtualBox.xml'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Relocated VM file missing' }
    }
    $newDiskHash=(Get-FileHash -LiteralPath $newDisk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($newDiskHash -ne $oldDiskHash) { throw 'Relocation modified base VDI bytes' }
    $relocatedSnapshotHash=(Get-FileHash -LiteralPath $relocatedSnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($relocatedSnapshotHash -ne $originalSnapshotHash) {
        throw 'Relocation modified differencing snapshot VDI bytes'
    }
    Invoke-Bounded-CLI 'new_set_machinefolder' @('setproperty','machinefolder',$newMachines) | Out-Null
    Invoke-Bounded-CLI 'new_registervm' @('registervm',$newVbox) | Out-Null
    Invoke-Bounded-CLI 'new_showvminfo' @('showvminfo',$vm,'--machinereadable') | Out-Null
    $relocatedUuid=Assert-Vm-Uuid 'new_showvminfo'
    Invoke-Bounded-CLI 'new_snapshot_list' @('snapshot',$vm,'list','--machinereadable') | Out-Null
    $newSnapshots=Get-Content -LiteralPath (Join-Path $out 'new_snapshot_list.stdout.txt') -Raw -Encoding UTF8
    if ($newSnapshots -notmatch [regex]::Escape($snapshotName) -or
        $newSnapshots -notmatch ('(?im)^SnapshotUUID="'+[regex]::Escape($originalSnapshotUuid)+'"\r?$')) {
        throw 'Relocated VM lost its original snapshot identity'
    }
    $relocatedSnapshotUuid=$originalSnapshotUuid
    Invoke-Bounded-CLI 'new_list_vms' @('list','vms') | Out-Null
    Invoke-Bounded-CLI 'new_list_hdds' @('list','hdds') | Out-Null
    Invoke-Bounded-CLI 'new_systemproperties' @('list','systemproperties') | Out-Null
    $vmListing=Get-Content -LiteralPath (Join-Path $out 'new_list_vms.stdout.txt') -Raw
    $hddListing=Get-Content -LiteralPath (Join-Path $out 'new_list_hdds.stdout.txt') -Raw
    $properties=Get-Content -LiteralPath (Join-Path $out 'new_systemproperties.stdout.txt') -Raw
    # Oracle's Windows VBoxManage output sometimes mixes separators inside a
    # Location: root\data\Machines\Snapshots/{uuid}.vdi. Normalize only
    # this human-readable observation for comparison; never rewrite VM XML.
    $normalizedHdds=$hddListing.Replace('/', '\')
    $diskAttachedNewRoot=($normalizedHdds -match [regex]::Escape($newDisk) -and
        $normalizedHdds -notmatch [regex]::Escape($oldRoot))
    $snapshotChainRestored=($normalizedHdds -match [regex]::Escape($relocatedSnapshotPath) -and
        $normalizedHdds -notmatch [regex]::Escape($originalSnapshotPath) -and
        $relocatedSnapshotHash -eq $originalSnapshotHash -and
        $relocatedSnapshotUuid -eq $originalSnapshotUuid)
    $machinefolderNewRoot=($properties -match [regex]::Escape($newMachines))
    if ($relocatedUuid -ne $originalUuid -or
        $vmListing -notmatch [regex]::Escape($originalUuid) -or
        -not $diskAttachedNewRoot -or -not $machinefolderNewRoot -or -not $snapshotChainRestored) {
        throw 'Re-registration did not preserve identity and new-root disk/machine paths'
    }
    Clear-Exact-VBoxSDS -Binary (Join-Path $script:app 'VBoxSDS.exe') -Phase 'new'
    $finished=$true
} catch {
    $problems+= $_.Exception.Message
} finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$originalEnvironment,'Process')
    $services=Get-VBox-HostState
    $report=[ordered]@{
        experiment='entire-portable-root-relocation-fixture'
        source_commit=$env:GITHUB_SHA
        guest_os_booted=$false
        vm_disks_created=1
        old_root=$oldRoot
        new_root=$newRoot
        visible_old_root=$oldRoot
        visible_new_root=$newRoot
        drive_letters_changed=[bool]($VhdDriveLetterChange -and $profileMoved)
        profile_moved=[bool]$profileMoved
        original_uuid=$originalUuid
        relocated_uuid=$relocatedUuid
        same_uuid=($originalUuid -ne '' -and $originalUuid -eq $relocatedUuid)
        original_disk_sha256=$oldDiskHash
        relocated_disk_sha256=$newDiskHash
        attached_disk_survived=($newDiskHash -ne '' -and $oldDiskHash -eq $newDiskHash)
        snapshot_name=$snapshotName
        original_snapshot_uuid=$originalSnapshotUuid
        relocated_snapshot_uuid=$relocatedSnapshotUuid
        same_snapshot_uuid=($originalSnapshotUuid -ne '' -and $originalSnapshotUuid -eq $relocatedSnapshotUuid)
        original_snapshot_sha256=$originalSnapshotHash
        relocated_snapshot_sha256=$relocatedSnapshotHash
        snapshot_bytes_preserved=($originalSnapshotHash -ne '' -and $originalSnapshotHash -eq $relocatedSnapshotHash)
        snapshot_path_relocated=[bool]$snapshotChainRestored
        disk_attachment_points_to_new_root=[bool]$diskAttachedNewRoot
        machinefolder_points_to_new_root=[bool]$machinefolderNewRoot
        service_cleanup=$serviceCleanups
        services_remaining=@($services.services)
        processes_remaining=@($services.processes)
        succeeded=[bool]($finished -and @($services.services).Count -eq 0 -and @($services.processes).Count -eq 0)
        problems=$problems
        commands=$results
    }
    $report | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $out 'relocation-results.json') -Encoding utf8
}
Write-Host "Portable root relocation: moved=$profileMoved, UUID=$($report.same_uuid), VDI=$($report.attached_disk_survived), snapshot=$($report.snapshot_bytes_preserved), chain=$($report.snapshot_path_relocated), service-cleanups=$($serviceCleanups.Count), succeeded=$($report.succeeded)"
if (-not $report.succeeded) { throw ('Portable root relocation failed: ' + ($problems -join ' | ')) }
