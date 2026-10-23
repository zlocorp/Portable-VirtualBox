# Non-admin offline package preparation acceptance; never invokes Oracle EXE/MSI.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable CI Windows required' }
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$target=Join-Path $env:RUNNER_TEMP 'Portable Oracle Setup Проверка'
New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'build/Portable-VirtualBox_x64.exe') -Destination (Join-Path $target 'Portable-VirtualBox.exe')
Copy-Item -LiteralPath (Join-Path $repo 'build/Portable-VirtualBox-Setup.exe') -Destination (Join-Path $target 'Portable-VirtualBox-Setup.exe')
$launcher=Join-Path $target 'Portable-VirtualBox.exe'
$servicesBefore=@(Get-CimInstance Win32_Service -Filter "Name LIKE 'VBox%'" -ErrorAction Stop)
if ($servicesBefore.Count) { throw 'Foreign VBox service baseline present; refuse test' }
function Execute([string]$Arguments,[int]$Expected,[string]$Label) {
    $stdout=Join-Path $env:RUNNER_TEMP ($Label+'.stdout.txt')
    $stderr=Join-Path $env:RUNNER_TEMP ($Label+'.stderr.txt')
    $p=Start-Process -FilePath $launcher -ArgumentList $Arguments -PassThru -WorkingDirectory $target -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    try {
        if (-not $p.WaitForExit(150000)) { throw "Preparation timed out: $Label" }
        if ($p.ExitCode -ne $Expected) { throw "Unexpected $Label exit $($p.ExitCode) expected $Expected; $([IO.File]::ReadAllText($stderr))" }
    } finally { $p.Dispose() }
}
Execute '--prepare-app64 "Z:\missing-installer.exe"' 2 'missing-official-file'
if (Test-Path -LiteralPath (Join-Path $target 'app64')) { throw 'Missing input created app64' }
Execute ('--prepare-app64 "'+$Installer+'"') 0 'prepare-exact-official'
$app=Join-Path $target 'app64'
$receipt=Get-Content -LiteralPath (Join-Path $app '.prepared.json') -Raw | ConvertFrom-Json
if ($receipt.file_count -ne 185 -or $receipt.total_bytes -ne 247834716 -or $receipt.status -ne 'prepared-not-installed' -or -not $receipt.validation.package_inputs_unchanged) { throw 'Prepared Oracle package receipt inconsistent' }
foreach($path in @('VirtualBox.exe','VBoxManage.exe','VirtualBoxVM.exe','VBoxSDS.exe','drivers\vboxsup\VBoxSup.sys','drivers\vboxsup\VBoxSup.inf','drivers\vboxsup\VBoxSup.cat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $app $path) -PathType Leaf)) { throw ('Absent Oracle file: '+$path) }
}
$hash=(Get-FileHash -LiteralPath (Join-Path $app 'VirtualBox.exe')).Hash
Execute ('--prepare-app64 "'+$Installer+'"') 2 'refuse-existing-app64'
if ((Get-FileHash -LiteralPath (Join-Path $app 'VirtualBox.exe')).Hash -ne $hash) { throw 'Repeat preparation modified Oracle app64' }
$servicesAfter=@(Get-CimInstance Win32_Service -Filter "Name LIKE 'VBox%'" -ErrorAction Stop)
if ($servicesAfter.Count) { throw 'File-only extraction accidentally registered services' }
if (@(Get-Process -Name VirtualBox,VirtualBoxVM,VBoxHeadless,VBoxManage -ErrorAction SilentlyContinue).Count) { throw 'File-only extraction launched Oracle' }
if (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\drivers\VBoxSup.sys')) { throw 'File-only extraction installed a driver' }
Write-Host 'PASS: frozen Python-free-from-user CLI prepared 185 signed-package Oracle files in Unicode root; repeat refusal; no MSI/VBox process/driver/service executed'
