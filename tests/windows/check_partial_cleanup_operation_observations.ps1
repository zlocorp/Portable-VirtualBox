# Execute production report initialization and effect body against synthetic OS
# boundaries. No real process, registry, service, package or elevation effects.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/vbox_sup_partial_cleanup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'partial cleanup parse failed'}
$init=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$report'})
$body=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Finally -and $_.Extent.Text -match 'cleanup-results.json'})
if($init.Count -ne 1 -or $body.Count -ne 1){throw 'unique production report/effect blocks missing'}
$run=[scriptblock]::Create($init[0].Extent.Text+"`n"+'$primaryFailure=$null'+"`n"+$body[0].Extent.Text)
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-partial-observation-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$oldMode=$env:PVBOX_FIXED_HELPER_MODE;$oldRoot=$env:SystemRoot;$oldSha=$env:GITHUB_SHA
$env:PVBOX_FIXED_HELPER_MODE='CI';$env:SystemRoot=$root;$env:GITHUB_SHA='fixture'
$published='oem42.inf';$sdsExe=Join-Path $root 'VBoxSDS.exe';$sys=Join-Path $root 'VBoxSup.sys';$installedInf=Join-Path $root 'oem42.inf';$pinSys='sys';$pinInf='inf';$TimeoutSeconds=10
$checks=0;$keys=@('sds_cleanup','service_stop','driver_package_removal','service_delete')
function Check($ok,$label){if(-not $ok){throw "FAIL partial operation observations: $label"};$script:checks++}
function Require-Quiescent {}
function Assert-PartialReceiptsUnchanged {}
function Assert-FailedStartStopped {}
function Assert-PartialDriver {
 param($ExpectedStatus)
 if($script:fault -eq 'before' -and (($script:target -eq 1 -and $script:completed -eq 1) -or ($script:target -eq 2 -and $script:completed -eq 2))){throw 'BEFORE_DRIVER'}
}
function Get-VBoxProcesses {}
function Start-Sleep {param($Seconds)}
function Get-VBoxNames {if($script:completed -lt 1){'VBoxSup';'VBoxSDS'}elseif($script:completed -lt 4){'VBoxSup'}}
function Get-ItemProperty {
 [CmdletBinding()]param([Parameter(Position=0)]$LiteralPath)
 if($LiteralPath.EndsWith('VBoxSDS')){
  if($script:fault -eq 'before' -and $script:target -eq 0){throw 'BEFORE_SDS'}
  return [pscustomobject]@{ImagePath=$sdsExe;Type=16;Start=3;ObjectName='LocalSystem'}
 }
 if($script:fault -eq 'before' -and $script:target -eq 3 -and $script:completed -eq 3){throw 'BEFORE_DELETE'}
 [pscustomobject]@{Type=1}
}
function Get-AuthenticodeSignature {param($LiteralPath) [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='Oracle'}}}
function Get-Service { [CmdletBinding()]param([Parameter(Position=0)]$Name) [pscustomobject]@{Status=$(if($Name -eq 'VBoxSDS' -or $script:completed -ge 2){'Stopped'}else{'Running'})} }
function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=$(if($LiteralPath -eq $sys){$pinSys}else{$pinInf})}}
function Test-Path {
 [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath)
 $p=if($PSBoundParameters.ContainsKey('LiteralPath')){$LiteralPath}else{$Path}
 if($p -like '*Services\VBoxSDS'){return $script:completed -lt 1}
 if($p -like '*Services\VBoxSup'){return $script:completed -lt 4}
 if($p -eq $sys -or $p -eq $installedInf){return $script:completed -lt 3}
 throw ('Unexpected path '+$p)
}
function Dispatch([int]$index){
 if($script:calls.Count -ge $script:plan.Count -or $index -ne $script:plan[$script:calls.Count]){throw 'OUT_OF_ORDER_EFFECT'}
 $script:calls.Add($index)
 if($index -eq $script:target){
  switch($script:fault){
   'throw' {throw 'DISPATCH_THROW'}
   'late' {return [pscustomobject]@{WithinDeadline=$false;ExitCodeKnown=$true;ExitCode=23}}
   'latezero' {return [pscustomobject]@{WithinDeadline=$false;ExitCodeKnown=$true;ExitCode=0}}
   'unknown' {return [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$false;ExitCode=0}}
   'nonzero' {return [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$true;ExitCode=23}}
  }
 }
 $script:completed=$index+1
 [pscustomobject]@{WithinDeadline=$true;ExitCodeKnown=$true;ExitCode=0}
}
function Invoke-ProtectedSds {param($Operation,$TimeoutSeconds);if($Operation -ne 'UnregisterPartial'){throw 'wrong SDS operation'};Dispatch 0}
function Invoke-ProtectedDriver {param($Operation,$TimeoutSeconds);$i=@{'StopSup'=1;'RemoveSupPackage'=2;'DeleteSupService'=3}[$Operation];Dispatch $i}
function Run-Bounded {param($Executable,$Argv,$Label)
 $index=@{'sds-unregister'=0;'sup-stop'=1;'sup-package-remove'=2;'sup-service-delete'=3}[$Label]
 $result=Dispatch $index;if(-not $result.WithinDeadline -or -not $result.ExitCodeKnown){throw 'BOUNDED_RETURN_UNAVAILABLE'};return [int]$result.ExitCode
}
$script:writeFault=$false
function Set-Content {
 [CmdletBinding()]param([Parameter(ValueFromPipeline=$true)]$Value,$LiteralPath,$Encoding)
 process {if($script:writeFault){throw 'REPORT_WRITE_FAILURE'};Microsoft.PowerShell.Management\Set-Content -Value $Value -LiteralPath $LiteralPath -Encoding $Encoding}
}
function Start-Process {throw 'NATIVE_LAUNCH_TRIPWIRE'}
try {
 foreach($legacy in @($false,$true)){
  $env:PVBOX_FIXED_HELPER_MODE=$(if($legacy){''}else{'CI'})
  foreach($target in 0..3){foreach($fault in @('before','throw','late','latezero','unknown','nonzero','success')){
   $out=Join-Path $root ($legacy.ToString()+'-'+$target.ToString()+'-'+$fault);[IO.Directory]::CreateDirectory($out)|Out-Null
   $markerExists=$true;$phase='Sds';$completed=0;$script:plan=@(0,1,2,3);$calls=New-Object 'Collections.Generic.List[int]'
   . $run
   $saved=[IO.File]::ReadAllText((Join-Path $out 'cleanup-results.json'))|ConvertFrom-Json
   if($fault -eq 'success'){
    Check ($saved.cleanup_verified -and $saved.sds_cleanup -eq 'CLEAN' -and $saved.service_stop -eq 'EXIT_0' -and $saved.driver_package_removal -eq 'EXIT_0' -and $saved.service_delete -eq 'EXIT_0') 'successful operation statuses'
    Check ($calls.Count -eq 4) 'four operations exactly once'
   }else{
    Check (-not $saved.cleanup_verified -and $saved.errors.Count -gt 0) 'failure remains failure'
    Check ($calls.Count -eq ($target+$(if($fault -eq 'before'){0}else{1}))) 'no later or repeated operation'
   }
   foreach($i in 0..3){
    $key=$keys[$i];$observation=$saved.operation_observations.$key
    $entered=($fault -eq 'success' -or $i -lt $target -or ($i -eq $target -and $fault -ne 'before'))
    Check ($observation.dispatch_entered -eq $entered) 'dispatch observation'
    if(-not $entered){Check ($saved.$key -eq 'NOT_ATTEMPTED') 'unentered remains NOT_ATTEMPTED'}
    elseif($i -eq $target -and ($fault -in @('throw','unknown') -or ($legacy -and $fault -in @('late','latezero')))){Check ($saved.$key -eq 'DISPATCH_ENTERED_OUTCOME_UNKNOWN') 'entered dispatch unknown'}
    if(-not $entered -or ($i -eq $target -and ($fault -eq 'throw' -or ($legacy -and $fault -in @('late','latezero','unknown'))))){
     Check ($null -eq $observation.within_deadline -and $null -eq $observation.exit_code_known -and $null -eq $observation.exit_code) 'no fabricated result'
    }elseif($i -eq $target -and $fault -eq 'unknown'){
     Check ($observation.within_deadline -eq $true -and $observation.exit_code_known -eq $false -and $null -eq $observation.exit_code) 'unknown exit not zero'
    }else{
     $exit=if($i -eq $target -and $fault -in @('late','nonzero')){23}else{0}
     Check ($observation.exit_code_known -eq $true -and $observation.exit_code -eq $exit) 'known exit retained'
     Check ($observation.within_deadline -eq (-not ($i -eq $target -and $fault -in @('late','latezero')))) 'deadline retained'
     if($i -eq $target -and $fault -in @('late','nonzero')){Check ($saved.$key -eq 'EXIT_23') 'observed exit status retained'}
     if($i -eq $target -and $fault -eq 'latezero'){Check ($saved.$key -eq 'EXIT_0' -and -not $saved.cleanup_verified) 'late zero retained without success'}
    }
   }
  }}
 }
 foreach($phaseCase in @('Stage','Start','StartFailedStopped')) {
  foreach($faultCase in @('success','throw')) {
   $out=Join-Path $root ('phase-'+$phaseCase+'-'+$faultCase);[IO.Directory]::CreateDirectory($out)|Out-Null
   $markerExists=$false;$phase=$phaseCase;$target=2;$fault=$faultCase;$calls=New-Object 'Collections.Generic.List[int]'
   if($phaseCase -eq 'Start'){$completed=1;$script:plan=@(1,2,3)}else{$completed=2;$script:plan=@(2,3)}
   . $run
   $saved=[IO.File]::ReadAllText((Join-Path $out 'cleanup-results.json'))|ConvertFrom-Json
   Check ($saved.sds_cleanup -eq 'NOT_ATTEMPTED' -and -not $saved.operation_observations.sds_cleanup.dispatch_entered) 'no SDS dispatch for non-SDS checkpoint'
   if($phaseCase -eq 'Start'){Check ($saved.service_stop -eq 'EXIT_0' -and $saved.operation_observations.service_stop.dispatch_entered) 'start checkpoint stops driver once'}
   else{Check ($saved.service_stop -eq 'NOT_ATTEMPTED' -and -not $saved.operation_observations.service_stop.dispatch_entered) 'stopped checkpoint never dispatches stop'}
   if($faultCase -eq 'throw'){Check (-not $saved.cleanup_verified -and $saved.driver_package_removal -eq 'DISPATCH_ENTERED_OUTCOME_UNKNOWN') 'package dispatch failure unknown'}
   else{Check ($saved.cleanup_verified -and $calls.Count -eq $script:plan.Count) 'checkpoint-specific successful plan'}
  }
 }
 foreach($effectFault in @('throw','success')){
  $out=Join-Path $root ('write-failure-'+$effectFault);[IO.Directory]::CreateDirectory($out)|Out-Null
  $markerExists=$true;$phase='Sds';$completed=0;$script:plan=@(0,1,2,3);$calls=New-Object 'Collections.Generic.List[int]';$target=0;$fault=$effectFault;$script:writeFault=$true
  $message='';$caught=$null;try {. $run}catch{$caught=$_.Exception;$message=$caught.Message}finally{$script:writeFault=$false}
  Check ($message -match 'REPORT_WRITE_FAILURE') 'write failure is reported'
  if($effectFault -eq 'throw'){Check ($message -match 'DISPATCH_THROW' -and $calls.Count -eq 1 -and $null -ne $caught.InnerException -and $caught.InnerException.Message -match 'DISPATCH_THROW') 'primary effect error preserved alongside write failure'}
  else{Check ($calls.Count -eq 4 -and $message -eq 'REPORT_WRITE_FAILURE') 'write failure after successful effects remains failure'}
  Check (-not [IO.File]::Exists((Join-Path $out 'cleanup-results.json'))) 'failed write does not invent report'
 }
 Write-Host "PARTIAL_CLEANUP_OPERATION_OBSERVATIONS_PASS checks=$checks"
}finally{$env:PVBOX_FIXED_HELPER_MODE=$oldMode;$env:SystemRoot=$oldRoot;$env:GITHUB_SHA=$oldSha;Remove-Item -LiteralPath $root -Recurse -Force}
