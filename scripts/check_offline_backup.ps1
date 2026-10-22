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
function Invoke-Backup([string]$cmd,[int]$expected) {
  $p=Start-Process -FilePath $exe -ArgumentList ($cmd+' "'+$dest+'"') -PassThru -Wait -NoNewWindow
  if ($p.ExitCode -ne $expected) { throw "Backup command $cmd returned $($p.ExitCode), wanted $expected" }
}
Invoke-Backup '--backup-data' 0
if (-not (Test-Path (Join-Path $dest 'data\Machines\Переносимая ВМ\Snapshots\Snapshot 1.vdi') -PathType Leaf)) { throw 'Missing copied VM byte fixture' }
if (Test-Path -LiteralPath ($dest+'.pending')) { throw 'Successful copy left stale staging' }
Invoke-Backup '--verify-backup' 0
Invoke-Backup '--backup-data' 2
$backup=Join-Path $dest 'data\Machines\Переносимая ВМ\Snapshots\Snapshot 1.vdi'
[IO.File]::WriteAllText($backup,'corrupted')
Invoke-Backup '--verify-backup' 3
if ((Get-Content -LiteralPath (Join-Path $profile 'Snapshot 1.vdi') -AsByteStream).Count -ne 256) { throw 'Source fixture was modified' }
Write-Host 'PASS: compiled ordinary UI data-backup engine copied Unicode VM tree, verified SHA-256 and refused overwrite/corruption without requiring Oracle or elevation'
