# Ordinary user's compiled launcher: plan a moved VM, SHA-256-backup, but
# NEVER invoke Oracle, install a driver, rewrite registry or delete media.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable Windows CI required'
}
$exe=(Resolve-Path -LiteralPath $Launcher).Path
$parent=Join-Path $env:RUNNER_TEMP ('rebind plan Тест '+[guid]::NewGuid().ToString('N'))
$root=Join-Path $parent 'Перенесено'
$old=Join-Path $parent 'Старая папка'
$backup=Join-Path $parent 'Новая копия'
$vmFolder=Join-Path $root 'data\Machines\Имя ВМ'
$registry=Join-Path $root 'data\.VirtualBox\VirtualBox.xml'
$config=Join-Path $vmFolder 'Имя ВМ.vbox'
$snapshot=Join-Path $vmFolder 'Snapshots\snap.vdi'
$uuid='{12345678-2222-3333-4444-abcdef123456}'
$oldSource=Join-Path $old 'data\Machines\Имя ВМ\Имя ВМ.vbox'
New-Item -ItemType Directory -Path (Split-Path $snapshot -Parent) -Force -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path (Split-Path $registry -Parent) -Force -ErrorAction Stop | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $root 'Portable-VirtualBox.exe')
$launcher=Join-Path $root 'Portable-VirtualBox.exe'
[IO.File]::WriteAllBytes((Join-Path $vmFolder 'disk.vdi'),[Text.Encoding]::ASCII.GetBytes('MAIN-VIRTUAL-DISK'))
[IO.File]::WriteAllBytes($snapshot,[Text.Encoding]::ASCII.GetBytes('SNAPSHOT-DIFFERENCING-DISK'))
$xmlHead='<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Имя ВМ" uuid="'+$uuid+'"><MediaRegistry><HardDisks>'
$xmlTail='</HardDisks></MediaRegistry><Snapshots><Snapshot name="Снимок"/></Snapshots></Machine></VirtualBox>'
$media='<HardDisk location="disk.vdi"/><HardDisk location="Snapshots/snap.vdi"/>'
$regHead='<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry>'
$regTail='</MachineRegistry></Global></VirtualBox>'
$entry='<MachineEntry uuid="'+$uuid+'" src="'+$oldSource+'"/>'
$utf8=[Text.UTF8Encoding]::new($false)

[IO.File]::WriteAllText($config,$xmlHead+$media+$xmlTail,$utf8)
[IO.File]::WriteAllText($registry,$regHead+$entry+$regTail,$utf8)
function Invoke-Launcher([string]$CommandLine,[int]$Expect,[string]$Label) {
    # $Args is a reserved PowerShell automatic variable and would silently
    # drop the forwarded CLI command line, opening the GUI by mistake.
    if ($CommandLine -notmatch '^--[a-z]') { throw 'Missing explicit forwarded launcher command' }
    $log=Join-Path $env:RUNNER_TEMP ($Label+'-'+[guid]::NewGuid().ToString('N')+'.txt')
    $stderr=$log+'.stderr'
    Write-Host ("Compiled moved-VM CLI: "+$Label)
    $p=Start-Process -FilePath $launcher -ArgumentList $CommandLine -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $stderr -ErrorAction Stop
    try {
      $exactHandle=$p.Handle
      if ($exactHandle -eq [IntPtr]::Zero) { throw "${Label}: no exact child handle" }
      if (-not $p.WaitForExit(45000)) {
        # Never guess that an in-flight user process has exited, and never
        # terminate another process by name. The CI host is disposable.
        $tail=if(Test-Path -LiteralPath $stderr){Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue}else{''}
        $output=if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue}else{''}
        $p.Refresh()
        $title=$p.MainWindowTitle
        throw "$Label exceeded 45s without confirmed exit; window=$title; stdout=$output; stderr=$tail"
      }
      $code=$p.ExitCode
    } finally { $p.Dispose() }
    if($code -ne $Expect) {
        throw ($Label+': exit '+$code+' expected '+$Expect+': '+(Get-Content -LiteralPath $log -Raw -Encoding utf8))
    }
    return [string](Get-Content -LiteralPath $log -Raw -Encoding utf8)
}
$before=(Get-FileHash -LiteralPath $config).Hash
$beforeRegistry=(Get-FileHash -LiteralPath $registry).Hash
$en=Invoke-Launcher '--lang en --plan-vm-rebind' 0 'plan-en'
if($en -notmatch [regex]::Escape($uuid) -or
   $en -notmatch [regex]::Escape($oldSource) -or
   $en -notmatch [regex]::Escape($config) -or
   $en -notmatch 'Snapshots / media: 1 / 2' -or
   $en -notmatch 'Registration was NOT changed') { throw 'English candidate plan omitted exact relocation evidence' }
