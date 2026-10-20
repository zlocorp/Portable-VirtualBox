# Second-cycle blank VM boot: reuse the EXACT original portable profile/VM.
# Disposable GitHub-hosted Windows only. Does not create/delete any VM or disks.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AppDir,
  [Parameter(Mandatory)][string]$FirstBootDirectory,
  [Parameter(Mandatory)][string]$FirstCleanupReport,
  [Parameter(Mandatory)][string]$StandaloneDriverReport,
  [Parameter(Mandatory)][string]$DriverStartReport,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [ValidateRange(10,90)][int]$TimeoutSeconds=40
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable hosted Windows runner required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
foreach($path in @($AppDir,$FirstBootDirectory,$FirstCleanupReport,$StandaloneDriverReport,$DriverStartReport,$OutputDirectory)) {
    $full=[IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) { throw 'All paths must be within trusted runner temp' }
}
$firstBoot=(Resolve-Path -LiteralPath $FirstBootDirectory).Path
$firstCleanup=Get-Content -LiteralPath $FirstCleanupReport -Raw | ConvertFrom-Json
$stage=Get-Content -LiteralPath $StandaloneDriverReport -Raw | ConvertFrom-Json
$started=Get-Content -LiteralPath $DriverStartReport -Raw | ConvertFrom-Json
$firstReport=Get-Content -LiteralPath (Join-Path $firstBoot 'vm-boot-results.json') -Raw | ConvertFrom-Json
if ($firstCleanup.experiment -ne 'disposable-owned-VBoxSup-stop-and-remove' -or -not $firstCleanup.cleanup_verified -or
    @($firstCleanup.final_vbox_services).Count -ne 0 -or
    $firstReport.installation_mode -ne 'standalone-prepared-app64' -or
    -not $firstReport.startvm_returned_zero -or -not $firstReport.poweroff_succeeded -or
    $firstReport.final_vm_state -ne 'poweroff' -or $firstReport.orphaned_vm_process_count -ne 0 -or
    $stage.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
    @($stage.services_before).Count -ne 0 -or
    -not $stage.system_driver_matches_package -or
    -not $started.driver_running -or $started.start_exit_code -ne 0) {
    throw 'First cycle teardown or second-cycle exclusive driver evidence missing'
}
$services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' |
    Where-Object { $_.PSChildName -match '^VBox' } |
    ForEach-Object { $_.PSChildName })
