# Only initiates and independently checks the integrated compiled AutoIt flow.
# The EXE, not this wrapper, orders the driver stage/start, native VM,
# independent host inspection and exact-owned driver/SDS cleanup.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableRoot,
    [ValidateRange(300,900)][int]$RuntimeTimeoutSeconds=600
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Hosted disposable Windows CI required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
if (-not $root.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'The compiled launcher must be beneath the private runner TEMP'
}
$exe=Join-Path $root 'Portable-VirtualBox_x64.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Compiled launcher missing' }
$stdout=Join-Path $env:RUNNER_TEMP 'native-vm-session.stdout.txt'
$stderr=Join-Path $env:RUNNER_TEMP 'native-vm-session.stderr.txt'
if ((Test-Path -LiteralPath $stdout) -or (Test-Path -LiteralPath $stderr)) {
    throw 'Existing native session logs: refusing replay'
}
$p=$null
try {
    $p=Start-Process -FilePath $exe -ArgumentList '--ci-integrated-session' -WorkingDirectory $root -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
    if (-not $p.WaitForExit($RuntimeTimeoutSeconds*1000)) {
        # Indeterminate effect: no guessed teardown. The runner is discarded.
        throw 'Integrated compiled session exceeded bound; do not clean resources'
    }
    if ($p.ExitCode -ne 0) {
        Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
        throw "Integrated compiled AutoIt failed with exit $($p.ExitCode); no recovery guesses"
    }
} finally {
    if ($null -ne $p) { $p.Dispose() }
}
$log=Get-Content -LiteralPath $stdout -Raw -Encoding utf8
if ($log -notmatch 'Native integrated: CLEAN; native VM and user data preserved' -or
    $log -notmatch 'Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF') {
    throw 'Compiled executable did not report a verified complete native session'
}
$stage=Get-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'native-vm-sup-stage\sup-standalone.json') -Raw | ConvertFrom-Json
$start=Get-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'native-vm-sup-start\sup-start-results.json') -Raw | ConvertFrom-Json
$boot=Get-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'native-vm-independent-receipt\vm-boot-results.json') -Raw | ConvertFrom-Json
$clean=Get-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'native-vm-cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
if ($stage.pnputil_exit_code -ne 0 -or -not $stage.system_driver_matches_package -or
    $start.start_exit_code -ne 0 -or -not $start.driver_running -or
    -not $boot.native_boot_verified -or -not $boot.independently_verified -or
    -not $boot.poweroff_succeeded -or $boot.final_vm_state -ne 'poweroff' -or
    -not $clean.cleanup_verified -or -not $clean.driver_package_removed -or
    @($clean.final_vbox_services).Count -ne 0 -or @($clean.errors).Count -ne 0) {
    throw 'Independent host report contradicts the compiled session result'
}
if (@(Get-Process -Name VirtualBox,VirtualBoxVM,VBoxSVC,VBoxManage,VBoxSDS -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'VirtualBox processes left running'
}
if ((Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup') -or
    (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
    throw 'Owned services remain registered after integrated session'
}
$vm=Join-Path $root 'data\Machines\pvbox_compiled_native_fixture\pvbox_compiled_native_fixture.vbox'
if (-not (Test-Path -LiteralPath $vm -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $root 'data\.VirtualBox\VirtualBox.xml') -PathType Leaf)) {
    throw 'Portable VM configuration was lost'
}
Write-Host 'PASS: compiled AutoIt orchestrated signed driver install/start, native VM, independent check and owned SDS/driver teardown'
