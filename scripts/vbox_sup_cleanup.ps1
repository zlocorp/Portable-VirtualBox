# Proof-only VBoxSup teardown on an exclusive, disposable GitHub Windows runner.
# This NEVER runs on a user's PC and NEVER deletes a pre-existing VBox driver.
# Stop/release only after a verified empty VM powered off and VBoxSDS clients exited.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$StandaloneReport,
    [Parameter(Mandatory)][string]$DriverStartReport,
    [Parameter(Mandatory)][string]$BootReport,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,90)][int]$TimeoutSeconds = 45
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable GitHub-hosted Windows runner required'
}
if (-not $env:RUNNER_TEMP) { throw 'RUNNER_TEMP missing' }
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
function Under-Runner([string]$Value) {
    $full=[IO.Path]::GetFullPath($Value)
    return $full.StartsWith($runner, [StringComparison]::OrdinalIgnoreCase)
}
foreach ($candidate in @($AppDir,$StandaloneReport,$DriverStartReport,$BootReport,$OutputDirectory)) {
    if (-not (Under-Runner $candidate)) { throw 'All input/output paths must be in RUNNER_TEMP' }
}
$app=(Resolve-Path -LiteralPath $AppDir).Path
$stage=(Get-Content -LiteralPath $StandaloneReport -Raw -ErrorAction Stop | ConvertFrom-Json)
$started=(Get-Content -LiteralPath $DriverStartReport -Raw -ErrorAction Stop | ConvertFrom-Json)
$boot=(Get-Content -LiteralPath $BootReport -Raw -ErrorAction Stop | ConvertFrom-Json)
$pinSys='4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be'
$pinInf='2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4'
if ($stage.experiment -ne 'standalone-VBoxSup-primitive-INF-pnputil' -or
    $stage.oracle_version -ne '7.2.22' -or $stage.pnputil_status -ne 'EXITED' -or
    $stage.pnputil_exit_code -ne 0 -or -not $stage.package_verified -or
    -not $stage.system_driver_matches_package -or
    $stage.system_driver_sha256 -ne $pinSys -or
    @($stage.services_before).Count -ne 0 -or
    @($stage.services_after).Count -ne 1 -or @($stage.services_after)[0] -ne 'VBoxSup' -or
    $stage.service_type -ne 1 -or $stage.service_start -ne 1) {
    throw 'No exclusive and exact signed VBoxSup creation evidence'
}
if ($started.experiment -ne 'owned-standalone-VBoxSup-start' -or
    -not $started.driver_running -or $started.start_exit_code -ne 0) {
    throw 'No proof that our VBoxSup was started'
}
if ($boot.installation_mode -ne 'standalone-prepared-app64' -or
    -not $boot.startvm_returned_zero -or -not $boot.poweroff_succeeded -or
    $boot.final_vm_state -ne 'poweroff' -or $boot.orphaned_vm_process_count -ne 0) {
    throw 'Disposable guest process has not been positively confirmed powered off'
}
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox')) {
    throw 'Another VirtualBox installation is present'
}
$sys=Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
$packageInf=Join-Path $app 'drivers\vboxsup\VBoxSup.inf'
if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
    (Get-FileHash -LiteralPath $packageInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Driver or INF does not match the verified Oracle package'
}
$sig=Get-AuthenticodeSignature -LiteralPath $sys
if ($sig.Status -ne 'Valid') { throw 'Installed VBoxSup signature invalid' }