$ru=Invoke-Launcher '--lang ru --plan-vm-rebind' 0 'plan-ru'
if($ru -notmatch 'Перенес' -or $ru -notmatch 'Регистрация не изменена') { throw 'Russian relocated VM plan missing' }
$answer=Invoke-Launcher ('--lang en --prepare-vm-rebind "'+$backup+'"') 0 'backup'
if($answer -notmatch 'SHA-256 verified backup' -or
   -not (Test-Path -LiteralPath (Join-Path $backup 'SHA256SUMS.txt') -PathType Leaf) -or
   -not (Test-Path -LiteralPath (Join-Path $backup 'data\Machines\Имя ВМ\Snapshots\snap.vdi') -PathType Leaf)) {
    throw 'User-visible backup was not fully published'
}
$null=Invoke-Launcher ('--verify-backup "'+$backup+'"') 0 'independent-backup-verification'
if((Get-FileHash -LiteralPath $config).Hash -ne $before -or
   (Get-FileHash -LiteralPath $registry).Hash -ne $beforeRegistry) {
    throw 'Planner or backup altered registered VM'
}
$null=Invoke-Launcher ('--prepare-vm-rebind "'+$backup+'"') 2 'non-overwriting-repeat'
$local='<MachineEntry uuid="'+$uuid+'" src="..\Machines\Имя ВМ\Имя ВМ.vbox"/>'
[IO.File]::WriteAllText($registry,$regHead+$local+$regTail,$utf8)
$none=Invoke-Launcher '--lang en --plan-vm-rebind' 2 'local-no-repair'
if($none -notmatch 'No relocated VM registration') { throw 'An already-local registration was marked stale' }
$wrongLocal=$local.Replace($uuid,'{ffffffff-2222-3333-4444-abcdef123456}')
[IO.File]::WriteAllText($registry,$regHead+$wrongLocal+$regTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-vm-rebind' 3 'wrong-local-uuid-blocked'
[IO.File]::WriteAllText($registry,$regHead+$local+$regTail,$utf8)
$extraPath=Join-Path $root 'data\Machines\Extra\Extra.vbox'
New-Item -ItemType Directory -Path (Split-Path $extraPath -Parent) -ErrorAction Stop | Out-Null
[IO.File]::WriteAllText((Join-Path (Split-Path $extraPath -Parent) 'disk.vdi'),'EXTRA-DISK',$utf8)
$extraXml='<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Extra" uuid="{99999999-2222-3333-4444-abcdef123456}"><MediaRegistry><HardDisk location="disk.vdi"/></MediaRegistry></Machine></VirtualBox>'
[IO.File]::WriteAllText($extraPath,$extraXml,$utf8)
$null=Invoke-Launcher '--lang en --plan-vm-rebind' 3 'extra-unregistered-vm-blocked'
Remove-Item -LiteralPath (Split-Path $extraPath -Parent) -Recurse -Force
$none=Invoke-Launcher '--lang en --plan-vm-rebind' 2 'local-restored-after-adversarial-inputs'
if($none -notmatch 'No relocated VM registration') { throw 'Correct local registration not restored' }
[IO.File]::WriteAllText($registry,$regHead+$entry+$regTail,$utf8)
[IO.File]::WriteAllText($config,$xmlHead+$media+'<HardDisk location="X:\foreign\private.vdi"/>'+$xmlTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-vm-rebind' 3 'foreign-media-rejected'
[IO.File]::WriteAllText($config,$xmlHead+$media+$xmlTail,$utf8)
[IO.File]::WriteAllText($registry,'<!DOCTYPE VirtualBox [<!ENTITY inject SYSTEM "file:///C:/Windows/win.ini">]>'+$regHead+$entry+$regTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-vm-rebind' 3 'xxe-rejected'
if((Test-Path -LiteralPath $old) -or @(Get-Process -Name VirtualBox,VirtualBoxVM,VBoxManage -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Planner touched the former folder or started Oracle'
}
Write-Host 'PASS: compiled RU/EN relocated VM plan, exact UUID, snapshot chain, external/XXE refusal, SHA256 backup, no Oracle mutation'

# Two-VM relocation discovery is informational only. Construct a second
# genuine local .vbox and snapshot chain with a stale absolute registration.
[IO.File]::WriteAllText($registry,$regHead+$entry+$regTail,$utf8)
$secondId='{99999999-2222-3333-4444-555555555555}'
$secondFolder=Join-Path $root 'data\Machines\Вторая ВМ'
$secondConfig=Join-Path $secondFolder 'Вторая ВМ.vbox'
$secondOldSource=Join-Path $old 'data\Machines\Вторая ВМ\Вторая ВМ.vbox'
New-Item -ItemType Directory -Path (Join-Path $secondFolder 'Snapshots') -ErrorAction Stop | Out-Null
[IO.File]::WriteAllBytes((Join-Path $secondFolder 'disk.vdi'),[Text.Encoding]::ASCII.GetBytes('SECOND-DISK'))
[IO.File]::WriteAllBytes((Join-Path $secondFolder 'Snapshots\snap.vdi'),[Text.Encoding]::ASCII.GetBytes('SECOND-SNAP'))
$secondBody=($xmlHead+$media+$xmlTail).Replace($uuid,$secondId).Replace('Имя ВМ','Вторая ВМ')
[IO.File]::WriteAllText($secondConfig,$secondBody,$utf8)
$secondEntry='<MachineEntry uuid="'+$secondId+'" src="'+$secondOldSource+'"/>'
$twoEntries=$regHead+$entry+$secondEntry+$regTail
[IO.File]::WriteAllText($registry,$twoEntries,$utf8)
$report=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 0 'batch-plan-two-vms'
if(-not $report.Contains('READ-ONLY') -or -not $report.Contains($secondId) -or
   -not $report.Contains($uuid) -or -not $report.Contains($secondConfig) -or
   -not $report.Contains('Batch changes and cleanup remain disabled')) {
  throw 'Two-VM discovery omitted explicit UUID/path or read-only warning'
}
$reportRu=Invoke-Launcher '--lang ru --plan-multi-vm-rebind' 0 'batch-plan-ru'
if(-not $reportRu.Contains('ТОЛЬКО ЧТЕНИЕ') -or -not $reportRu.Contains('Вторая ВМ')) { throw 'Russian batch discovery missing' }
$null=Invoke-Launcher ('--lang en --prepare-vm-rebind "'+(Join-Path $parent 'Forbidden-Batch-Backup')+'"') 2 'batch-write-remains-disabled'
if(Test-Path -LiteralPath (Join-Path $parent 'Forbidden-Batch-Backup')) { throw 'Bulk preparation unexpectedly wrote user backup' }
$alternateOld=Join-Path $parent 'Other Old Root'
[IO.File]::WriteAllText($registry,$regHead+$entry+$secondEntry.Replace($old,$alternateOld)+$regTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 3 'batch-plan-mixed-origins'
[IO.File]::WriteAllText($registry,$regHead+$entry+$secondEntry.Replace($secondId,'{ffffffff-2222-3333-4444-555555555555}')+$regTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 3 'batch-plan-invalid-uuid'
[IO.File]::WriteAllText($registry,$twoEntries,$utf8)
Remove-Item -LiteralPath (Join-Path $secondFolder 'Snapshots\snap.vdi') -ErrorAction Stop
$null=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 3 'batch-plan-missing-media'
[IO.File]::WriteAllBytes((Join-Path $secondFolder 'Snapshots\snap.vdi'),[Text.Encoding]::ASCII.GetBytes('SECOND-SNAP'))
[IO.File]::WriteAllText($registry,$regHead+$entry+$regTail,$utf8)
$null=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 2 'batch-plan-single-refusal'
[IO.File]::WriteAllText($registry,$twoEntries,$utf8)
$report=Invoke-Launcher '--lang en --plan-multi-vm-rebind' 0 'batch-plan-restored'
if(-not $report.Contains($secondId)) { throw 'Read-only batch discovery did not recover after negative fixtures' }
if(Test-Path -LiteralPath $old) { throw 'Read-only discovery created the old path' }
Write-Host 'PASS: compiled two-VM read-only moved-root discovery, RU/EN, mixed origins, UUID mismatch, missing media and mutation refusal'
