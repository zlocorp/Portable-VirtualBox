# PowerShell wrapper behavior with substituted effects and one isolated loader
# process using a harmless managed fixture DLL. No service/driver/registry effects.
param([string]$Repository=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require([bool]$Ok,[string]$Message) { if (-not $Ok) { throw $Message } }
$tokens=$null;$errors=$null
$source=Join-Path $Repository 'scripts/privileged_session_worker.ps1'
# Windows PowerShell 5.1 treats BOM-less script files as ANSI. Keep this
# production guard and its fixture ASCII; construct tested Unicode at runtime.
Require ([IO.File]::ReadAllText($source,[Text.Encoding]::UTF8) -cnotmatch '[^\x00-\x7f]') 'Protected script must remain ASCII for Windows PowerShell 5.1'
Require ([IO.File]::ReadAllText($PSCommandPath,[Text.Encoding]::UTF8) -cnotmatch '[^\x00-\x7f]') 'Wrapper fixture must remain ASCII for Windows PowerShell 5.1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
Require ($errors.Count -eq 0) 'Protected source parse failed'
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Run-Sds'},$true))
Require ($functions.Count -eq 1) 'Exactly one Run-Sds required'
# Load only reviewed wrapper; dependencies are substituted fixed boundaries.
. ([scriptblock]::Create($functions[0].Extent.Text))
$savedMode=$env:PVBOX_FIXED_HELPER_MODE
$savedRunnerTemp=$env:RUNNER_TEMP
try {
 # Execute the actual ALPHA guard with only the workstation query replaced.
 # The child must use the parent-pinned locator, not rediscover ProgramData
 # from the deliberately cleared child environment.
 foreach($name in @('Assert-CanonicalAlphaLocator','Assert-PortableFixedHelper')){
  $declarations=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
  Require ($declarations.Count -eq 1) "Exactly one $name required"
  . ([scriptblock]::Create($declarations[0].Extent.Text))
 }
 $validStore='C:\ProgramData\PortableVirtualBox.Alpha'
 $validSession=$validStore+'\pvbox-manager-123-1'
 $unicodeSegment=-join ([char[]]@(0x0414,0x0430,0x043d,0x043d,0x044b,0x0435,0x20,0x4e16,0x754c))
 $unicodeStore='D:\'+$unicodeSegment+'\PortableVirtualBox.Alpha'
 Require ($unicodeSegment.Length -eq 9 -and [int]$unicodeSegment[0] -eq 0x0414 -and [int]$unicodeSegment[7] -eq 0x4e16 -and [int]$unicodeSegment[8] -eq 0x754c) 'Unicode fixture codepoints changed'
 $locatorCases=@(
  @{Name='Valid';Store=$validStore;Session=$validSession;Ok=$true},
  @{Name='Unicode';Store=$unicodeStore;Session=$unicodeStore+'\pvbox-manager-123-1';Ok=$true},
  @{Name='Missing';Store=$null;Session=$validSession},
  @{Name='Relative';Store='PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='DriveRelative';Store='C:PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='Mismatch';Store=$validStore;Session='C:\Other\PortableVirtualBox.Alpha\pvbox-manager-123-1'},
  @{Name='WrongLeaf';Store='C:\ProgramData\Other';Session='C:\ProgramData\Other\pvbox-manager-123-1'},
  @{Name='WrongMode';Store=$validStore;Session=$validSession;Mode='CI'},
  @{Name='UNC';Store='\\server\share\PortableVirtualBox.Alpha';Session='\\server\share\PortableVirtualBox.Alpha\pvbox-manager-123-1'},
  @{Name='Device';Store='\\?\C:\ProgramData\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='Slash';Store='C:/ProgramData/PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='Traversal';Store='C:\Other\..\ProgramData\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='DotSegment';Store='C:\ProgramData\.\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='RepeatedSeparator';Store='C:\ProgramData\\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='TrailingSlash';Store=$validStore+'\';Session=$validSession},
  @{Name='TrailingDot';Store='C:\ProgramData.\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='TrailingSpace';Store='C:\ProgramData \PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='ShortName';Store='C:\PROGRA~1\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='ADS';Store='C:\ProgramData:stream\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='BadSession';Store=$validStore;Session=$validStore+'\..\pvbox-manager-123-1'},
  @{Name='MissingSession';Store=$validStore;Session=$null},
  @{Name='CaseEquivalent';Store='c:\programdata\portablevirtualbox.alpha';Session='C:\ProgramData\PortableVirtualBox.Alpha\pvbox-manager-123-1';Ok=$true},
  @{Name='LeadingSpace';Store='C:\ ProgramData\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='UnicodeWhitespace';Store=('C:\Data'+[char]0xa0+'\PortableVirtualBox.Alpha');Session=$validSession},
  @{Name='Reserved';Store='C:\NUL.txt\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='ReservedConsole';Store='C:\CONIN$\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='ReservedSuperscript';Store=('C:\COM'+[char]0x00b9+'\PortableVirtualBox.Alpha');Session=$validSession},
  @{Name='Wildcard';Store='C:\Data*\PortableVirtualBox.Alpha';Session=$validSession},
  @{Name='Control';Store=('C:\Data'+[char]0x1f+'\PortableVirtualBox.Alpha');Session=$validSession},
  @{Name='C1Control';Store=('C:\Data'+[char]0x85+'\PortableVirtualBox.Alpha');Session=$validSession},
  @{Name='LongPath';Store=('C:\'+('a'*240)+'\PortableVirtualBox.Alpha');Session=$validSession},
  @{Name='SessionAlias';Store=$validStore;Session=$validStore+'\pvbox-manager-123-1.'}
 )
 foreach($case in $locatorCases){
  & {
   $env:PVBOX_FIXED_HELPER_MODE=if($case.ContainsKey('Mode')){$case.Mode}else{'ALPHA'}
   $env:RUNNER_TEMP=$case.Store;$SessionDir=$case.Session;$observations=@{Os=0}
   function Get-CimInstance {
    [CmdletBinding()]param([string]$ClassName)
    $observations.Os++
    Require ($ClassName -ceq 'Win32_OperatingSystem' -and $PSBoundParameters['ErrorAction'] -eq 'Stop') 'Unexpected ALPHA query'
    return [pscustomobject]@{ProductType=1;BuildNumber='22631'}
   }
   $caught=$null;try{Assert-PortableFixedHelper}catch{$caught=$_}
   $ok=$case.ContainsKey('Ok') -and $case.Ok
   Require (($null -eq $caught) -eq $ok) "ALPHA/$($case.Name) locator acceptance: $caught"
   Require ($observations.Os -eq $(if($ok){1}else{0})) "ALPHA/$($case.Name) queried workstation before valid locator"
   Write-Host "PASS fixed ALPHA locator $($case.Name)"
  }
 }
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
 # Real nested '& child.ps1' call across distinct defining/caller directories.
 # Production loader, harmless fixed DLL, isolated PowerShell; no system effects.
 if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -or $env:PVBOX_TEST_NET48_REFERENCES) {
  $loader=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-ProtectedSds'},$true))
  Require ($loader.Count -eq 1) 'Exactly one production protected loader required'
  $fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-sds-nested-'+[guid]::NewGuid().ToString('N'))
  $defining=Join-Path $fixtureRoot 'defining';$calling=Join-Path $fixtureRoot 'calling'
  New-Item -ItemType Directory -Path $defining,$calling | Out-Null
  try {
   $fixtureSource=Join-Path $fixtureRoot 'HarmlessSdsBridge.cs'
   [IO.File]::WriteAllText($fixtureSource,@'
namespace PortableVBox {
 public enum SdsOperation { Register, UnregisterFull, UnregisterPartial }
 public sealed class HarmlessResult {
  public string Kind { get { return "TEST_ONLY_NO_EFFECTS"; } }
  public string Operation { get; internal set; }
  public int TimeoutSeconds { get; internal set; }
  public string Location { get; internal set; }
 }
 public static class SdsBridge {
  public static HarmlessResult Run(SdsOperation operation,int timeoutSeconds) {
   return new HarmlessResult {
    Operation=operation.ToString(),TimeoutSeconds=timeoutSeconds,
    Location=typeof(SdsBridge).Assembly.Location
   };
  }
 }
}
'@,[Text.UTF8Encoding]::new($false))
   $fixtureDll=Join-Path $defining 'PortableVBox.SdsBridge.dll'
   . (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
   Compile-FixedFixtureSources @($fixtureSource) $fixtureDll $null
   Require ([Reflection.AssemblyName]::GetAssemblyName($fixtureDll).Name -ceq 'PortableVBox.SdsBridge') 'Harmless assembly simple name changed'
   Require (@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {$_.GetName().Name -ceq 'PortableVBox.SdsBridge'}).Count -eq 0) 'Compiler loaded the harmless fixture before real loader'
   Require (-not (Test-Path -LiteralPath (Join-Path $calling 'PortableVBox.SdsBridge.dll'))) 'Calling directory must not contain a bridge'
   $child=Join-Path $calling 'child.ps1'
   [IO.File]::WriteAllText($child,@'
param([string]$ExpectedDll)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Recreate the actual loader body without a defining file in a nested scope.
# It must refuse before loading any assembly, then leave the file-defined
# function intact for the real child-call regression below.
$memoryDefinition=[scriptblock]::Create('function Invoke-ProtectedSds {'+(Get-Command Invoke-ProtectedSds -CommandType Function).Definition+'}')
& {
 . $memoryDefinition
 if (-not [string]::IsNullOrEmpty((Get-Command Invoke-ProtectedSds -CommandType Function).ScriptBlock.File)) { throw 'Expected in-memory function definition' }
 $refused=$false
 try { Invoke-ProtectedSds -Operation UnregisterPartial -TimeoutSeconds 45 | Out-Null }
 catch { if ($_.Exception.Message -ceq 'Unknown protected SDS function definition') { $refused=$true } else { throw } }
 if (-not $refused) { throw 'Loader accepted a function without a defining file' }
 if (@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {$_.GetName().Name -ceq 'PortableVBox.SdsBridge'}).Count -ne 0) { throw 'No-file refusal loaded an assembly' }
 Write-Host 'SDS_NOFILE_LOADER_REFUSAL_PASS'
}
$result=Invoke-ProtectedSds -Operation UnregisterPartial -TimeoutSeconds 45
if ($result.Kind -cne 'TEST_ONLY_NO_EFFECTS' -or
    $result.Operation -cne 'UnregisterPartial' -or $result.TimeoutSeconds -ne 45 -or
    $result.Location -cne $ExpectedDll) { throw 'Nested loader did not execute exact defining-directory harmless bridge' }
$refused=$false
try { Invoke-ProtectedSds -Operation UnregisterPartial -TimeoutSeconds 45 | Out-Null }
catch { if ($_.Exception.Message -ceq 'Unexpected preloaded SDS bridge assembly') { $refused=$true } else { throw } }
if (-not $refused) { throw 'Second loader call did not refuse preloaded bridge' }
Write-Host 'SDS_NESTED_LOADER_PASS'
'@,[Text.UTF8Encoding]::new($false))
   # Preserve old top-level cache initializers for red regression. They belong
   # to the defining script, not the nested calling script.
   $initializers=@([regex]::Matches([IO.File]::ReadAllText($source),'(?m)^\$script:Sds(?:BridgeType|OperationType)=\$null\r?$') | ForEach-Object {$_.Value})
   $worker=Join-Path $defining 'privileged_session_worker.ps1'
   $nl=[Environment]::NewLine
   $workerText='Set-StrictMode -Version Latest'+$nl+'$ErrorActionPreference=''Stop'''+$nl+($initializers -join $nl)+$nl+$loader[0].Extent.Text+$nl+"& '"+$child.Replace("'","''")+"' '"+$fixtureDll.Replace("'","''")+"'"+$nl
   [IO.File]::WriteAllText($worker,$workerText,[Text.UTF8Encoding]::new($false))
   $env:PVBOX_FIXED_HELPER_MODE='CI'
   $engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
   & $engine -NoProfile -NonInteractive -File $worker
   Require ($LASTEXITCODE -eq 0) 'Actual nested protected loader child failed'
  } finally { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
 } else { Write-Host 'SKIP SDS nested loader: net48 reference toolchain unavailable on non-Windows' }
} finally { $env:PVBOX_FIXED_HELPER_MODE=$savedMode; $env:RUNNER_TEMP=$savedRunnerTemp }
Write-Host 'SDS_BRIDGE_WRAPPER_PASS'
