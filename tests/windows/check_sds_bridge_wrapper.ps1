# Managed PowerShell wrapper behavior only. No assembly, native process, service,
# driver or registry is loaded/touched by this fixture.
param([string]$Repository=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require([bool]$Ok,[string]$Message) { if (-not $Ok) { throw $Message } }
$tokens=$null;$errors=$null
$source=Join-Path $Repository 'scripts/privileged_session_worker.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
Require ($errors.Count -eq 0) 'Protected source parse failed'
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Run-Sds'},$true))
Require ($functions.Count -eq 1) 'Exactly one Run-Sds required'
# Load only reviewed wrapper; dependencies are substituted fixed boundaries.
. ([scriptblock]::Create($functions[0].Extent.Text))
$savedMode=$env:PVBOX_FIXED_HELPER_MODE
try {
 foreach ($mode in @('CI','ALPHA')) {
  foreach ($case in @('Success','Nonzero','LateZero','LateNonzero','ObservationError','UnknownExit','MissingBridge')) {
   & {
    $env:PVBOX_FIXED_HELPER_MODE=$mode
    $state=@{Native=0;Bridge=0}
    function Start-Process { $state.Native++;throw 'FORBIDDEN_LEGACY_NATIVE' }
    if($case -ne 'MissingBridge') {
     function Invoke-ProtectedSds {
      param([string]$Operation,[int]$TimeoutSeconds)
      $state.Bridge++
      Require ($Operation -ceq 'Register' -and $TimeoutSeconds -eq 30) 'Protected registration selector changed'
      if($case -eq 'ObservationError'){throw 'FIXTURE_OBSERVATION_FAILURE'}
      return [pscustomobject]@{
       WithinDeadline=($case -notin @('LateZero','LateNonzero'))
       ExitCodeKnown=($case -ne 'UnknownExit')
       ExitCode=$(if($case -in @('Nonzero','LateNonzero')){5}else{0})
       ElapsedMs=31000L
      }
     }
    }
    $facts=@{Launch='not_attempted';Handle='not_observed';Wait='not_observed';Completion='not_observed';ExitCode=$null;ElapsedMs=$null}
    $caught=$null
    try{Run-Sds '--regservice' 'sds-register' $facts}catch{$caught=$_}
    Require ($state.Native -eq 0) "$mode/$case fell back to legacy native process"
    Require ($state.Bridge -eq $(if($case -eq 'MissingBridge'){0}else{1})) "$mode/$case bridge count"
    Require (($null -eq $caught) -eq ($case -eq 'Success')) "$mode/$case changed acceptance"
    if($case -in @('Nonzero','LateZero','LateNonzero')) {
     $expected=if($case -eq 'Nonzero'){'SDS operation unconfirmed; retain resources'}else{'SDS operation exceeded safety deadline; child exited, state requires inspection'}
     Require ($caught.Exception.Message -ceq $expected) "$mode/$case changed refusal"
    }
    if($case -eq 'ObservationError'){Require ($caught.Exception.Message.Contains('FIXTURE_OBSERVATION_FAILURE')) 'Observation failure replaced'}
    if($case -in @('ObservationError','MissingBridge')){
     Require ($facts.Launch -ceq 'unknown') 'Bridge exception invented launch failure or no-attempt fact'
     Require ($facts.Completion -ceq 'not_observed' -and $null -eq $facts.ExitCode) 'Bridge exception invented completion facts'
    }
    if($case -eq 'Success') {
     Require ($facts.Launch -ceq 'returned' -and $facts.Handle -ceq 'nonzero' -and $facts.Wait -ceq 'within_deadline' -and $facts.Completion -ceq 'confirmed' -and $facts.ExitCode -eq 0) 'Success lost measured facts'
    }
    if($case -in @('LateZero','LateNonzero')) {
     Require ($facts.Wait -ceq 'exceeded' -and $facts.Completion -ceq 'confirmed' -and $null -eq $facts.ExitCode) 'Late result promoted or diagnostic semantics changed'
    }
    Write-Host "PASS protected SDS wrapper $mode/$case"
   }
  }
 }
 foreach($case in @('UnknownMode','WrongArgument','WrongLabel')){
  & {
   $env:PVBOX_FIXED_HELPER_MODE=if($case -eq 'UnknownMode'){'OTHER'}else{'CI'}
   $state=@{Native=0;Bridge=0}
   function Start-Process {$state.Native++;throw 'FORBIDDEN_NATIVE'}
   function Invoke-ProtectedSds {$state.Bridge++;throw 'FORBIDDEN_BRIDGE'}
   $argument=if($case -eq 'WrongArgument'){'--unregservice'}else{'--regservice'}
   $label=if($case -eq 'WrongLabel'){'arbitrary-output'}else{'sds-register'}
   $caught=$null;try{Run-Sds $argument $label @{}}catch{$caught=$_}
   Require ($null -ne $caught -and $state.Native -eq 0 -and $state.Bridge -eq 0) "$case admitted unexpected execution selector"
   Write-Host "PASS protected SDS wrapper $case"
  }
 }
 # Exercise the actual narrowly selected unregister transport branch, never
 # the scripts' service/registry/file-removal preambles or continuation bodies.
 foreach($selection in @(
  @{File='vbox_sup_cleanup.ps1';Operation='UnregisterFull';Result='sdsExit'},
  @{File='vbox_sup_partial_cleanup.ps1';Operation='UnregisterPartial';Result='result'}
 )) {
  $tokens=$null;$errors=$null
  $cleanupAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository ('scripts/'+$selection.File)),[ref]$tokens,[ref]$errors)
  Require ($errors.Count -eq 0) 'Cleanup parse failed'
  $branches=@($cleanupAst.FindAll({param($n)
   $n -is [Management.Automation.Language.IfStatementAst] -and
   $n.Clauses[0].Item1.Extent.Text -ceq '$env:PVBOX_FIXED_HELPER_MODE' -and
   $n.Extent.Text.Contains('Invoke-ProtectedSds -Operation '+$selection.Operation)
  },$true))
  Require ($branches.Count -eq 1) 'Expected one exact cleanup transport branch'
  foreach($command in @($branches[0].FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true))){
   Require ($command.GetCommandName() -cin @('Invoke-ProtectedSds','Run-Bounded')) 'Unexpected effect in selected cleanup transport'
  }
  $branch=[scriptblock]::Create($branches[0].Extent.Text)
  foreach($protectedMode in @('CI','ALPHA')){
  foreach($case in @('Success','Nonzero','Late','UnknownExit','ObservationError','MissingBridge','UnknownMode','Standalone')){
   & {
    $env:PVBOX_FIXED_HELPER_MODE=if($case -eq 'UnknownMode'){'OTHER'}elseif($case -eq 'Standalone'){$null}else{$protectedMode}
    $state=@{Bridge=0;Legacy=0};$TimeoutSeconds=45;$expectedSds='fixed-app/VBoxSDS.exe';$sdsExe=$expectedSds
    function Run-Bounded {
     param($Command,$Argument,$Label)
     $state.Legacy++
     Require ($Command -ceq $expectedSds -and $Argument -ceq '--unregservice' -and $Label -ceq 'sds-unregister') 'Standalone unregister selector changed'
     return 0
    }
    if($case -ne 'MissingBridge'){
     function Invoke-ProtectedSds{
      param([string]$Operation,[int]$TimeoutSeconds)
      $state.Bridge++
      Require ($Operation -ceq $selection.Operation -and $TimeoutSeconds -eq 45) 'Protected unregister selector changed'
      if($case -eq 'ObservationError'){throw 'FIXTURE_OBSERVATION_FAILURE'}
      return [pscustomobject]@{WithinDeadline=($case -ne 'Late');ExitCodeKnown=($case -ne 'UnknownExit');ExitCode=$(if($case -eq 'Nonzero'){5}else{0});ElapsedMs=1L}
     }
    }
    $caught=$null;try{. $branch}catch{$caught=$_}
    $accepted=$case -in @('Success','Nonzero','Standalone')
    Require (($null -eq $caught) -eq $accepted) "$($selection.Operation)/$case transport branch outcome"
    Require ($state.Legacy -eq $(if($case -eq 'Standalone'){1}else{0})) "$($selection.Operation)/$case used legacy fallback"
    Require ($state.Bridge -eq $(if($case -in @('Standalone','UnknownMode','MissingBridge')){0}else{1})) "$($selection.Operation)/$case bridge count"
    if($accepted){
     $exit=Get-Variable -Name $selection.Result -ValueOnly
     Require ($exit -eq $(if($case -eq 'Nonzero'){5}else{0})) 'Unregister branch discarded exit code before authoritative gate'
    }
    Write-Host "PASS protected SDS cleanup $protectedMode/$($selection.Operation)/$case"
   }
  }
  }
 }
} finally { $env:PVBOX_FIXED_HELPER_MODE=$savedMode }
Write-Host 'SDS_BRIDGE_WRAPPER_PASS'
