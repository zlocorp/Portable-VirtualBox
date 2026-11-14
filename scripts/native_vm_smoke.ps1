# End-to-end disposable Windows test orchestrator for the compiled native AutoIt
# VM boot path. PowerShell provisions/cleans signed kernel resources ONLY after
# exact host/driver/VM proof. The VM is booted by Portable-VirtualBox_x64.exe.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableRoot,
    [ValidateRange(120,300)][int]$RuntimeTimeoutSeconds = 240
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') {
    throw 'Only a disposable GitHub-hosted Windows runner may run this test'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\') + '\'
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
if (-not $root.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Portable root must be beneath RUNNER_TEMP'
}
$launcher=Join-Path $root 'Portable-VirtualBox_x64.exe'
$app=Join-Path $root 'app64'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $app 'VBoxManage.exe') -PathType Leaf)) {
    throw 'Missing compiled AutoIt launcher or signed Oracle files'
}
$startPath=Join-Path $env:RUNNER_TEMP 'native-vm-sup-start'
$stagePath=Join-Path $env:RUNNER_TEMP 'native-vm-sup-stage'
$receiptPath=Join-Path $env:RUNNER_TEMP 'native-vm-independent-receipt'
$cleanupPath=Join-Path $env:RUNNER_TEMP 'native-vm-cleanup'
$log=Join-Path $env:RUNNER_TEMP 'native-vm-session.stdout.txt'
$errors=Join-Path $env:RUNNER_TEMP 'native-vm-session.stderr.txt'

# First run is intentionally idempotent and only creates private user folders.
$p=Start-Process -FilePath $launcher -ArgumentList '--prepare-profile' -WorkingDirectory $root -PassThru -Wait -NoNewWindow
if ($p.ExitCode -ne 0) { throw 'Compiled launcher profile initialization failed' }
# The already audited scripts reject external VirtualBox installations and
# pin exact SHA-256 + Microsoft/Oracle signatures before installing VBoxSup.
./scripts/vbox_sup_standalone.ps1 -AppDir $app -OutputDirectory $stagePath -TimeoutSeconds 75
$stageFile=Join-Path $stagePath 'sup-standalone.json'
$stage=Get-Content -LiteralPath $stageFile -Raw | ConvertFrom-Json
if ($stage.pnputil_exit_code -ne 0 -or -not $stage.service_registered -or
    -not $stage.system_driver_matches_package) { throw 'Pinned driver installation was not confirmed' }
./scripts/vbox_sup_start_owned.ps1 -StandaloneReport $stageFile -OutputDirectory $startPath -TimeoutSeconds 30
$startedFile=Join-Path $startPath 'sup-start-results.json'
$started=Get-Content -LiteralPath $startedFile -Raw | ConvertFrom-Json
if (-not $started.driver_running -or $started.start_exit_code -ne 0) { throw 'Pinned driver not Running' }

$native=$null
try {
    $native=Start-Process -FilePath $launcher -ArgumentList '--ci-vm-session' -WorkingDirectory $root -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $errors
    if (-not $native.WaitForExit($RuntimeTimeoutSeconds*1000)) {
        try { $native.Kill(); [void]$native.WaitForExit(5000) } catch {}
        throw 'Compiled AutoIt VM test timed out; no cleanup authorized'
    }
    Write-Host ("Compiled native AutoIt exit = " + $native.ExitCode)
    if ($native.ExitCode -ne 0) { throw "Compiled AutoIt VM boot/poweroff failed ($($native.ExitCode)); no cleanup authorized" }
} finally {
    if ($null -ne $native) { $native.Dispose() }
}
Get-Content -LiteralPath $log -ErrorAction SilentlyContinue
if (-not ((Get-Content -LiteralPath $log -Raw) -match 'Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF')) {
    throw 'Compiled session did not produce verified VM start/stop marker'
}
./scripts/check_native_vm_boot.ps1 -PortableRoot $root -Transcript $log -OutputDirectory $receiptPath -TimeoutSeconds 30
$receipt=Get-Content -LiteralPath (Join-Path $receiptPath 'vm-boot-results.json') -Raw | ConvertFrom-Json
if (-not $receipt.native_boot_verified -or -not $receipt.independently_verified -or
    -not $receipt.poweroff_succeeded -or $receipt.final_vm_state -ne 'poweroff') {
    throw 'Independent host receipt did not confirm native VM poweroff'
}
./scripts/vbox_sup_cleanup.ps1 -AppDir $app -StandaloneReport $stageFile -DriverStartReport $startedFile -BootReport (Join-Path $receiptPath 'vm-boot-results.json') -OutputDirectory $cleanupPath -TimeoutSeconds 45
$clean=Get-Content -LiteralPath (Join-Path $cleanupPath 'cleanup-results.json') -Raw | ConvertFrom-Json
if (-not $clean.cleanup_verified -or @($clean.final_vbox_services).Count -ne 0) { throw 'Owned system resources not fully cleaned' }
$vmFile=Join-Path $root 'data\Machines\pvbox_compiled_native_fixture\pvbox_compiled_native_fixture.vbox'
if (-not (Test-Path -LiteralPath $vmFile -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $root 'data\.VirtualBox\VirtualBox.xml') -PathType Leaf)) {
    throw 'Native VM configuration was not preserved across cleanup'
}
Write-Host 'PASS: compiled native AutoIt booted/powered off its own VM, independent receipt and signed exact-owned cleanup completed'
