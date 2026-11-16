# Actual fixed failure readers on Windows, then mocked renderer/coordinator contracts.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/privileged_session_worker.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'worker parse failed'}
foreach($name in @('Get-SdsFailureServiceFacts','Get-SdsFailureRegistryFacts','Get-SdsFailureProcessFacts','ConvertTo-SdsFailureLines','Write-SdsFailureDiagnostics')){
 $defs=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
 if($defs.Count -ne 1){throw 'missing unique fixed collector function'}
 . ([scriptblock]::Create($defs[0].Extent.Text))
}
$checks=0
function Check($ok,$label){if(-not $ok){throw "FAIL failure capture: $label"};$script:checks++}
# Exercise actual fixed readers before installing boundary mocks. No service is
# installed, started, stopped or deleted; presence is not assumed either way.
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
 $expectedImage='C:\pvbox-readonly-probe-never-created\VBoxSDS.exe'
 $nativeFacts=@{utc=[DateTime]::UtcNow.Ticks}
 $nativeFacts.service=Get-SdsFailureServiceFacts
 $nativeFacts.Registry32=Get-SdsFailureRegistryFacts 'Registry32' $expectedImage
 $nativeFacts.Registry64=Get-SdsFailureRegistryFacts 'Registry64' $expectedImage
 $nativeFacts.process=Get-SdsFailureProcessFacts $expectedImage
 foreach($axis in @('service','Registry32','Registry64','process')){
  Check ($nativeFacts[$axis] -is [hashtable]) 'native reader returns one facts map'
  Check ($nativeFacts[$axis].query -cin @('observed','missing','error','unknown')) 'native query classification'
 }
 Check ($nativeFacts.service.ContainsKey('state') -and $nativeFacts.service.ContainsKey('hresult')) 'native service shape'
 foreach($view in @('Registry32','Registry64')){
  foreach($key in @('image','account','type','start','hresult')){Check ($nativeFacts[$view].ContainsKey($key)) 'native registry shape'}
  Check ($nativeFacts[$view].image -cin @('unknown','different','matches_requested')) 'native registry image classifier'
  Check ($nativeFacts[$view].account -cin @('unknown','different','LocalSystem')) 'native registry account classifier'
 }
 Check ($nativeFacts.process.truncated -is [bool] -and $nativeFacts.process.rows -is [object[]] -and $nativeFacts.process.rows.Count -le 4) 'native bounded process shape'
 foreach($row in $nativeFacts.process.rows){
  Check ($row -is [hashtable] -and $row.ContainsKey('pid') -and $row.ContainsKey('created')) 'native process metadata shape'
  Check ($row.image -cin @('unknown','different','matches_requested')) 'native process image classifier'
 }
 $nativeLines=@(ConvertTo-SdsFailureLines $nativeFacts 0)
 Check ($nativeLines.Count -ge 4 -and $nativeLines.Count -le 8) 'native facts render bounded records'
 $nativeBytes=0
 foreach($line in $nativeLines){
  $nativeBytes += [Text.Encoding]::UTF8.GetByteCount($line+"`r`n")
  Check ($line -cmatch '\APVBOX_SDS_FAILURE_V1 authority=none [a-zA-Z0-9_= -]+\z' -and [Text.Encoding]::UTF8.GetByteCount($line+"`r`n") -le 1024) 'native records sanitized and bounded'
  Check (-not $line.Contains($expectedImage) -and $line -notmatch 'pvbox-readonly-probe|[\\/:]') 'native raw paths excluded'
 }
 Check ($nativeBytes -le 6144) 'native sample cap'
 Write-Host 'SDS_FAILURE_NATIVE_READ_PASS'
} else {
 Write-Host 'SDS_FAILURE_NATIVE_READ_SKIP non-Windows'
}
$poison=[pscustomobject]@{};$poison|Add-Member ScriptMethod ToString {throw 'SECRET_GETTER_MUST_NOT_RUN'} -Force
$facts=@{utc=123L;service=@{query='observed';state='stopped';hresult=-1};Registry32=@{query='observed';image='SECRET_PATH';account=$poison;type=16;start=3};Registry64=@{query='missing'};process=@{query='observed';truncated=$false;rows=@()}}
$rows=@();for($i=0;$i -lt 20;$i++){$rows+=@{pid=$i+1;created=123L;image='SECRET_PROCESS_PATH'}}
$facts.process.rows=$rows
$lines=@(ConvertTo-SdsFailureLines $facts 0);$text=$lines -join "`n"
Check ($lines.Count -eq 8 -and $text -match 'retained=4 truncated=true') 'rows capped with explicit truncation'
Check ($text -notmatch 'SECRET|GETTER' -and $text -match 'image=unknown' -and $text -match 'exception_hresult=-1') 'secrets rejected, signed numeric error retained'
Check (@(ConvertTo-SdsFailureLines $facts 2).Count -eq 0) 'third sample rejected'
foreach($bad in @($poison,'123SECRET',1.5,$null)){
 $facts.utc=$bad;$facts.service.state=$bad;$facts.Registry32.type=$bad
 $text=@(ConvertTo-SdsFailureLines $facts 1)-join "`n"
 Check ($text -match 'utc_ticks=unavailable' -and $text -notmatch 'SECRET') 'malformed primitives cannot leak or execute'
}
# Native read boundary mocks must remain exact and must not introduce effects.
$serviceCalls=0;$registryCalls=0;$processCalls=0;$sleepCalls=0;$fail=$false
function Get-SdsFailureServiceFacts {$script:serviceCalls++;if($script:fail){throw 'SECRET_SERVICE_ERROR'};return @{query='error';hresult=-1}}
function Get-SdsFailureRegistryFacts {param($View,$ExpectedImage);Check ($View -cin @('Registry32','Registry64') -and $ExpectedImage -ceq 'protected/VBoxSDS.exe') 'fixed registry read selectors';$script:registryCalls++;if($script:fail){throw 'SECRET_REGISTRY_ERROR'};return @{query='missing'}}
function Get-SdsFailureProcessFacts {param($ExpectedImage);Check ($ExpectedImage -ceq 'protected/VBoxSDS.exe') 'fixed process image comparison';$script:processCalls++;if($script:fail){throw 'SECRET_PROCESS_ERROR'};return @{query='observed';rows=$rows;truncated=$true}}
function Start-Sleep {param($Milliseconds);Check ($Milliseconds -eq 200) 'single bounded intersample delay';$script:sleepCalls++}
function Start-Process {throw 'FORBIDDEN_EFFECT'}
function Set-Content {throw 'FORBIDDEN_WRITE'}
foreach($fail in @($false,$true)){
 $serviceCalls=0;$registryCalls=0;$processCalls=0;$sleepCalls=0
 $writer=[IO.StringWriter]::new();$original=[Console]::Out
 try{[Console]::SetOut($writer);$returned=@(Write-SdsFailureDiagnostics 'protected/VBoxSDS.exe')}finally{[Console]::SetOut($original)}
 $text=$writer.ToString()
 Check ($returned.Count -eq 0) 'no success-stream result or authority object'
 Check ($serviceCalls -eq 2 -and $registryCalls -eq 4 -and $processCalls -eq 2 -and $sleepCalls -eq 1) 'exact bounded read counts even on error'
 Check ($text -notmatch 'SECRET' -and $text -match 'sample=0' -and $text -match 'sample=1') 'failure snapshots no raw error leakage'
 Check ([Text.Encoding]::UTF8.GetByteCount($text) -le 6144) 'total cap'
 foreach($line in $text.Split([string[]]@("`r`n"),[StringSplitOptions]::RemoveEmptyEntries)){Check ($line.Length -le 1024 -and $line -cmatch '\APVBOX_SDS_FAILURE_V1 authority=none [a-zA-Z0-9_= -]+\z') 'bounded ASCII diagnostic record'}
}
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Text;
public sealed class SdsFailureThrowWriter : TextWriter {public override Encoding Encoding{get{return Encoding.UTF8;}}public override void Write(string value){throw new IOException("PRIVATE_SINK_ERROR");}}
'@
$original=[Console]::Out;$sink=[SdsFailureThrowWriter]::new()
try{[Console]::SetOut($sink);Write-SdsFailureDiagnostics 'protected/VBoxSDS.exe'}finally{[Console]::SetOut($original)}
Check $true 'sink failure swallowed without changing caller outcome'
# A renderer fault or oversized result is fail-closed before output.
function ConvertTo-SdsFailureLines {param($Facts,$Sample);return ('PVBOX_SDS_FAILURE_V1 authority=none '+('x'*1024))}
$writer=[IO.StringWriter]::new();$original=[Console]::Out
try{[Console]::SetOut($writer);Write-SdsFailureDiagnostics 'protected/VBoxSDS.exe'}finally{[Console]::SetOut($original)}
Check ($writer.ToString().Length -eq 0) 'oversized record not emitted'
# Seven valid 900-byte lines exceed the new collector's 6144-byte allocation.
function ConvertTo-SdsFailureLines {param($Facts,$Sample);for($i=0;$i -lt 7;$i++){'PVBOX_SDS_FAILURE_V1 authority=none '+('x'*864)}}
$writer=[IO.StringWriter]::new();$original=[Console]::Out
try{[Console]::SetOut($writer);Write-SdsFailureDiagnostics 'protected/VBoxSDS.exe'}finally{[Console]::SetOut($original)}
Check ($writer.ToString().Length -eq 0) 'aggregate cap reserves unchanged V1 bytes before any sample emission'
Write-Host "SDS_FAILURE_CAPTURE_PASS checks=$checks"
