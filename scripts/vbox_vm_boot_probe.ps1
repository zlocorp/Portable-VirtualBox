# Isolated VirtualBox headless boot-capability experiment.
# Installs nothing, changes no services and attaches no guest disks.
# The OFFICIAL MSI installation is performed earlier on a disposable runner.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [string]$InstallReport,
    [string]$StandaloneDriverReport,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,90)][int]$TimeoutSeconds=35
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Disposable Github-hosted runner required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
$target=[IO.Path]::GetFullPath($OutputDirectory)
if (-not $target.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'VM experiment output must stay within RUNNER_TEMP'
}
if ([bool]$InstallReport -eq [bool]$StandaloneDriverReport) {
    throw 'Exactly one verified installation or standalone-driver report is required'
}
$app=(Resolve-Path -LiteralPath $AppDir).Path
$standaloneMode = [bool]$StandaloneDriverReport
$experimentMode = 'official-installed'
if ($standaloneMode) {
    $experimentMode = 'standalone-prepared-app64'
    if (-not ($app.TrimEnd('\') + '\').StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Standalone app64 must be beneath temporary runner root'
    }
    $reportPath=(Resolve-Path -LiteralPath $StandaloneDriverReport).Path
    if (-not $reportPath.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Standalone VBoxSup provenance must come from isolated runner'
    }
    $reference=(Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop | ConvertFrom-Json)
    if ($reference.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
        $reference.pnputil_status -ne 'EXITED' -or $reference.pnputil_exit_code -ne 0 -or
        -not $reference.package_verified -or -not $reference.service_registered -or
        -not $reference.system_driver_matches_package -or
        $reference.system_driver_sha256 -ne '4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be' -or
        @($reference.services_before).Count -ne 0 -or
        @($reference.services_after).Count -ne 1 -or
        @($reference.services_after)[0] -ne 'VBoxSup' -or
        $reference.service_type -ne 1 -or $reference.service_start -ne 1) {
        throw 'Standalone driver report is not exact and unambiguous'
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') {
        throw 'Official system VirtualBox installation exists'
    }
} else {
    $reference=(Get-Content -LiteralPath $InstallReport -Raw -ErrorAction Stop | ConvertFrom-Json)
    if ($reference.status -ne 'EXITED' -or $reference.exit_code -ne 0 -or
        $reference.feature -ne 'VBoxApplication' -or
        @($reference.services_before).Count -ne 0 -or
        @($reference.services_after) -notcontains 'VBoxSup') {
        throw 'Official installation provenance/clean-host checks failed'
    }
    if ($app -ine ([string]$reference.install_directory).TrimEnd('\')) {
        throw 'Installed program path mismatches the verified installation'
    }
}
$cli=Join-Path $app 'VBoxManage.exe'
$vmBinary=Join-Path $app 'VirtualBoxVM.exe'
foreach ($path in @($cli,$vmBinary)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Missing official VirtualBox executable' }
    $sig=Get-AuthenticodeSignature -LiteralPath $path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Oracle') {
        throw 'Unexpected Oracle executable signature'
    }
}
$service=Get-Service -Name VBoxSup -ErrorAction Stop
$driver=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
$driverStatusBefore = [string]$service.Status
if ([int]$driver.Type -ne 1 -or [int]$driver.Start -ne 1 -or
    ([string]$driver.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys')) {
    throw 'VBoxSup configuration is not the expected signed Oracle kernel driver'
}
if ($standaloneMode) {
    $kernel = Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
    if ((Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        '4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be') {
        throw 'Installed standalone VBoxSup system image changed'
    }
    $existing=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' |
        Where-Object { $_.PSChildName -match '^VBox' } | ForEach-Object { $_.PSChildName })
    if ($existing.Count -ne 1 -or $existing[0] -ne 'VBoxSup') {
        throw 'Unexpected VirtualBox components before standalone boot'
    }
} elseif ($service.Status -ne 'Running') {
    throw 'Official VBoxSup kernel driver is not running'
}
if (Test-Path -LiteralPath $target) { throw 'Refusing existing VM test output directory' }
$root=(New-Item -ItemType Directory -Path $target -ErrorAction Stop).FullName
$profile=(New-Item -ItemType Directory -Path (Join-Path $root 'home Тест')).FullName
$machines=(New-Item -ItemType Directory -Path (Join-Path $root 'machines Тест')).FullName
$vm='pvbox_disposable_boot_fixture'
$results=@()
$oldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$bootReturnedZero=$false
$poweroffNeeded=$false
$poweroffSucceeded=$false
$endState='UNKNOWN'

function Invoke-LocalVBox {
    param([string]$Name,[string[]]$Arguments)
    $stdout=Join-Path $root ($Name+'.stdout.txt')
    $stderr=Join-Path $root ($Name+'.stderr.txt')
    $argv=($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"','') + '"' } else { $_ }
    }) -join ' '
    $proc=$null; $status='LAUNCH_ERROR'; $exitCode=$null; $problem=''
    $sw=[Diagnostics.Stopwatch]::StartNew()
    try {
        $proc=Start-Process -FilePath $cli -WorkingDirectory $app -ArgumentList $argv -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        if ($proc.WaitForExit($TimeoutSeconds*1000)) {
            $status='EXITED'; $exitCode=$proc.ExitCode
        } else {
            $status='TIMEOUT'
            try { $proc.Kill(); [void]$proc.WaitForExit(5000) }
            catch { $problem='Direct CLI process remained after timeout' }
        }
    } catch { $problem=$_.Exception.Message }
    finally { $sw.Stop(); if ($null -ne $proc) { $proc.Dispose() } }
    return [pscustomobject]@{name=$Name; status=$status; exit_code=$exitCode; elapsed_ms=$sw.ElapsedMilliseconds; error=$problem}
}
function Query-VmState {
    $probe=Invoke-LocalVBox -Name 'show_state' -Arguments @('showvminfo',$vm,'--machinereadable')
    $script:results+= $probe
    if ($probe.status -ne 'EXITED' -or $probe.exit_code -ne 0) { return 'UNKNOWN' }
    $content=Get-Content -LiteralPath (Join-Path $root 'show_state.stdout.txt') -Raw -ErrorAction SilentlyContinue
    if ($content -match '(?m)^VMState="([^"]+)"') { return $Matches[1] }
    return 'UNKNOWN'
}
function Require-Step {
    param([string]$Name,[string[]]$Arguments)
    if (@($Arguments).Count -lt 2) { throw "Missing VBoxManage arguments for $Name" }
    $r=Invoke-LocalVBox -Name $Name -Arguments $Arguments
    $script:results+= $r
    Write-Host "$Name : $($r.status)/$($r.exit_code)"
    if ($r.status -ne 'EXITED' -or $r.exit_code -ne 0) { throw "VM setup command failed: $Name" }
}
try {
    $env:VBOX_USER_HOME=$profile
    Require-Step -Name 'set_machine_folder' -Arguments @('setproperty','machinefolder',$machines)
    Require-Step -Name 'create_fixture' -Arguments @('createvm','--name',$vm,'--platform-architecture','x86','--register')
    Require-Step -Name 'configure_fixture' -Arguments @('modifyvm',$vm,'--memory','128','--cpus','1','--nic1','none','--boot1','none','--boot2','none','--boot3','none','--boot4','none')
    Require-Step -Name 'list_fixture' -Arguments @('list','vms')
    $registered=Get-Content -LiteralPath (Join-Path $root 'list_fixture.stdout.txt') -Raw
    if ($registered -notmatch [regex]::Escape($vm)) { throw 'Test VM not registered despite zero CLI exit codes' }
    Require-Step -Name 'inspect_fixture' -Arguments @('showvminfo',$vm,'--machinereadable')
    $info=Get-Content -LiteralPath (Join-Path $root 'inspect_fixture.stdout.txt') -Raw
    if ($info -notmatch '(?m)^memory=128\r?$') { throw 'Test VM memory was not configured' }
    if ($info -notmatch '(?m)^VMState="poweroff"\r?$') { throw 'Test VM is not powered off before boot test' }
    # This tests host virtualization capability. It does NOT boot a guest OS.
    $attempt=Invoke-LocalVBox -Name 'start_headless' -Arguments @('startvm',$vm,'--type','headless')
    $results+= $attempt
    $bootReturnedZero=($attempt.status -eq 'EXITED' -and $attempt.exit_code -eq 0)
    Write-Host "startvm: $($attempt.status)/$($attempt.exit_code)"
    $endState=Query-VmState
    if ($endState -in @('running','paused','stuck','saving','starting','stopping') -or $bootReturnedZero) {
        $poweroffNeeded=$true
        # Only the disposable VM explicitly created above. Never kill by process name.
        $stop=Invoke-LocalVBox -Name 'poweroff_fixture' -Arguments @('controlvm',$vm,'poweroff')
        $results+= $stop
        $poweroffSucceeded=($stop.status -eq 'EXITED' -and $stop.exit_code -eq 0)
        Write-Host "controlvm poweroff: $($stop.status)/$($stop.exit_code)"
        $endState=Query-VmState
    }
} finally {
    if ($null -eq $oldHome) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME=$oldHome }
}
$remaining=@(Get-Process -Name 'VirtualBoxVM' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Id })
# Only this disposable fixture's own VBoxHardening.log is collected.
# A boot error might occur before a complete log is written.
$privateHardening = Join-Path (Join-Path $machines $vm) 'Logs\VBoxHardening.log'
$hardeningPresent = Test-Path -LiteralPath $privateHardening -PathType Leaf
if ($hardeningPresent) {
    $tail = @(Get-Content -LiteralPath $privateHardening -Tail 160 -ErrorAction Stop)
    $bounded = ($tail -join [Environment]::NewLine)
    if ($bounded.Length -gt 32768) { $bounded = $bounded.Substring($bounded.Length - 32768) }
    $bounded | Set-Content -LiteralPath (Join-Path $root 'hardening-tail.txt') -Encoding utf8
}
$report=[ordered]@{
    experiment='official-VBoxSup-headless-empty-fixture'
    installation_mode=$experimentMode
    kernel_driver_state_before=$driverStatusBefore
    kernel_driver_state_after=[string](Get-Service -Name VBoxSup -ErrorAction SilentlyContinue).Status
    source_commit=$env:GITHUB_SHA
    host_os=[Environment]::OSVersion.VersionString
    kernel_driver_state=[string]$service.Status
    startvm_returned_zero=[bool]$bootReturnedZero
    poweroff_needed=[bool]$poweroffNeeded
    poweroff_succeeded=[bool]$poweroffSucceeded
    final_vm_state=$endState
    orphaned_vm_process_count=$remaining.Count
    commands=$results
    hardening_log_present=[bool]$hardeningPresent
    guest_os_booted=$false
    vm_disks_created=$false
}
$report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $root 'vm-boot-results.json') -Encoding utf8
Write-Host "VM boot capability: mode=$experimentMode; start_exit_zero=$bootReturnedZero; final_state=$endState; orphan_VM_processes=$($remaining.Count)"
if ($env:GITHUB_STEP_SUMMARY) {
    '### Disposable Windows VBoxSup boot capability' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- VBoxSup: $($service.Status); startvm code zero: $bootReturnedZero" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Final VM state: $endState; orphan VM processes: $($remaining.Count)" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    '- No guest disk, OS or user virtual machines were involved.' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
if ($remaining.Count -ne 0 -or ($poweroffNeeded -and $endState -in @('running','paused','stuck','starting'))) {
    throw 'Blank test VM remained active; disposable host must be destroyed'
}
# Nonzero startvm is a recorded capability result, not a build failure.
