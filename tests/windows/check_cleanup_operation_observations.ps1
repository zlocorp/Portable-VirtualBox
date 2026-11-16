[CmdletBinding()]
param()
# Execute actual production report initialization + effect try/catch/finally.
# All OS boundaries are mocked. No services, packages, native children or UAC.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/vbox_sup_cleanup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'parse failed'}
$init=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$report'})
$body=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Finally})
if($init.Count -ne 1 -or $body.Count -ne 1){throw 'unique production blocks missing'}
$run=[scriptblock]::Create($init[0].Extent.Text+"`n"+$body[0].Extent.Text)
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-operation-report-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$oldMode=$env:PVBOX_FIXED_HELPER_MODE;$oldRoot=$env:SystemRoot
$env:PVBOX_FIXED_HELPER_MODE='CI';$env:SystemRoot=$root
$prospective=$false;$published='oem42.inf';$bootVerified=$true;$expectedSds=Join-Path $root 'VBoxSDS.exe'
$sys=Join-Path $root 'VBoxSup.sys';$installedInf=Join-Path $root 'oem42.inf';$pinSys='sys';$pinInf='inf';$TimeoutSeconds=5
$checks=0;$keys=@('sds_cleanup','service_stop','driver_package_removal','service_delete')
function Check($ok,$label){if(-not $ok){throw "FAIL operation observations: $label"};$script:checks++}
function Get-VBoxProcesses {}
function Start-Sleep {param($Seconds)}
function Get-VBoxNames {
 if($script:fault -eq 'before' -and $script:target -eq 1 -and $script:completed -eq 1){throw 'BEFORE_STOP'}
 if($script:completed -lt 1){'VBoxSup';'VBoxSDS'}elseif($script:completed -lt 4){'VBoxSup'}
}
function Get-ItemProperty {
 [CmdletBinding()]param($LiteralPath)
 if($LiteralPath.EndsWith('VBoxSDS')){
  if($script:fault -eq 'before' -and $script:target -eq 0){throw 'BEFORE_SDS'}
  return [pscustomobject]@{ImagePath=$expectedSds;Type=16;Start=3;ObjectName='LocalSystem'}
 }
 if($script:fault -eq 'before' -and $script:target -eq 3 -and $script:completed -eq 3){throw 'BEFORE_DELETE'}
 [pscustomobject]@{ImagePath='\SystemRoot\System32\drivers\VBoxSup.sys';Type=1}
}
function Get-Service {
 [CmdletBinding()]param($Name)
 if($Name -eq 'VBoxSDS'){return [pscustomobject]@{Status='Stopped'}}
 if($script:completed -eq 4){return $null}
 [pscustomobject]@{Status=$(if($script:completed -lt 2){'Running'}else{'Stopped'})}
}
function Get-FileHash {
 param($LiteralPath,$Algorithm)
 if($script:fault -eq 'before' -and $script:target -eq 2 -and $script:completed -eq 2){throw 'BEFORE_PACKAGE'}
 [pscustomobject]@{Hash=$(if($LiteralPath -eq $sys){$pinSys}else{$pinInf})}
}
function Test-Path {
 [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath)
 $p=if($PSBoundParameters.ContainsKey('LiteralPath')){$LiteralPath}else{$Path}
 if($p -like '*Services\VBoxSDS'){return $script:completed -lt 1}
 if($p -like '*Services\VBoxSup'){return $script:completed -lt 4}
 if($p -eq $sys -or $p -eq $installedInf){return $script:completed -lt 3}
 throw ('Unexpected path observation '+$p)
}
function Dispatch([int]$index){
 if($index -ne $script:calls.Count){throw 'OUT_OF_ORDER_EFFECT'}
 $script:calls.Add($index)
 if($index -eq $script:target){
  switch($script:fault){
   'throw' {throw 'DISPATCH_THROW'}
   'late' {return [pscustomobject]@{WithinDeadline=$false;ExitCodeKnown=$true;ExitCode=23}}
   'unknown' {return [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$false;ExitCode=0}}
   'nonzero' {return [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$true;ExitCode=23}}
  }
 }
 $script:completed=$index+1
 [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$true;ExitCode=0}
}
function Invoke-ProtectedSds {param($Operation,$TimeoutSeconds);if($Operation -ne 'UnregisterFull'){throw 'unexpected SDS operation'};Dispatch 0}
function Invoke-ProtectedDriver {param($Operation,$TimeoutSeconds);$i=@{'StopSup'=1;'RemoveSupPackage'=2;'DeleteSupService'=3}[$Operation];Dispatch $i}
function Run-Bounded {
 param($Executable,$Argv,$Label)
 $index=@{'sds-unregister'=0;'sup-stop'=1;'sup-package-remove'=2;'sup-service-delete'=3}[$Label]
 $result=Dispatch $index
 if(-not $result.WithinDeadline -or -not $result.ExitCodeKnown){throw 'BOUNDED_RETURN_UNAVAILABLE'}
 return [int]$result.ExitCode
}
function Start-Process {throw 'NATIVE_LAUNCH_TRIPWIRE'}
try {
 foreach($legacy in @($false,$true)){
 $env:PVBOX_FIXED_HELPER_MODE=$(if($legacy){''}else{'CI'})
 foreach($target in 0..3){foreach($fault in @('before','throw','late','unknown','nonzero','success')){
  $out=Join-Path $root ($legacy.ToString()+'-'+$target.ToString()+'-'+$fault);[IO.Directory]::CreateDirectory($out)|Out-Null
  $completed=0;$calls=New-Object 'Collections.Generic.List[int]'
  . $run
  $saved=[IO.File]::ReadAllText((Join-Path $out 'cleanup-results.json'))|ConvertFrom-Json
  if($fault -eq 'success'){
   Check ($saved.cleanup_verified -and $saved.sds_cleanup -eq 'CLEAN' -and $saved.service_stop -eq 'EXIT_0' -and $saved.driver_package_removal -eq 'EXIT_0' -and $saved.service_delete -eq 'EXIT_0') 'success compatibility'
   Check ($calls.Count -eq 4) 'all four successful operations exactly once'
  }else{
   Check (-not $saved.cleanup_verified -and $saved.errors.Count -gt 0) 'failure remains failure'
   Check ($calls.Count -eq ($target+$(if($fault -eq 'before'){0}else{1}))) 'no skipped or subsequent dispatch'
  }
  foreach($i in 0..3){
   $key=$keys[$i]
   if($fault -ne 'success' -and ($i -gt $target -or ($i -eq $target -and $fault -eq 'before'))){
    Check ($saved.$key -eq 'NOT_ATTEMPTED') 'undispatched operation NOT_ATTEMPTED'
   }elseif($i -eq $target -and ($fault -in @('throw','unknown') -or ($legacy -and $fault -eq 'late'))){
    Check ($saved.$key -eq 'DISPATCH_ENTERED_OUTCOME_UNKNOWN') 'entered dispatch must not claim NOT_ATTEMPTED'
   }
   $observation=$saved.operation_observations.$key
   $entered=($fault -eq 'success' -or $i -lt $target -or ($i -eq $target -and $fault -ne 'before'))
   Check ($observation.dispatch_entered -eq $entered) 'dispatch entry observation exact'
   if(-not $entered -or ($i -eq $target -and ($fault -eq 'throw' -or ($legacy -and $fault -in @('late','unknown'))))){
    Check ($null -eq $observation.within_deadline -and $null -eq $observation.exit_code_known -and $null -eq $observation.exit_code) 'no fabricated returned result'
   }elseif($i -eq $target -and $fault -eq 'unknown'){
    Check ($observation.within_deadline -eq $true -and $observation.exit_code_known -eq $false -and $null -eq $observation.exit_code) 'unknown exit does not store default zero'
   }else{
    $exit=if($i -eq $target -and $fault -in @('late','nonzero')){23}else{0}
    Check ($observation.exit_code_known -eq $true -and $observation.exit_code -eq $exit) 'known exit saved before failure guard'
    Check ($observation.within_deadline -eq (-not ($i -eq $target -and $fault -eq 'late'))) 'deadline saved before failure guard'
    if($i -eq $target -and $fault -in @('late','nonzero')){Check ($saved.$key -eq 'EXIT_23') 'nonzero/late known exit retained'}
   }
  }
 }}}
 Write-Host "CLEANUP_OPERATION_OBSERVATIONS_PASS checks=$checks"
}finally{$env:PVBOX_FIXED_HELPER_MODE=$oldMode;$env:SystemRoot=$oldRoot;Remove-Item -LiteralPath $root -Recurse -Force}
