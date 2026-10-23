# Effect adapter for the compiled Manager session experiment, NOT a production
# elevated helper. Reuse the existing signed/exact-owned CI driver operations.
# Caller and worker run on the disposable elevated GitHub Windows runner only.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Finish')][string]$Action,
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$SessionDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Disposable hosted Windows experiment required; no ordinary-PC runtime'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This research adapter requires the already elevated disposable runner; it does not implement UAC'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
function Assert-RegularPath([string]$Value, [bool]$Existing=$true) {
    $full=[IO.Path]::GetFullPath($Value)
    if (-not $full.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path outside private runner' }
    $current=$full
    while($current.Length -gt 3) {
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse path not permitted' }
        } elseif ($current -eq $full -and $Existing) { throw 'Required path is absent' }
        $current=Split-Path $current -Parent
    }
    return $full
}
$root=Assert-RegularPath $PortableRoot
$session=Assert-RegularPath $SessionDir ($Action -eq 'Finish')
$app=Assert-RegularPath (Join-Path $root 'app64')
if ($session -eq $root -or $session.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Session records must be separate from user data' }
$parentId=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
$parent=[Diagnostics.Process]::GetProcessById($parentId)
try {
    $parentPath=$parent.MainModule.FileName
    $parentStart=$parent.StartTime.ToUniversalTime().Ticks.ToString()
    # Exact CI-owned controller paths only; never authorise an arbitrary EXE.
    if ($parentPath -notin @((Join-Path $root 'Portable-VirtualBox-Session-Test.exe'),
                             (Join-Path $root 'Portable-VirtualBox.exe'))) {
        throw 'Worker not launched by one of the exact compiled session controllers'
    }
} finally { $parent.Dispose() }
function VBox-Processes { return @(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)') }
function Check-App {
    $manifest=Get-Content -LiteralPath (Join-Path $app '.prepared.json') -Raw | ConvertFrom-Json
    if ($manifest.status -ne 'prepared-not-installed' -or $manifest.file_count -ne 185 -or $manifest.total_bytes -ne 247834716 -or
        $manifest.validation.product_version -ne '7.2.22' -or
        $manifest.validation.installer_sha256 -ne 'afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f') { throw 'Not the CI-prepared pinned Oracle package' }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $manifest.files) {
        $relative=[string]$row.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|[:\x00\r\n"]' -or -not $seen.Add($relative)) { throw 'Invalid file inventory path' }
        $file=Assert-RegularPath (Join-Path $app $relative)
        if (-not $file.StartsWith($app+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Inventory escaped app64' }
        $info=Get-Item -LiteralPath $file
        if ($info.PSIsContainer -or $info.Length -ne $row.size -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $row.sha256) { throw "Changed prepared file: $relative" }
    }
    if ($seen.Count -ne 185) { throw 'Incomplete file inventory' }
    foreach($name in @('VirtualBox.exe','VBoxManage.exe','VBoxSVC.exe','VBoxSDS.exe')) {
        $file=Join-Path $app $name
        $sig=Get-AuthenticodeSignature -LiteralPath $file
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Oracle' -or
            (Get-Item -LiteralPath $file).VersionInfo.FileVersion -notmatch '^7\.2\.22(?:\.|$)') { throw "Invalid Oracle executable: $name" }
    }
}
function Run-Oracle([string]$ArgsText,[string]$Name) {
    $p=Start-Process -FilePath (Join-Path $app 'VBoxManage.exe') -ArgumentList $ArgsText -WorkingDirectory $app -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $session ($Name+'.stdout.txt')) -RedirectStandardError (Join-Path $session ($Name+'.stderr.txt'))
    try {
        if (-not $p.WaitForExit(30000)) { throw 'Oracle configuration command timed out; no forced teardown' }
        if ($p.ExitCode -ne 0) { throw "Oracle configuration failed: $($p.ExitCode)" }
    } finally { $p.Dispose() }
}
try {
    if ($Action -eq 'Prepare') {
        if (Test-Path -LiteralPath $session) { throw 'Refusing old session evidence' }
        New-Item -ItemType Directory -Path $session -ErrorAction Stop | Out-Null
        Check-App
        # Prepare and start recheck an empty system baseline and signed hashes.
        & (Join-Path $PSScriptRoot 'vbox_sup_standalone.ps1') -AppDir $app -OutputDirectory (Join-Path $session 'stage')
        & (Join-Path $PSScriptRoot 'vbox_sup_start_owned.ps1') -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -OutputDirectory (Join-Path $session 'start')
        $previous=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
        try {
            $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
            Run-Oracle ('setproperty machinefolder "'+(Join-Path $root 'data\Machines')+'"') 'machinefolder'
        } finally { [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$previous,'Process') }
        # A prepare receipt is bound to the live controller generation. It is
        # CI evidence only, never a transferable production cleanup capability.
        [ordered]@{schema=1;portable_root=$root;controller_pid=$parentId;controller_created=$parentStart;
            controller_image=$parentPath;prepared=$true;source_commit=$env:GITHUB_SHA} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding utf8
        Write-Host 'MANAGER_EFFECT_PREPARED'
    } else {
        $receipt=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw | ConvertFrom-Json
        if ($receipt.schema -ne 1 -or -not $receipt.prepared -or $receipt.portable_root -ine $root -or
            $receipt.controller_pid -ne $parentId -or $receipt.controller_created -ne $parentStart -or
            $receipt.controller_image -ine $parentPath) { throw 'Session controller identity changed; no cleanup' }
        if (@(VBox-Processes).Count -ne 0) { throw 'VirtualBox activity remains; refusing teardown' }
        Check-App
        # Dedicated session evidence, NEVER a forged VM boot/poweroff receipt.
        $proof=Join-Path $session 'quiescent-session.json'
        if (Test-Path -LiteralPath $proof) { throw 'Refusing replay of session cleanup' }
        [ordered]@{experiment='compiled-manager-quiescent-session';portable_root=$root;
            stage_report=(Join-Path $session 'stage\sup-standalone.json');
            driver_start_report=(Join-Path $session 'start\sup-start-results.json');
            controller_pid=$parentId;controller_created=$parentStart;
            no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
            ConvertTo-Json | Set-Content -LiteralPath $proof -Encoding utf8
        & (Join-Path $PSScriptRoot 'vbox_sup_cleanup.ps1') -AppDir $app -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -DriverStartReport (Join-Path $session 'start\sup-start-results.json') -QuiescentReport $proof -OutputDirectory (Join-Path $session 'cleanup')
        $clean=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or @(VBox-Processes).Count -ne 0) { throw 'Session teardown not verified' }
        Write-Host 'MANAGER_EFFECT_CLEAN'
    }
} catch {
    if (Test-Path -LiteralPath $session -PathType Container) {
        $_.Exception.Message | Set-Content -LiteralPath (Join-Path $session ('error-'+$Action+'.txt')) -Encoding utf8
    }
    Write-Error $_
    exit 1
}
exit 0
