# Execute the production partial-cleanup script with all OS observations and
# effects replaced by controlled fixtures. Only temporary files are changed.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-partial-admission-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$path=Join-Path $repo 'scripts/vbox_sup_partial_cleanup.ps1'
$source=[IO.File]::ReadAllText($path)
if (([regex]::Matches($source,[regex]::Escape('[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)'))).Count -ne 1) { throw 'Unexpected controller call sites' }
$source=$source.Replace('[Diagnostics.Process]::GetProcessById([int]$proof.controller_pid)', '(Get-FixtureController ([int]$proof.controller_pid))')
if (([regex]::Matches($source,[regex]::Escape('[IO.File]::Open($proofPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)'))).Count -ne 1) { throw 'Unexpected proof writer sites' }
$source=$source.Replace('[IO.File]::Open($proofPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)', '(Open-FixtureProof $proofPath ([IO.FileMode]::CreateNew) ([IO.FileAccess]::Write) ([IO.FileShare]::Read))')
$source=$source.Replace("| Set-Content -LiteralPath (Join-Path `$out 'cleanup-results.json') -Encoding utf8", "| Write-FixtureReport -LiteralPath (Join-Path `$out 'cleanup-results.json') -Encoding utf8")
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    $source=$source.Replace(".Path.TrimEnd('\')+'\'", ".Path.TrimEnd('/')+'/'")
    $source=$source.Replace("(`$session+'\').StartsWith", "(`$session+'/').StartsWith")
}
$copy=Join-Path $root 'partial.ps1'
[IO.File]::WriteAllText($copy,$source)
Copy-Item (Join-Path $repo 'scripts/vbox_sup_package_identity.ps1') $root
$names=@('RUNNER_TEMP','GITHUB_ACTIONS','GITHUB_REPOSITORY','RUNNER_ENVIRONMENT','RUNNER_OS','PVBOX_FIXED_HELPER_MODE','SystemRoot','GITHUB_SHA')
$old=@{};foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
$env:RUNNER_TEMP=$root;$env:GITHUB_ACTIONS='true';$env:GITHUB_REPOSITORY='zlocorp/Portable-VirtualBox';$env:RUNNER_ENVIRONMENT='github-hosted';$env:RUNNER_OS='Windows';$env:PVBOX_FIXED_HELPER_MODE='CI';$env:SystemRoot=Join-Path $root 'Windows';$env:GITHUB_SHA='fixture'
$pinSys='4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be'
$pinInf='2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4'
function Check([bool]$ok,[string]$message){if(-not $ok){throw "FAIL partial admission: $message"}}
function Get-FixtureController([int]$id){
    $created=[datetime]::FromFileTimeUtc($global:created)
    if($global:fault -eq 'owner'){ $created=$created.AddSeconds(1) }
    $p=[pscustomobject]@{StartTime=$created;MainModule=[pscustomobject]@{FileName=(Join-Path $global:portable 'Portable-VirtualBox.exe')}}
    $p|Add-Member ScriptMethod Dispose {};return $p
}
function Get-CimInstance { param($ClassName,$Filter) if($ClassName -eq 'Win32_SystemDriver'){return [pscustomobject]@{State='Stopped'}} }
function Get-Process { [CmdletBinding()]param() if($global:fault -eq 'busy'){return [pscustomobject]@{ProcessName='VBoxSVC';Id=1}} }
function Get-Service { [CmdletBinding()]param($Name) return [pscustomobject]@{Status=$(if($global:fault -eq 'late-sds' -and $Name -eq 'VBoxSDS' -and [IO.File]::Exists($global:proof)){'Running'}elseif($Name -eq 'VBoxSup' -and $global:phase -in @('Start','Sds')){'Running'}else{'Stopped'})} }
function Get-AuthenticodeSignature { param($LiteralPath) return [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='Oracle'}} }
function Get-FileHash { [CmdletBinding()]param($LiteralPath,$Algorithm)
    if($global:fault -eq 'hash'){throw 'FIXTURE_READ_FAILURE'}
    return [pscustomobject]@{Hash=$(if($LiteralPath.EndsWith('.sys')){$pinSys}else{$pinInf})}
}
function Get-ItemProperty { [CmdletBinding()]param($LiteralPath) if($LiteralPath -like '*VBoxSDS'){return [pscustomobject]@{Type=16;Start=3;ObjectName='LocalSystem';ImagePath=(Join-Path $global:app 'VBoxSDS.exe')}}; return [pscustomobject]@{Type=1;Start=1;ImagePath=$(if($global:fault -eq 'late-driver' -and [IO.File]::Exists($global:proof)){'foreign.sys'}else{'\SystemRoot\System32\drivers\VBoxSup.sys'})} }
function Get-ChildItem { [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath,$Filter,[switch]$Force)
    if($Path -like 'HKLM:*'){[pscustomobject]@{PSChildName='VBoxSup'};if($global:phase -eq 'Sds'){[pscustomobject]@{PSChildName='VBoxSDS'}};return}
    Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -Filter $Filter -Force:$Force
}
function Test-Path { [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath,$PathType)
    $p=if($PSBoundParameters.ContainsKey('LiteralPath')){$LiteralPath}else{$Path}
    if($p -like 'HKLM:*'){return ($p -like '*VBoxSDS' -and $global:phase -eq 'Sds')}
    if($global:fault -eq 'race-proof' -and $p -eq $global:proof){[IO.File]::WriteAllText($global:proof,'race sentinel');return $false}
    $a=@{LiteralPath=$p};if($PSBoundParameters.ContainsKey('PathType')){$a.PathType=$PathType}
    Microsoft.PowerShell.Management\Test-Path @a
}
function Open-FixtureProof($Path,$Mode,$Access,$Share){
    $stream=[IO.File]::Open($Path,$Mode,$Access,$Share)
    if($global:fault -notin @('partial-write','flush','late-receipt')){return $stream}
    $wrapper=[pscustomobject]@{Stream=$stream}
    $wrapper|Add-Member ScriptMethod Write {param($b,$o,$n) if($global:fault -eq 'partial-write'){$this.Stream.Write($b,$o,3);throw 'FIXTURE_PARTIAL_WRITE'};$this.Stream.Write($b,$o,$n)}
    $wrapper|Add-Member ScriptMethod Flush {param($d) if($global:fault -eq 'flush'){throw 'FIXTURE_FLUSH'};$this.Stream.Flush($d);[IO.File]::WriteAllText((Join-Path $global:session 'stage/sup-standalone.json'),'changed after flush')}
    $wrapper|Add-Member ScriptMethod Dispose {$this.Stream.Dispose()}
    return $wrapper
}
function New-Item { [CmdletBinding()]param($Path,$ItemType) if($global:fault -eq 'output' -and $Path -eq $global:out){throw 'FIXTURE_OUTPUT'};Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType }
function Write-FixtureReport {
 [CmdletBinding()]param([Parameter(ValueFromPipeline=$true)]$Value,$LiteralPath,$Encoding)
 process {if($global:fault -eq 'report-write'){throw 'FIXTURE_REPORT_WRITE'};Microsoft.PowerShell.Management\Set-Content -LiteralPath $LiteralPath -Encoding $Encoding -Value $Value}
}
function Start-Process {throw 'UNEXPECTED_NATIVE_LAUNCH'}
function Invoke-ProtectedSds {param($Operation,$TimeoutSeconds);Invoke-ProtectedDriver -Operation $Operation -TimeoutSeconds $TimeoutSeconds}
function Invoke-ProtectedDriver {param($Operation,$TimeoutSeconds)
    $global:effects++
    Check ([IO.File]::Exists($global:proof)) 'proof absent at effect'
    Check ([IO.Directory]::Exists($global:out)) 'output absent at effect'
    Check ([IO.File]::ReadAllText($global:proof) -ceq $global:proofJson) 'proof differs from validated bytes'
    throw 'FIXTURE_EFFECT_FAILURE'
}
function Setup([string]$name,[string]$phase='Stage'){
    $global:phase=$phase
    $global:session=Join-Path $root $name;$global:app=Join-Path $session 'app64';$global:portable=Join-Path $root 'portable';$global:out=Join-Path $session 'cleanup';$global:proof=Join-Path $session 'partial-recovery-quiescent.json'
    foreach($dir in @($app,(Join-Path $session 'stage'),$portable,(Join-Path $env:SystemRoot 'INF'))){[IO.Directory]::CreateDirectory($dir)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $env:SystemRoot 'INF/oem42.inf'),'fixture')
    $global:created=[datetime]::UtcNow.ToFileTimeUtc()
    [ordered]@{schema=1;phase='pre-system-effects';portable_root=$portable;protected_app=$app;controller_pid=4101;controller_created_filetime=$created.ToString()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'prepare-intent.json')
    [ordered]@{experiment='standalone-VBoxSup-primitive-INF-pnputil';oracle_version='7.2.22';pnputil_status='EXITED';pnputil_exit_code=0;package_verified=$true;service_registered=$true;system_driver_matches_package=$true;system_driver_sha256=$pinSys;services_before=@();services_after=@('VBoxSup');service_type=1;service_start=1;published_inf_schema=1;published_inf='oem42.inf';published_inf_was_absent=$true;published_inf_sha256=$pinInf}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'stage/sup-standalone.json')
    if($phase -ne 'Stage') {
        [IO.Directory]::CreateDirectory((Join-Path $session 'start'))|Out-Null
        $failed=$phase -eq 'StartFailedStopped'
        [ordered]@{experiment='owned-standalone-VBoxSup-start';start_status='EXITED';start_exit_code=$(if($failed){5}else{0});driver_running=(-not $failed);initial_status='Stopped';service_status_after=$(if($failed){'Stopped'}else{'Running'});wmi_driver_state=$(if($failed){'Stopped'}else{'Running'});no_other_vbox_services_before=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'start/sup-start-results.json')
    }
    if($phase -eq 'Sds') {
        [ordered]@{schema=1;registered=$true;protected_app=$app;controller_pid=4101;controller_created_filetime=$created.ToString();sds_image=(Join-Path $app 'VBoxSDS.exe')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'sds-registered.json')
    }
    $global:proofJson=[ordered]@{schema=1;experiment='partial-protected-manager-quiescent';portable_root=$portable;protected_app=$app;original_controller_pid=4101;original_controller_created_filetime=$created.ToString();controller_pid=4102;controller_created_filetime=$created.ToString();controller_image=(Join-Path $portable 'Portable-VirtualBox.exe');no_vbox_processes_verified=$true;source_commit='fixture'}|ConvertTo-Json
    $global:argsForCleanup=@{AppDir=$app;SessionDir=$session;PartialRecoveryReport=$proof;OutputDirectory=$out;OriginalControllerCreated=$created;ProspectiveProofJson=$proofJson}
    $global:fault='none';$global:effects=0
}
function Call-Cleanup {try{& $copy @argsForCleanup|Out-Null;return 'UNEXPECTED_SUCCESS'}catch{return $_.Exception.Message}}
try {
    foreach($phase in @('Stage','Start','StartFailedStopped','Sds')) {
    foreach($failure in @('hash','busy','owner')){
        Setup ('pre-'+$phase+'-'+$failure) $phase;$global:fault=$failure
        $message=Call-Cleanup
        Check ($message -notmatch 'parameter cannot be found|parameter name') "prospective parameter unavailable: $message"
        Check (-not [IO.File]::Exists($proof) -and -not [IO.Directory]::Exists($out) -and $effects -eq 0) "$failure admitted"
        $global:fault='none';$message=Call-Cleanup
        Check ($message -match 'FIXTURE_EFFECT_FAILURE' -and $effects -eq 1) "$failure retry did not reach effect: $message"
        $message=Call-Cleanup
        Check ($effects -eq 1 -and [IO.File]::Exists($proof)) "$failure replay after admission"
    }
    }
    foreach($failure in @('partial-write','flush','output')){
        Setup ('post-'+$failure);$global:fault=$failure;$message=Call-Cleanup
        Check ($message -match 'FIXTURE_' -and [IO.File]::Exists($proof) -and $effects -eq 0) "$failure missing retained proof: $message"
        $before=[IO.File]::ReadAllBytes($proof);$global:fault='none';$message=Call-Cleanup
        Check ($effects -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($proof)) -eq [Convert]::ToBase64String($before)) "$failure proof changed or replayed"
    }
    foreach($case in @(@('late-sds','Sds'),@('late-driver','Start'),@('late-receipt','Stage'))) {
        Setup ('after-flush-'+$case[0]) $case[1];$global:fault=$case[0];$message=Call-Cleanup
        Check ([IO.File]::Exists($proof) -and $effects -eq 0) ($case[0]+' admitted effect after state changed: '+$message)
        $bytes=[IO.File]::ReadAllBytes($proof);$global:fault='none';$message=Call-Cleanup
        Check ($effects -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($proof)) -eq [Convert]::ToBase64String($bytes)) ($case[0]+' replayed or changed proof')
    }
    Setup 'legacy-file-proof';[IO.File]::WriteAllText($proof,$proofJson);$argsForCleanup.Remove('ProspectiveProofJson')
    $message=Call-Cleanup;Check ($message -match 'FIXTURE_EFFECT_FAILURE' -and $effects -eq 1) "legacy file-proof flow changed: $message"
    $message=Call-Cleanup;Check ($effects -eq 1 -and [IO.File]::ReadAllText($proof) -ceq $proofJson) 'legacy proof replayed or changed'
    Setup 'legacy-bad-proof';[IO.File]::WriteAllText($proof,'{}');$argsForCleanup.Remove('ProspectiveProofJson')
    $message=Call-Cleanup;Check ($effects -eq 0 -and -not [IO.Directory]::Exists($out) -and [IO.File]::ReadAllText($proof) -ceq '{}') 'invalid legacy proof admitted or changed'
    Setup 'failed-report-write';$global:fault='report-write';$message=Call-Cleanup
    Check ($message -match 'FIXTURE_EFFECT_FAILURE' -and $message -match 'FIXTURE_REPORT_WRITE' -and $effects -eq 1 -and [IO.File]::Exists($proof)) ('report write masked effect failure: '+$message)
    $bytes=[IO.File]::ReadAllBytes($proof);$global:fault='none';$message=Call-Cleanup
    Check ($effects -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($proof)) -eq [Convert]::ToBase64String($bytes)) 'report write allowed replay or changed proof'
    Setup 'race-proof';$global:fault='race-proof';$message=Call-Cleanup
    Check ($effects -eq 0 -and [IO.File]::ReadAllText($proof) -ceq 'race sentinel') 'CreateNew overwrote racing proof'
    Setup 'sds-without-marker';[IO.File]::WriteAllText((Join-Path $session 'sds-register.stdout.txt'),'evidence');$message=Call-Cleanup
    Check ($message -match 'SDS may have registered' -and $effects -eq 0 -and -not [IO.File]::Exists($proof)) 'ambiguous SDS was admitted'
    Check ([IO.File]::ReadAllText((Join-Path $session 'sds-register.stdout.txt')) -ceq 'evidence') 'SDS evidence altered'
    Setup 'foreign-proof';$bad=$proofJson|ConvertFrom-Json;$bad.protected_app=Join-Path $root 'foreign';$argsForCleanup.ProspectiveProofJson=$bad|ConvertTo-Json
    $message=Call-Cleanup;Check ($message -match 'ownership proof mismatch' -and $effects -eq 0 -and -not [IO.File]::Exists($proof)) 'foreign proof admitted'
    Setup 'bad-json';$argsForCleanup.ProspectiveProofJson='{';$message=Call-Cleanup
    Check ($effects -eq 0 -and -not [IO.File]::Exists($proof)) 'malformed proof admitted'
    Setup 'tamper-stage';$stagePath=Join-Path $session 'stage/sup-standalone.json';$stage=Get-Content -LiteralPath $stagePath -Raw|ConvertFrom-Json
    $stage.system_driver_sha256='bad';$stage|ConvertTo-Json|Set-Content -LiteralPath $stagePath
    $message=Call-Cleanup;Check ($message -match 'No exact exclusive' -and $effects -eq 0 -and -not [IO.File]::Exists($proof)) 'tampered stage admitted'
    foreach($marker in @('quiescent-session.json','recovery-quiescent.json','partial-recovery-quiescent.json','payload-cleanup.json','payload-removed.json','cleanup')){
        Setup ('existing-'+$marker);$target=Join-Path $session $marker
        if($marker -eq 'cleanup'){[IO.Directory]::CreateDirectory($target)|Out-Null}else{[IO.File]::WriteAllText($target,'sentinel')}
        $message=Call-Cleanup;Check ($effects -eq 0) "existing $marker admitted"
        if($marker -ne 'cleanup'){Check ([IO.File]::ReadAllText($target) -ceq 'sentinel') "existing $marker altered"}
    }
    Write-Host 'PARTIAL_CLEANUP_ADMISSION_PASS'
} finally {
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$old[$name])}
    Remove-Item -LiteralPath $root -Recurse -Force
}
