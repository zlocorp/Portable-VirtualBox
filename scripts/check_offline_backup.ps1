# Exercise the real compiled, ordinary x64 user CLI without Oracle or elevation.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $env:RUNNER_TEMP) { throw 'Private CI destination required' }
$exe=(Resolve-Path -LiteralPath $Launcher).Path
$folder=Split-Path $exe -Parent
$profile=Join-Path $folder 'data\Machines\Переносимая ВМ\Snapshots'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path (Split-Path $profile -Parent) 'Machine.vbox'), [Text.Encoding]::UTF8.GetBytes('synthetic config / no runtime'))
[IO.File]::WriteAllBytes((Join-Path $profile 'Snapshot 1.vdi'), [byte[]](0..255))
[IO.File]::WriteAllBytes((Join-Path $profile 'empty.bin'), [byte[]]::new(0))
$dest=Join-Path $env:RUNNER_TEMP ('Offline Backup Тест '+[guid]::NewGuid().ToString('N'))
function Invoke-Backup([string]$cmd,[int]$expected,[string]$language='en',[string]$expectedText='',[string]$target=$dest) {
  $output=Join-Path $env:RUNNER_TEMP ('backup-output-'+[guid]::NewGuid().ToString('N')+'.txt')
  $p=Start-Process -FilePath $exe -ArgumentList ('--lang '+$language+' '+$cmd+' "'+$target+'"') -PassThru -Wait -NoNewWindow -RedirectStandardOutput $output
  if ($p.ExitCode -ne $expected) { throw "Backup command $cmd returned $($p.ExitCode), wanted $expected" }
  if ($expectedText) {
    $text=Get-Content -LiteralPath $output -Raw -Encoding utf8
    if ($text.Trim() -cne ($expectedText+' '+$target)) { throw "Wrong $language status for ${cmd}: $text" }
  }
}
Invoke-Backup '--backup-data' 0 'ru' 'Резервная копия создана и проверена (SHA-256).'
if (-not (Test-Path (Join-Path $dest 'data\Machines\Переносимая ВМ\Snapshots\Snapshot 1.vdi') -PathType Leaf)) { throw 'Missing copied VM byte fixture' }
if (Test-Path -LiteralPath ($dest+'.pending')) { throw 'Successful copy left stale staging' }
Invoke-Backup '--verify-backup' 0 'ru' 'Резервная копия проверена (SHA-256).'
Invoke-Backup '--verify-backup' 0 'en' 'Backup verified (SHA-256).'
$englishDest=Join-Path $env:RUNNER_TEMP ('English Backup Тест '+[guid]::NewGuid().ToString('N'))
Invoke-Backup '--backup-data' 0 'en' 'Backup created and verified (SHA-256).' $englishDest
$restored=Join-Path $env:RUNNER_TEMP ('Restored VM Тест '+[guid]::NewGuid().ToString('N'))
$p=Start-Process -FilePath $exe -ArgumentList ('--restore-backup "'+$dest+'" "'+$restored+'"') -PassThru -Wait -NoNewWindow
if ($p.ExitCode -ne 0) { throw "Restore into fresh root returned $($p.ExitCode)" }
if (-not (Test-Path (Join-Path $restored 'data\Machines\Переносимая ВМ\Snapshots\Snapshot 1.vdi') -PathType Leaf)) { throw 'Restored snapshot bytes absent' }
$p=Start-Process -FilePath $exe -ArgumentList ('--verify-backup "'+$restored+'"') -PassThru -Wait -NoNewWindow
if ($p.ExitCode -ne 0) { throw 'Restored tree did not verify' }
$p=Start-Process -FilePath $exe -ArgumentList ('--restore-backup "'+$dest+'" "'+$restored+'"') -PassThru -Wait -NoNewWindow
if ($p.ExitCode -ne 2) { throw 'Restore overwrote existing user root' }
Invoke-Backup '--backup-data' 2
$backup=Join-Path $dest 'data\Machines\Переносимая ВМ\Snapshots\Snapshot 1.vdi'
[IO.File]::WriteAllText($backup,'corrupted')
Invoke-Backup '--verify-backup' 3
if ((Get-Content -LiteralPath (Join-Path $profile 'Snapshot 1.vdi') -AsByteStream).Count -ne 256) { throw 'Source fixture was modified' }
Write-Host 'PASS: compiled ordinary UI data-backup engine copied and restored Unicode VM tree to a new root, verified SHA-256 and refused overwrite/corruption without requiring Oracle or elevation'
