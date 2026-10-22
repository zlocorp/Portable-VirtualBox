# Test the ordinary compiled user's VM inventory. Never start Oracle/driver.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $env:RUNNER_TEMP) { throw 'Private Windows test root required' }
$source=(Resolve-Path -LiteralPath $Launcher).Path
$root=Join-Path $env:RUNNER_TEMP ('VM inventory Тест '+[Guid]::NewGuid().ToString('N'))
$machine=Join-Path $root 'data\Machines\ВМ с пробелами'
New-Item -ItemType Directory -Path $machine -Force -ErrorAction Stop | Out-Null
$exe=Join-Path $root 'Portable-VirtualBox_x64.exe'
Copy-Item -LiteralPath $source -Destination $exe
function Invoke-Audit([int]$Expected,[string]$Language) {
  $stdout=Join-Path $env:RUNNER_TEMP ('inventory-'+[Guid]::NewGuid().ToString('N')+'.txt')
  $p=Start-Process -FilePath $exe -ArgumentList ('--lang '+$Language+' --audit-vms') -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdout
  if ($p.ExitCode -ne $Expected) { throw "Audit returned $($p.ExitCode), expected $Expected" }
  return [string](Get-Content -LiteralPath $stdout -Raw -Encoding utf8)
}
$xml=Join-Path $machine 'Тест.vbox'
$uuid='{11111111-2222-3333-4444-555555555555}'
$head='<VirtualBox xmlns="http://www.virtualbox.org/" version="1.20-windows"><Machine uuid="'+$uuid+'" name="ВМ с пробелами"><MediaRegistry><HardDisks>'
$tail='</HardDisks></MediaRegistry><Snapshots><Snapshot name="Снимок"/></Snapshots></Machine></VirtualBox>'
[IO.File]::WriteAllBytes((Join-Path $machine 'disk.vdi'),[byte[]](0..255))
$local='<HardDisk location="disk.vdi"/>'
[IO.File]::WriteAllText($xml,$head+$local+$tail,[Text.UTF8Encoding]::new($false))
$en=Invoke-Audit 0 'en'
if (-not $en.Contains('VMs / snapshots / media') -or -not $en.Contains('ВМ с пробелами')) { throw 'Clean fixture did not enumerate VM and snapshot' }
$ru=Invoke-Audit 0 'ru'
if (-not $ru.Contains('ВМ / снимки / носители')) { throw 'Russian output missing' }
$external='<HardDisk location="D:\OtherHost\disk.vdi"/><HardDisk location="missing.vdi"/>'
[IO.File]::WriteAllText($xml,$head+$local+$external+$tail,[Text.UTF8Encoding]::new($false))
$report=Invoke-Audit 2 'en'
if (-not $report.Contains('External/ambiguous medium path') -or -not $report.Contains('Missing local medium')) { throw 'External/missing medium not surfaced' }
$report=Invoke-Audit 2 'ru'
if (-not $report.Contains('Внешний или неоднозначный') -or -not $report.Contains('Отсутствует локальный')) { throw 'RU external/missing diagnostics absent' }
# Backup of an incomplete VM is allowed as a FILE copy, but never silently
# described as a complete VM backup. Verify real compiled CLI warning.
$backup=Join-Path $env:RUNNER_TEMP ('Incomplete VM backup '+[Guid]::NewGuid().ToString('N'))
$warning=Join-Path $env:RUNNER_TEMP ('vm-backup-warning-'+[Guid]::NewGuid().ToString('N')+'.txt')
$b=Start-Process -FilePath $exe -ArgumentList ('--lang en --backup-data "'+$backup+'"') -PassThru -Wait -NoNewWindow -RedirectStandardError $warning
if ($b.ExitCode -ne 0 -or -not (Test-Path (Join-Path $backup 'data\Machines\ВМ с пробелами\Тест.vbox'))) { throw 'Guarded copy of data unexpectedly failed' }
if (-not (Get-Content -LiteralPath $warning -Raw -Encoding utf8).Contains('NOT a complete backup')) { throw 'Backup of external-disk VM was silent' }
[IO.File]::WriteAllText($xml,'<!DOCTYPE VirtualBox [<!ENTITY bad SYSTEM "file:///C:/Windows/win.ini">]>'+$head+$local+$tail,[Text.UTF8Encoding]::new($false))
$null=Invoke-Audit 3 'en'
if (-not (Test-Path -LiteralPath (Join-Path $machine 'disk.vdi'))) { throw 'Read-only inventory mutated media' }
Write-Host 'PASS: compiled RU/EN VM catalog, snapshot count, local/external/missing disks and safe XML refusal; no VM launched'
