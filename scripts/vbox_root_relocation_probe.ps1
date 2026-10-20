# CI-only relocation experiment: entire portable root, including app64, profile
# and an attached tiny VDI, from one Unicode path to another. No VM boot.
# Never run this on a normal PC; VBoxManage auto-registers VBoxSDS.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,120)][int]$TimeoutSeconds=30,
    [switch]$SimulateDriveLetterChange
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
foreach ($path in @($oldRoot,$newRoot,$evidence)) {
    if (-not ($path.TrimEnd('\')+'\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'All working paths must be beneath RUNNER_TEMP'
    }
}
if ($oldRoot -ieq $newRoot -or (Test-Path -LiteralPath $newRoot) -or
    (Test-Path -LiteralPath $evidence)) { throw 'Target root/evidence exists or overlaps source' }
if ([IO.Path]::GetPathRoot($oldRoot) -ine [IO.Path]::GetPathRoot($newRoot)) {
    throw 'This first experiment tests only same-volume root relocation'
}
$visibleOldRoot=$oldRoot
$visibleNewRoot=$newRoot
$aliasOldMounted=$false
$aliasNewMounted=$false
$subst=Join-Path $env:SystemRoot 'System32\subst.exe'
if ($SimulateDriveLetterChange) {
    if ((Test-Path -LiteralPath 'P:\') -or (Test-Path -LiteralPath 'Q:\')) {
        throw 'P: or Q: already in use: refusing drive alias experiment'
    }
    & $subst P: $oldRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to mount source drive alias P:' }
    $aliasOldMounted=$true
    $visibleOldRoot='P:\'
}
$oldApp=Join-Path $visibleOldRoot 'app64'
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
$oldHome=Join-Path $visibleOldRoot 'data\.VirtualBox'
$oldMachines=Join-Path $visibleOldRoot 'data\Machines Тест'
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
        if ($p.WaitForExit($TimeoutSeconds*1000)) { $status='EXITED';$exitCode=$p.ExitCode }
        else {
            $status='TIMEOUT'
            try { $p.Kill(); [void]$p.WaitForExit(5000) }
            catch { $errorText='Could not stop timed-out directly launched process' }
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
        if (-not $p.WaitForExit(20000)) {
            try {$p.Kill();[void]$p.WaitForExit(5000)} catch {}
            throw 'Owned VBoxSDS unregistration timed out'
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
        (Get-FileHash -LiteralPath $diskFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldDiskHash) {
        throw 'Unregister unexpectedly deleted/modified portable VM data'
    }
    Clear-Exact-VBoxSDS -Binary $oldSds -Phase 'old'
    # Move the whole portable folder, INCLUDING app64, profile and VDI.
    if ($SimulateDriveLetterChange) {
        & $subst P: /D | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot release source drive alias P:' }
        $aliasOldMounted=$false
    }
    Move-Item -LiteralPath $oldRoot -Destination $newRoot -ErrorAction Stop
    if ($SimulateDriveLetterChange) {
        & $subst Q: $newRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot mount destination drive alias Q:' }
        $visibleNewRoot='Q:\'
        $aliasNewMounted=$true
    }
    $profileMoved=$true
    if ((Test-Path -LiteralPath $oldRoot) -or -not (Test-Path -LiteralPath $newRoot)) {
        throw 'Entire root was not moved cleanly'
    }
    $script:app=Join-Path $visibleNewRoot 'app64'
    $script:cli=Join-Path $script:app 'VBoxManage.exe'
    $newHome=Join-Path $visibleNewRoot 'data\.VirtualBox'
    $newMachines=Join-Path $visibleNewRoot 'data\Machines Тест'
    $newVbox=Join-Path (Join-Path $newMachines $vm) ($vm+'.vbox')
    $newDisk=Join-Path (Join-Path $newMachines $vm) 'attached Test Диск.vdi'
    $env:VBOX_USER_HOME=$newHome
    foreach ($path in @($newVbox,$newDisk,(Join-Path $newHome 'VirtualBox.xml'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Relocated VM file missing' }
    }
    $newDiskHash=(Get-FileHash -LiteralPath $newDisk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($newDiskHash -ne $oldDiskHash) { throw 'Relocation modified VDI bytes' }
    Invoke-Bounded-CLI 'new_set_machinefolder' @('setproperty','machinefolder',$newMachines) | Out-Null
    Invoke-Bounded-CLI 'new_registervm' @('registervm',$newVbox) | Out-Null
    Invoke-Bounded-CLI 'new_showvminfo' @('showvminfo',$vm,'--machinereadable') | Out-Null
    $relocatedUuid=Assert-Vm-Uuid 'new_showvminfo'
    Invoke-Bounded-CLI 'new_list_vms' @('list','vms') | Out-Null
    Invoke-Bounded-CLI 'new_list_hdds' @('list','hdds') | Out-Null
    Invoke-Bounded-CLI 'new_systemproperties' @('list','systemproperties') | Out-Null
    $vmListing=Get-Content -LiteralPath (Join-Path $out 'new_list_vms.stdout.txt') -Raw
    $hddListing=Get-Content -LiteralPath (Join-Path $out 'new_list_hdds.stdout.txt') -Raw
    $properties=Get-Content -LiteralPath (Join-Path $out 'new_systemproperties.stdout.txt') -Raw
    $diskAttachedNewRoot=($hddListing -match [regex]::Escape($newDisk) -and
        $hddListing -notmatch [regex]::Escape($visibleOldRoot))
    $machinefolderNewRoot=($properties -match [regex]::Escape($newMachines))
    if ($relocatedUuid -ne $originalUuid -or
        $vmListing -notmatch [regex]::Escape($originalUuid) -or
        -not $diskAttachedNewRoot -or -not $machinefolderNewRoot) {
        throw 'Re-registration did not preserve identity and new-root disk/machine paths'
    }
    Clear-Exact-VBoxSDS -Binary (Join-Path $script:app 'VBoxSDS.exe') -Phase 'new'
    $finished=$true
} catch {
    $problems+= $_.Exception.Message
} finally {
    if ($SimulateDriveLetterChange -and $finished -and $aliasNewMounted) {
        & $subst Q: /D | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $problems+= 'Cannot remove destination drive alias after verified VBoxSDS cleanup'
            $finished=$false
        } else {
            $aliasNewMounted=$false
        }
    }
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$originalEnvironment,'Process')
    $services=Get-VBox-HostState
    $report=[ordered]@{
        experiment='entire-portable-root-relocation-fixture'
        source_commit=$env:GITHUB_SHA
        guest_os_booted=$false
        vm_disks_created=1
        old_root=$oldRoot
        new_root=$newRoot
        visible_old_root=$visibleOldRoot
        visible_new_root=$visibleNewRoot
        drive_letters_changed=[bool]($SimulateDriveLetterChange -and $profileMoved -and -not $aliasOldMounted -and -not $aliasNewMounted)
        profile_moved=[bool]$profileMoved
        original_uuid=$originalUuid
        relocated_uuid=$relocatedUuid
        same_uuid=($originalUuid -ne '' -and $originalUuid -eq $relocatedUuid)
        original_disk_sha256=$oldDiskHash
        relocated_disk_sha256=$newDiskHash
        attached_disk_survived=($newDiskHash -ne '' -and $oldDiskHash -eq $newDiskHash)
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
Write-Host "Portable root relocation: moved=$profileMoved, UUID=$($report.same_uuid), VDI=$($report.attached_disk_survived), path=$diskAttachedNewRoot, service-cleanups=$($serviceCleanups.Count), succeeded=$($report.succeeded)"
if (-not $report.succeeded) { throw ('Portable root relocation failed: ' + ($problems -join ' | ')) }