# PnPUtil's human-language output is NOT a stable public parsing API.
# On this exact English hosted image, accept a single tightly constrained
# Published Name: oemNN.inf, then prove its on-disk INF has the known SHA.
# If format or identity differs, refuse all driver-removal operations.
$pnputilLog=Join-Path (Split-Path $StandaloneReport -Parent) 'pnputil.stdout.txt'
if (-not (Test-Path -LiteralPath $pnputilLog -PathType Leaf)) { throw 'Missing driver installation transcript' }
$installText=Get-Content -LiteralPath $pnputilLog -Raw -ErrorAction Stop
$publishedMatches=[regex]::Matches($installText,'(?im)^\s*Published Name:\s*(oem[0-9]{1,6}\.inf)\s*$')
if ($publishedMatches.Count -ne 1) { throw 'No unambiguous published OEM INF name from this installation' }
$published=$publishedMatches[0].Groups[1].Value.ToLowerInvariant()
$installedInf=Join-Path (Join-Path $env:SystemRoot 'INF') $published
if (-not (Test-Path -LiteralPath $installedInf -PathType Leaf) -or
    (Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
    throw 'Published driver INF does not match this exact staged Oracle INF'
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output evidence directory already exists' }
$out=(New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$report=[ordered]@{
    experiment='disposable-owned-VBoxSup-stop-and-remove'
    source_commit=$env:GITHUB_SHA
    oracle_version='7.2.22'
    published_inf=$published
    original_service_baseline_empty=$true
    vm_powered_off_before_cleanup=$true
    sds_cleanup='NOT_ATTEMPTED'
    service_stop='NOT_ATTEMPTED'
    driver_package_removal='NOT_ATTEMPTED'
    service_delete='NOT_ATTEMPTED'
    final_vbox_services=@()
    cleanup_verified=$false
    driver_package_removed=$false
    errors=@()
}
function Get-VBoxNames {
    return @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^VBox' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
}
function Get-VBoxProcesses {
    return @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '^(VBox|VirtualBox)' } |
        ForEach-Object { $_.Id } | Sort-Object -Unique)
}
function Run-Bounded([string]$Executable,[string]$Argv,[string]$Label) {
    $stdout=Join-Path $out ($Label+'.stdout.txt')
    $stderr=Join-Path $out ($Label+'.stderr.txt')
    $p=$null
    try {
        $p=Start-Process -FilePath $Executable -ArgumentList $Argv -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) {
            # Kill only the subprocess started by this script, never by image name.
            try { $p.Kill(); [void]$p.WaitForExit(5000) } catch {}
            throw "$Label timed out"
        }
        return [int]$p.ExitCode
    } finally {
        if ($null -ne $p) { $p.Dispose() }
    }
}
try {
    $expectedSds=Join-Path $app 'VBoxSDS.exe'
    $signed=Get-AuthenticodeSignature -LiteralPath $expectedSds
    if ($signed.Status -ne 'Valid' -or $signed.SignerCertificate.Subject -notmatch 'Oracle') { throw 'Unexpected VBoxSDS publisher signature' }
    $services=@(Get-VBoxNames)
    if ($services.Count -ne 2 -or $services -notcontains 'VBoxSup' -or $services -notcontains 'VBoxSDS') {
        throw 'Unexpected registered VirtualBox services after private VM boot'
    }
    $sdsConfig=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
    $sdsImage=([string]$sdsConfig.ImagePath).Trim().Trim('"')
    if ($sdsImage -ine $expectedSds -or [int]$sdsConfig.Type -ne 16 -or
        [int]$sdsConfig.Start -ne 3 -or [string]$sdsConfig.ObjectName -ne 'LocalSystem') {
        throw 'VBoxSDS does not belong to this exact app64'
    }
    for($i=0;$i -lt 45;$i++) {
        $sds=Get-Service -Name VBoxSDS -ErrorAction Stop
        $processes=@(Get-VBoxProcesses)
        if ($sds.Status -eq 'Stopped' -and $processes.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    if ((Get-Service -Name VBoxSDS).Status -ne 'Stopped' -or
        @(Get-VBoxProcesses).Count -ne 0) { throw 'VBoxSDS or another VBox process is still active: no cleanup' }
    # Revalidate service path immediately before Oracle's supported unregister.
    $sdsConfig=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
    if (([string]$sdsConfig.ImagePath).Trim().Trim('"') -ine $expectedSds) { throw 'VBoxSDS changed during idle wait' }
    $sdsExit=Run-Bounded $expectedSds '--unregservice' 'sds-unregister'
    if ($sdsExit -ne 0 -or (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) {
        throw "Exact VBoxSDS unregistration failed: $sdsExit"
    }
    $report.sds_cleanup='CLEAN'
    $names=@(Get-VBoxNames)
    if ($names.Count -ne 1 -or $names[0] -ne 'VBoxSup' -or @(Get-VBoxProcesses).Count -ne 0) {
        throw 'Unexpected VBox resource remained after VBoxSDS cleanup'
    }
    $service=Get-Service -Name VBoxSup -ErrorAction Stop
    $reg=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
    if ($service.Status -ne 'Running' -or [int]$reg.Type -ne 1 -or
        ([string]$reg.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys') -or
        (Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys) {
        throw 'VBoxSup image/status changed since owned acquisition'
    }
    $sc=Join-Path $env:SystemRoot 'System32\sc.exe'
    $stopExit=Run-Bounded $sc 'stop VBoxSup' 'sup-stop'
    $report.service_stop="EXIT_$stopExit"
    if ($stopExit -ne 0) { throw 'VBoxSup stop failed; retain package without deletion' }
    for($i=0;$i -lt 20;$i++) {
        if ((Get-Service -Name VBoxSup -ErrorAction Stop).Status -eq 'Stopped') { break }
        Start-Sleep -Seconds 1
    }
    if ((Get-Service -Name VBoxSup -ErrorAction Stop).Status -ne 'Stopped' -or
        @(Get-VBoxProcesses).Count -ne 0) { throw 'VBoxSup not safely stopped: no package removal' }
    $names=@(Get-VBoxNames)
    if ($names.Count -ne 1 -or $names[0] -ne 'VBoxSup') { throw 'Driver state changed before removal' }
    if ((Get-FileHash -LiteralPath $sys -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinSys -or
        (Get-FileHash -LiteralPath $installedInf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinInf) {
        throw 'Unexpected driver/INF mutation before package removal'
    }
    $pnputil=Join-Path $env:SystemRoot 'System32\pnputil.exe'
    # No /force and no wildcard; Windows PnP manager owns the package teardown.
    $removeExit=Run-Bounded $pnputil "/delete-driver $published /uninstall" 'sup-package-remove'
    $report.driver_package_removal="EXIT_$removeExit"
    if ($removeExit -ne 0) { throw 'PnPUtil refused driver package deletion' }
    # PnPUtil may defer kernel-service cleanup. Observe for a bounded period
    # before deciding the package was completely removed; never force-delete.
    for($i=0;$i -lt 25;$i++) {
        $afterServices=@(Get-VBoxNames)
        if ($afterServices.Count -eq 0 -and -not (Test-Path -LiteralPath $installedInf)) { break }
        Start-Sleep -Seconds 1
    }
    $afterServices=@(Get-VBoxNames)
    $report.final_vbox_services=$afterServices
    $report.published_inf_present=(Test-Path -LiteralPath $installedInf)
    $report.system_driver_file_present=(Test-Path -LiteralPath $sys)
    $driverSvc=Get-Service -Name VBoxSup -ErrorAction SilentlyContinue
    $report.service_state_after=$(if ($null -eq $driverSvc) { 'ABSENT' } else { [string]$driverSvc.Status })
    # DriverStore cleanup and kernel service deletion are distinct operations.
    # The Oracle primitive driver can leave a STOPPED VBoxSup service entry even
    # after PnPUtil removes both the published INF and VBoxSup.sys.
    $report.driver_package_removed=(-not $report.published_inf_present -and -not $report.system_driver_file_present)
    if (-not $report.driver_package_removed) {
        throw 'Driver package or system driver remains: never manually remove its service'
    }
    if ($afterServices.Count -eq 1 -and $afterServices[0] -eq 'VBoxSup') {
        $remaining=Get-Service -Name VBoxSup -ErrorAction Stop
        $config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
        if ($remaining.Status -ne 'Stopped' -or [int]$config.Type -ne 1 -or
            ([string]$config.ImagePath -ine '\SystemRoot\System32\drivers\VBoxSup.sys') -or
            @(Get-VBoxProcesses).Count -ne 0 -or
            (Test-Path -LiteralPath $installedInf) -or (Test-Path -LiteralPath $sys)) {
            throw 'Residual VBoxSup service does not meet exact exclusive-removal conditions'
        }
        # Only on our fresh disposable host after its own exact driver package
        # was removed and only the expected stopped service key remains.
        # This is not an unscoped wildcard deletion or production routine.
        $deleteExit=Run-Bounded $sc 'delete VBoxSup' 'sup-service-delete'
        $report.service_delete="EXIT_$deleteExit"
        if ($deleteExit -ne 0) { throw 'Exact stopped VBoxSup service delete failed' }
        for($i=0;$i -lt 25;$i++) {
            if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup')) { break }
            Start-Sleep -Seconds 1
        }
    }
    $report.final_vbox_services=@(Get-VBoxNames)
    $report.cleanup_verified=($report.final_vbox_services.Count -eq 0 -and
        @(Get-VBoxProcesses).Count -eq 0 -and
        -not (Test-Path -LiteralPath $sys) -and
        -not (Test-Path -LiteralPath $installedInf))
    if (-not $report.cleanup_verified) {
        throw 'Driver package removal returned success, but system is not verified clean'
    }
} catch {
    $report.errors+= $_.Exception.Message
} finally {
    $report.final_vbox_services=@(Get-VBoxNames)
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'cleanup-results.json') -Encoding utf8
}
Write-Host "VBoxSup cleanup: SDS=$($report.sds_cleanup), stop=$($report.service_stop), PnP=$($report.driver_package_removal), removed=$($report.driver_package_removed)"
if ($report.errors.Count) { throw ($report.errors -join '; ') }
