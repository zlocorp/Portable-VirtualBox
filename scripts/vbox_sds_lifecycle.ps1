# Disposable hosted-Windows experiment: observe VBoxSDS auto-registration and
# conditionally unregister ONLY the service created by THIS probe.
# VBoxSDS --unregservice itself has system effects, so never run this on
# a normal desktop or against any pre-existing VirtualBox installation.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(10,60)][int]$IdleSeconds=30,
    [ValidateRange(5,45)][int]$CommandSeconds=20
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Hosted disposable CI runner required for VBoxSDS registration experiment'
}
if (-not $env:RUNNER_TEMP) { throw 'Missing RUNNER_TEMP' }
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\') + '\'
$app=(Resolve-Path -LiteralPath $AppDir -ErrorAction Stop).Path
$outFull=[IO.Path]::GetFullPath($OutputDirectory)
if (-not $app.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
    -not $outFull.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Input/output must both be under RUNNER_TEMP'
}
$manager=Join-Path $app 'VBoxManage.exe'
$sdsExe=Join-Path $app 'VBoxSDS.exe'
foreach ($file in @($manager,$sdsExe)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Expected signed Oracle executable missing' }
    $sig=Get-AuthenticodeSignature -LiteralPath $file
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Oracle') {
        throw "Oracle signature invalid for $(Split-Path $file -Leaf)"
    }
}
if (Test-Path -LiteralPath $outFull) { throw 'Refusing to replace probe evidence' }
$folder=(New-Item -ItemType Directory -Path $outFull -ErrorAction Stop).FullName
$profile=(New-Item -ItemType Directory -Path (Join-Path $folder 'profile Тест')).FullName

function Read-HostState {
    $services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
    $processes=@(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(?:VBox|VirtualBox)' } |
        ForEach-Object { [pscustomobject]@{pid=$_.Id; name=$_.ProcessName} })
    $item=$null
    if ($services -contains 'VBoxSDS') {
        $data=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
        $svc=Get-Service -Name VBoxSDS -ErrorAction Stop
        $item=[ordered]@{
            image_path=[string]$data.ImagePath
            account= if ($data.PSObject.Properties['ObjectName']) {[string]$data.ObjectName} else {''}
            start=[int]$data.Start
            type=[int]$data.Type
            status=[string]$svc.Status
        }
    }
    return [pscustomobject]@{
        services=$services
        processes=$processes
        sds=$item
    }
}

function Run-OwnedProcess {
    param([string]$Path,[string[]]$Argv,[string]$Label)
    $stdout=Join-Path $folder ($Label+'.stdout.txt')
    $stderr=Join-Path $folder ($Label+'.stderr.txt')
    $p=$null; $exitCode=$null; $status='LAUNCH_ERROR'; $errorText=''
    $sw=[Diagnostics.Stopwatch]::StartNew()
    try {
        $p=Start-Process -FilePath $Path -WorkingDirectory $app -ArgumentList ($Argv -join ' ') -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        if ($p.WaitForExit($CommandSeconds*1000)) {
            $status='EXITED'; $exitCode=$p.ExitCode
        } else {
            $status='TIMEOUT'
            # Kill ONLY our directly launched child; no process-name matching.
            try { $p.Kill(); [void]$p.WaitForExit(5000) }
            catch { $errorText='Failed to stop the timed-out directly launched process' }
        }
    } catch {
        $errorText=$_.Exception.Message
    } finally {
        $sw.Stop()
        if ($null -ne $p) { $p.Dispose() }
    }
    return [pscustomobject]@{label=$Label;status=$status;exit_code=$exitCode;duration_ms=$sw.ElapsedMilliseconds;error=$errorText}
}

$initial=Read-HostState
if (@($initial.services).Count -ne 0 -or @($initial.processes).Count -ne 0 -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox')) {
    throw 'Existing VirtualBox installation/services/processes: refusing experiment'
}
$events=@()
$events+= [pscustomobject]@{phase='before';state=$initial}
$oldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$commands=@()
$cleanupAllowed=$false
$cleanupExit=$null
$cleanupStatus='NOT_ATTEMPTED'
$endStatus='UNCHECKED'
try {
    $env:VBOX_USER_HOME=$profile
    foreach ($step in @(
        @{name='version';argv=@('--version')},
        @{name='list_vms';argv=@('list','vms')},
        @{name='system_properties';argv=@('list','systemproperties')}
    )) {
        $result=Run-OwnedProcess -Path $manager -Argv $step.argv -Label $step.name
        $commands+= $result
        $events+= [pscustomobject]@{phase=('after_'+$step.name);state=(Read-HostState)}
        Write-Host "$($step.name): $($result.status)/$($result.exit_code)"
        if ($result.status -ne 'EXITED' -or $result.exit_code -ne 0) { break }
    }
} finally {
    if ($null -eq $oldHome) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME=$oldHome }
}
$afterCommands=Read-HostState
$expectedPath='"' + $sdsExe + '"'
$correctService=($null -ne $afterCommands.sds -and
    $afterCommands.sds.image_path -ceq $expectedPath -and
    $afterCommands.sds.start -eq 3 -and
    $afterCommands.sds.type -eq 16 -and
    $afterCommands.sds.account -eq 'LocalSystem')
