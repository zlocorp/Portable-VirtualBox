# Compile actual fixture helpers but never invoke native APIs or launch a GUI.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '../../scripts/check_russian_gui.ps1'
$source=[IO.File]::ReadAllText($path)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'fixture parse errors'}
$code=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
Add-Type -TypeDefinition $code
$defs=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-LocaleFailure'},$true))
if($defs.Count -ne 1){throw 'missing evidence writer'}
. ([scriptblock]::Create($defs[0].Extent.Text))
function Check($value,$label){if(-not $value){throw $label}}
foreach($phase in @('Await','Capture','Click','secret')){
 [LocaleProbeEvidence]::Phase=$phase;[LocaleProbeEvidence]::ExpectedPid=42;[LocaleProbeEvidence]::Owner=100;[LocaleProbeEvidence]::Index=3
 [LocaleProbeEvidence]::Begin(101,42,('Button'+('x'*100)),("Public`n"+('Ж'*200)),49)
 $row=[LocaleProbeEvidence]::Last
 Check ($row['class'].Length -eq 64 -and $row['caption'].Length -eq 128 -and $row['caption'] -notmatch "`n") 'string limits'
 Check ($row['completed'] -eq $false -and $row['expected_pid'] -eq 42 -and $row['observed_pid'] -eq 42 -and $row['index'] -eq 3) 'owned observation shape'
 Check ($row['phase'] -eq $(if($phase -eq 'secret'){'unknown'}else{$phase})) 'phase whitelist'
 foreach($case in @(@(0,0,'failure_unspecified'),@(0,1460,'failure_with_error'),@(0,5,'failure_with_error'),@(1,0,'success'))){
  [LocaleProbeEvidence]::End($case[0],0,$case[1],100)
  Check ($row['transport'] -eq $case[2] -and $row['last_error'] -eq $case[1] -and $row['api_result'] -eq $case[0]) 'transport not inferred from font handle'
 }
}
# Every text observation clears stale child dimensions, not only phase entry.
[LocaleProbeEvidence]::Width=300;[LocaleProbeEvidence]::Height=40
[LocaleProbeEvidence]::Begin(101,42,'Button','Public',49)
Check ([LocaleProbeEvidence]::Last['width'] -eq 300) 'font observation keeps fresh dimensions'
foreach($phase in @('Await','Capture','Click','Await')){
 [LocaleProbeEvidence]::Phase=$phase
 [LocaleProbeEvidence]::Width=300;[LocaleProbeEvidence]::Height=40
 [LocaleProbeEvidence]::Begin(100,42,'AutoIt v3 GUI','',13)
 Check ([LocaleProbeEvidence]::Last['width'] -eq 0 -and [LocaleProbeEvidence]::Last['height'] -eq 0) 'WM_GETTEXT never inherits dimensions'
}
[LocaleProbeEvidence]::End(1,0,0,100)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-font-evidence-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
 Write-LocaleFailure $temp System.InvalidOperationException
 $file=Join-Path $temp 'failure.json'
 Check ([IO.File]::Exists($file) -and (Get-Item $file).Length -le 8192) 'failure before any success artifact saved'
 $parsed=Get-Content $file -Raw|ConvertFrom-Json
 Check ($parsed.authority -eq 'none' -and $parsed.last_observation.timeout_ms -eq 250 -and $parsed.last_observation.flags -eq 3) 'gate unchanged'
 Check ($parsed.failure_type -eq 'System.InvalidOperationException' -and $parsed.last_observation.transport -eq 'success' -and $parsed.failure_kind -eq 'observation_or_gate_failure') 'successful last observation is not failure origin'
 $original=[InvalidOperationException]::new('original control observation failure')
 try{try{throw $original}catch{Write-LocaleFailure (Join-Path $temp 'missing/child');throw}}catch{Check ([object]::ReferenceEquals($_.Exception,$original)) 'writer error masked original'}
 [IO.File]::Delete($file);[LocaleProbeEvidence]::Last['oversize']='x'*9000
 Write-LocaleFailure $temp System.InvalidOperationException
 Check (-not [IO.File]::Exists($file)) 'hard byte bound'
}finally{[IO.Directory]::Delete($temp,$true)}
Write-Host 'RUSSIAN_FAILURE_DIAGNOSTICS_PASS'