if ($services.Count -ne 1 -or $services[0] -ne 'VBoxSup' -or
    (Get-Service -Name VBoxSup).Status -ne 'Running') {
    throw 'Unexpected system VBox state before second cycle'
}
if (Test-Path 'HKLM:\SOFTWARE\Oracle\VirtualBox') { throw 'Unexpected system-installed Oracle VirtualBox' }
$app=(Resolve-Path -LiteralPath $AppDir).Path
$cli=Join-Path $app 'VBoxManage.exe'
$signature=Get-AuthenticodeSignature -LiteralPath $cli
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Oracle') { throw 'Invalid Oracle CLI signature' }
$vboxHome=(Join-Path $firstBoot 'home Тест')
$machines=(Join-Path $firstBoot 'machines Тест')
$vmName='pvbox_disposable_boot_fixture'
$vmFile=Join-Path (Join-Path $machines $vmName) ($vmName+'.vbox')
$xml=Join-Path $vboxHome 'VirtualBox.xml'
$originalInfo=Join-Path $firstBoot 'inspect_fixture.stdout.txt'
foreach ($p in @($xml,$vmFile,$originalInfo)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'Original VM profile/configuration is missing' }
}
$infoBefore=Get-Content -LiteralPath $originalInfo -Raw
if ($infoBefore -notmatch '(?m)^UUID="([0-9a-fA-F-]{36})"\r?$') { throw 'Original VM UUID not found' }
$firstUuid=$Matches[1].ToLowerInvariant()
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Second-cycle output exists: refusing overwrite' }
$out=(New-Item -ItemType Directory -Path $OutputDirectory).FullName
$results=@()
$vmStarted=$false
$poweroffSucceeded=$false
$state='UNKNOWN'
$reopenedUuid=''
$sameIdentity=$false
$oldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
function Invoke-VBox {
    param([string]$Name,[string[]]$Arguments)
    $stdout=Join-Path $out ($Name+'.stdout.txt')
    $stderr=Join-Path $out ($Name+'.stderr.txt')
    $argsText=($Arguments | ForEach-Object { if ($_ -match '\s') { '"'+($_ -replace '"','')+'"' } else { $_ } }) -join ' '
    $p=$null
    $status='LAUNCH_ERROR';$code=$null;$err=''
    try {
        $p=Start-Process -FilePath $cli -WorkingDirectory $app -ArgumentList $argsText -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        if ($p.WaitForExit($TimeoutSeconds*1000)) { $status='EXITED';$code=$p.ExitCode }
        else {
            $status='TIMEOUT'
            try { $p.Kill(); [void]$p.WaitForExit(5000) } catch {$err='Timeout child could not be stopped'}
        }
    } catch { $err=$_.Exception.Message }
    finally { if ($null -ne $p) {$p.Dispose()} }
    $result=[pscustomobject]@{name=$Name;status=$status;exit_code=$code;error=$err}
    $script:results+= $result
    Write-Host "$Name : $status / $code"
    return $result
}
function Require([string]$Name,[string[]]$Arguments) {
    $r=Invoke-VBox $Name $Arguments
    if ($r.status -ne 'EXITED' -or $r.exit_code -ne 0) { throw "VBoxManage failed: $Name" }
}
try {
    $env:VBOX_USER_HOME=$vboxHome
    Require 'list_original_vms' @('list','vms')
    $listing=Get-Content -LiteralPath (Join-Path $out 'list_original_vms.stdout.txt') -Raw
    if ($listing -notmatch [regex]::Escape($vmName) -or $listing -notmatch [regex]::Escape($firstUuid)) {
        throw 'Original registered VM name/UUID did not survive driver teardown'
    }
    Require 'reopen_original_vm' @('showvminfo',$vmName,'--machinereadable')
    $info=Get-Content -LiteralPath (Join-Path $out 'reopen_original_vm.stdout.txt') -Raw
    if ($info -notmatch '(?m)^UUID="([0-9a-fA-F-]{36})"\r?$') { throw 'Reopened UUID is missing' }
    $reopenedUuid=$Matches[1].ToLowerInvariant()
    $sameIdentity=($reopenedUuid -eq $firstUuid)
    if (-not $sameIdentity -or $info -notmatch '(?m)^VMState="poweroff"\r?$') {
        throw 'Existing VM identity or initial powered-off state mismatch'
    }
    $start=Invoke-VBox 'start_existing_vm' @('startvm',$vmName,'--type','headless')
    $vmStarted=($start.status -eq 'EXITED' -and $start.exit_code -eq 0)
    if (-not $vmStarted) { throw 'Second-cycle blank VM failed to start' }
} finally {
    if ($vmStarted) {
        $stop=Invoke-VBox 'poweroff_existing_vm' @('controlvm',$vmName,'poweroff')
        $poweroffSucceeded=($stop.status -eq 'EXITED' -and $stop.exit_code -eq 0)
        $view=Invoke-VBox 'inspect_after_poweroff' @('showvminfo',$vmName,'--machinereadable')
        if ($view.status -eq 'EXITED' -and $view.exit_code -eq 0) {
            $last=Get-Content -LiteralPath (Join-Path $out 'inspect_after_poweroff.stdout.txt') -Raw
            if ($last -match '(?m)^VMState="([^"]+)"\r?$') {$state=$Matches[1]}
        }
    }
    if ($null -eq $oldHome) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME=$oldHome }
}
$orphans=@(Get-Process -Name VirtualBoxVM -ErrorAction SilentlyContinue)
$report=[ordered]@{
    experiment='portable-VM-second-cycle-existing-definition'
    installation_mode='standalone-prepared-app64'
    source_commit=$env:GITHUB_SHA
    first_boot=$firstBoot
    first_uuid=$firstUuid
    reopened_uuid=$reopenedUuid
    same_vm_identity=[bool]$sameIdentity
    original_vm_definition_present=(Test-Path -LiteralPath $vmFile -PathType Leaf)
    original_global_profile_present=(Test-Path -LiteralPath $xml -PathType Leaf)
    startvm_returned_zero=[bool]$vmStarted
    poweroff_succeeded=[bool]$poweroffSucceeded
    final_vm_state=$state
    orphaned_vm_process_count=$orphans.Count
    guest_os_booted=$false
    commands=$results
}
$report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $out 'vm-boot-results.json') -Encoding utf8
Write-Host "Reopened VM: same_uuid=$sameIdentity, started=$vmStarted, final=$state, orphan=$($orphans.Count)"
if (-not $sameIdentity -or -not $vmStarted -or -not $poweroffSucceeded -or $state -ne 'poweroff' -or
    $orphans.Count -gt 0 -or -not $report.original_vm_definition_present -or -not $report.original_global_profile_present) {
    throw 'Second-cycle reuse/stop acceptance failed'
}
