$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'FixtureVmLogEvidence.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-log-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$script:checks=0
function Check($Value,[string]$Label){$script:checks++;if(-not $Value){throw $Label}}
function Case([string]$Name) {
    $folder=Join-Path $root $Name;New-Item -ItemType Directory $folder | Out-Null
    $out=Join-Path $folder 'out';New-Item -ItemType Directory $out | Out-Null
    $binding=New-FixtureVmLogBinding (Join-Path $folder 'portable') 'pvbox_manager_gui_fixture' $root
    $binding.uuid='12345678-1234-1234-1234-123456789abc'
    $vm=Get-FixtureVmDirectory $binding;New-Item -ItemType Directory (Join-Path $vm 'Logs') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $vm 'pvbox_manager_gui_fixture.vbox'),('<VirtualBox><Machine uuid="{'+$binding.uuid+'}"/></VirtualBox>'))
    return @{binding=$binding;vm=$vm;out=$out}
}
try {
    foreach($size in @(0,17,131072,131073,400000)){
        $c=Case ('size-'+$size);$bytes=New-Object byte[] $size
        for($i=0;$i -lt $size;$i++){$bytes[$i]=[byte]($i%251)}
        [IO.File]::WriteAllBytes((Join-Path $c.vm 'Logs/VBox.log'),$bytes)
        $r=Export-FixtureVmLog $c.binding $c.out;$got=[IO.File]::ReadAllBytes((Join-Path $c.out 'fixture-vbox-tail.txt'))
        Check ($r.status -eq 'exported' -and $got.Length -eq [Math]::Min($size,131072)) 'Wrong tail size/status'
        for($i=0;$i -lt $got.Length;$i++){if($got[$i] -ne $bytes[$size-$got.Length+$i]){throw 'Wrong tail bytes'}}
        Check ($r.offset -eq [Math]::Max(0,$size-131072)) 'Wrong offset'
    }
    $c=Case 'missing';$r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'log_not_found' -and -not(Test-Path (Join-Path $c.out 'fixture-vbox-tail.txt'))) 'Missing log not explicit'
    $c=Case 'foreign';$c.binding.uuid='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    [IO.File]::WriteAllText((Join-Path $c.vm 'Logs/VBox.log'),'private-other-vm')
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'refused_or_read_error' -and -not(Test-Path (Join-Path $c.out 'fixture-vbox-tail.txt'))) 'Foreign UUID copied'
    $c=Case 'missing-config';Remove-Item -LiteralPath (Join-Path $c.vm 'pvbox_manager_gui_fixture.vbox')
    [IO.File]::WriteAllText((Join-Path $c.vm 'Logs/VBox.log'),'unbound')
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'config_not_found' -and -not(Test-Path (Join-Path $c.out 'fixture-vbox-tail.txt'))) 'Unbound log copied'
    $c=Case 'xml-entity'
    [IO.File]::WriteAllText((Join-Path $c.vm 'pvbox_manager_gui_fixture.vbox'),'<!DOCTYPE VirtualBox [<!ENTITY foreign SYSTEM "file:///nonexistent-secret">]><VirtualBox><Machine uuid="&foreign;"/></VirtualBox>')
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'refused_or_read_error' -and $r.failure -eq 'read_or_validation_failed') 'XML entity or raw parser error exposed'
    $c=Case 'large-config';[IO.File]::WriteAllBytes((Join-Path $c.vm 'pvbox_manager_gui_fixture.vbox'),(New-Object byte[] 1048577))
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'refused_or_read_error') 'Oversized config accepted'
    $c=Case 'foreign-name';$c.binding.name='../foreign'
    $r=Export-FixtureVmLog $c.binding $c.out;Check ($r.status -eq 'refused_or_read_error') 'Foreign path accepted'
    $c=Case 'outside';$c.binding.root=[IO.Path]::GetTempPath()
    $r=Export-FixtureVmLog $c.binding $c.out;Check ($r.status -eq 'refused_or_read_error') 'Outside root accepted'
    $c=Case 'not-created';$r=Export-FixtureVmLog $null $c.out
    Check ($r.status -eq 'not_created') 'Uncreated VM adopted'
    $refused=$false;try { $null=New-FixtureVmLogBinding $c.binding.root $c.binding.name $root } catch {$refused=$true}
    Check $refused 'Preexisting fixture adopted'
    $c=Case 'overwrite';[IO.File]::WriteAllText((Join-Path $c.vm 'Logs/VBox.log'),'new');[IO.File]::WriteAllText((Join-Path $c.out 'fixture-vbox-tail.txt'),'old')
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'refused_or_read_error' -and [IO.File]::ReadAllText((Join-Path $c.out 'fixture-vbox-tail.txt')) -eq 'old') 'Previous evidence overwritten'
    $c=Case 'reparse';$target=Join-Path $root 'foreign-log.txt';[IO.File]::WriteAllText($target,'foreign')
    New-Item -ItemType SymbolicLink -Path (Join-Path $c.vm 'Logs/VBox.log') -Target $target | Out-Null
    $r=Export-FixtureVmLog $c.binding $c.out
    Check ($r.status -eq 'refused_or_read_error' -and -not(Test-Path (Join-Path $c.out 'fixture-vbox-tail.txt'))) 'Reparse file copied'
    $c=Case 'metadata-existing';[IO.File]::WriteAllText((Join-Path $c.out 'fixture-vbox-log-evidence.json'),'old')
    $failure='';try {
        try { throw 'original-start-failure' }
        finally { try { $null=Export-FixtureVmLog $c.binding $c.out } catch { $diagnostic='export_error' } }
    } catch { $failure=$_.Exception.Message }
    Check ($failure -eq 'original-start-failure' -and $diagnostic -eq 'export_error') 'Diagnostic failure masked primary failure'
    Check ([IO.File]::ReadAllText((Join-Path $c.out 'fixture-vbox-log-evidence.json')) -eq 'old') 'Metadata overwritten'
    Write-Host ('FIXTURE_VM_LOG_EXPORT_PASS checks='+$script:checks)
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