$createdSds=($initial.services -notcontains 'VBoxSDS' -and $afterCommands.services -contains 'VBoxSDS')
$allCommandsOk=($commands.Count -eq 3 -and @($commands | Where-Object { $_.status -ne 'EXITED' -or $_.exit_code -ne 0 }).Count -eq 0)
$events+= [pscustomobject]@{phase='post_commands';state=$afterCommands}
if ($allCommandsOk -and $createdSds -and $correctService) {
    # Oracle source documents idle shutdown. Wait for all clients to exit
    # naturally. Do not stop other processes or force-stop a service.
    for ($i=0;$i -lt $IdleSeconds;$i++) {
        $current=Read-HostState
        if ($current.sds.status -eq 'Stopped' -and @($current.processes).Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    $idle=Read-HostState
    $events+= [pscustomobject]@{phase='after_idle';state=$idle}
    $cleanupAllowed=($null -ne $idle.sds -and
        $idle.sds.image_path -ceq $expectedPath -and
        $idle.sds.account -eq 'LocalSystem' -and
        $idle.sds.status -eq 'Stopped' -and
        $idle.sds.start -eq 3 -and $idle.sds.type -eq 16 -and
        @($idle.processes).Count -eq 0 -and $idle.services.Count -eq 1)
    if ($cleanupAllowed) {
        # Oracle-supported unregistration, only after proving this host had no
        # VBox installation before our command and the exact expected path.
        $unreg=Run-OwnedProcess -Path $sdsExe -Argv @('--unregservice') -Label 'unregister_owned_sds'
        $cleanupStatus=$unreg.status
        $cleanupExit=$unreg.exit_code
        $events+= [pscustomobject]@{phase='after_unregister_command';state=(Read-HostState)}
        for ($i=0;$i -lt 15;$i++) {
            $check=Read-HostState
            if (@($check.services).Count -eq 0 -and @($check.processes).Count -eq 0) { break }
            Start-Sleep -Seconds 1
        }
        $final=Read-HostState
        $events+= [pscustomobject]@{phase='after_cleanup';state=$final}
        $endStatus=if ($cleanupStatus -eq 'EXITED' -and $cleanupExit -eq 0 -and
            @($final.services).Count -eq 0 -and @($final.processes).Count -eq 0) {'CLEAN'} else {'NOT_CLEAN'}
    } else {
        $endStatus='CLEANUP_NOT_AUTHORIZED'
    }
} else {
    $endStatus='UNEXPECTED_SERVICE_OR_COMMAND_RESULT'
}
$report=[ordered]@{
    experiment='owned-VBoxSDS-auto-registration-lifecycle'
    source_commit=$env:GITHUB_SHA
    oracle_version='7.2.20'
    services_before=@($initial.services)
    commands=$commands
    observed_created_sds=[bool]$createdSds
    expected_sds_image_verified=[bool]$correctService
    cleanup_allowed=[bool]$cleanupAllowed
    cleanup_status=$cleanupStatus
    cleanup_exit_code=$cleanupExit
    final_status=$endStatus
    states=$events
    guest_vm_started=$false
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $folder 'sds-lifecycle.json') -Encoding utf8
Write-Host "VBoxSDS lifecycle: registered=$createdSds, identity_verified=$correctService, cleanup_allowed=$cleanupAllowed, result=$endStatus"
if ($env:GITHUB_STEP_SUMMARY) {
    '### VBoxSDS disposable-host lifecycle' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Registered by CLI: $createdSds; expected image: $correctService" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Cleanup outcome: $endStatus" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
if ($endStatus -ne 'CLEAN') {
    throw "VBoxSDS lifecycle did not reach verified clean state: $endStatus"
}
