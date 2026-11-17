# Execute production cleanup with OS observations/effects replaced by fixture functions.
# Process.GetProcessById and File.Open are replaced at their AST call sites.
# File.Open returns a real stream normally; fault wrappers retain its actual bytes/disposal.
# All validation, marker creation, persisted proof, and control flow are production code.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-preflight-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$global:checks=0
function Check([bool]$Pass,[string]$Name) { if (-not $Pass) { throw "FAIL preflight: $Name" }; $global:checks++ }
$sourcePath=Join-Path $repo 'scripts/vbox_sup_cleanup.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Cleanup parse failed' }
$source=[IO.File]::ReadAllText($sourcePath)
$unix=[Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT
$calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Static -and $n.Expression.Extent.Text -eq '[Diagnostics.Process]' -and $n.Member.Extent.Text -eq 'GetProcessById'},$true))
Check ($calls.Count -ge 2) 'native dependency call sites found'
$openCalls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Static -and $n.Expression.Extent.Text -eq '[IO.File]' -and $n.Member.Extent.Text -eq 'Open'},$true))
Check ($openCalls.Count -eq 1) 'single proof stream creation site found'
foreach ($call in (@($calls)+@($openCalls) | Sort-Object {$_.Extent.StartOffset} -Descending)) {
    if($call.Member.Extent.Text -eq 'Open'){
        $replacement='(Open-FixtureProof '+(($call.Arguments | ForEach-Object {'('+ $_.Extent.Text +')'}) -join ' ')+')'
    }else{$replacement='(Get-FixtureController -ProcessId ('+$call.Arguments[0].Extent.Text+'))'}
    $source=$source.Substring(0,$call.Extent.StartOffset)+$replacement+$source.Substring($call.Extent.EndOffset)
}
# Unix portability adapter changes only the native separator observation.
# The mandatory Windows fixture executes the unchanged prefix expression.
if($unix){$source=$source.Replace(".Path.TrimEnd('\')+'\'",".Path.TrimEnd('/')+'/'")}
$scriptCopy=Join-Path $root 'vbox_sup_cleanup.ps1'
[IO.File]::WriteAllText($scriptCopy,$source)
Copy-Item (Join-Path $repo 'scripts/vbox_sup_package_identity.ps1') $root
$envNames=@('RUNNER_TEMP','GITHUB_ACTIONS','GITHUB_REPOSITORY','RUNNER_ENVIRONMENT','RUNNER_OS','PVBOX_FIXED_HELPER_MODE','SystemRoot')
$old=@{};foreach($name in $envNames){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
$env:RUNNER_TEMP=$root;$env:GITHUB_ACTIONS='true';$env:GITHUB_REPOSITORY='zlocorp/Portable-VirtualBox'
$env:RUNNER_ENVIRONMENT='github-hosted';$env:RUNNER_OS='Windows';$env:PVBOX_FIXED_HELPER_MODE='CI';$env:SystemRoot=Join-Path $root 'Windows'
$pinSys='4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be'
$pinInf='2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4'
function Get-FixtureController([int]$ProcessId) {
    $global:controllerReads++
    $created=[datetime]::FromFileTimeUtc($global:created)
    if(($global:fault -eq 'late-controller' -and $global:controllerReads -gt 1) -or ($global:fault -eq 'post-controller' -and [IO.File]::Exists($global:proofPath))){$created=$created.AddSeconds(1)}
    $value=[pscustomobject]@{StartTime=$created;MainModule=[pscustomobject]@{FileName=(Join-Path $global:portable 'Portable-VirtualBox.exe')}}
    $value | Add-Member ScriptMethod Dispose { }
    return $value
}
function Get-CimInstance { param($ClassName,$Filter) if($global:fault -eq 'old-live'){[pscustomobject]@{ProcessId=4101}} }
function Get-Process { [CmdletBinding()] param() if($global:fault -eq 'busy'){[pscustomobject]@{ProcessName='VirtualBoxVM';Id=77}} }
function Start-Sleep { param($Seconds) }
function Get-Service { [CmdletBinding()] param($Name) [pscustomobject]@{Status=$(if($global:fault -eq 'running'){'Running'}else{'Stopped'})} }
function Get-AuthenticodeSignature { param($LiteralPath) [pscustomobject]@{Status=$(if($global:fault -eq 'signature' -and $LiteralPath.EndsWith('VBoxSDS.exe')){'NotSigned'}else{'Valid'});SignerCertificate=[pscustomobject]@{Subject='Oracle'}} }
function Get-FileHash { [CmdletBinding()]param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=$(if($LiteralPath.EndsWith('.sys')){$pinSys}else{$pinInf})} }
function Get-ItemProperty {
    [CmdletBinding()]param($LiteralPath)
    if($global:fault -eq 'query'){throw [UnauthorizedAccessException]::new('fixture query refused')}
    [pscustomobject]@{ImagePath=$(if($global:fault -eq 'config'){'foreign.exe'}else{Join-Path $global:app 'VBoxSDS.exe'});Type=16;Start=3;ObjectName='LocalSystem'}
}
function Get-ChildItem {
    [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath,$Filter,[switch]$Force)
    if($Path -like 'HKLM:*'){
        [pscustomobject]@{PSChildName='VBoxSup'}
        if($global:fault -eq 'partial-services'){throw [UnauthorizedAccessException]::new('fixture partial service enumeration')}
        [pscustomobject]@{PSChildName='VBoxSDS'}
        if($global:fault -eq 'foreign-service'){[pscustomobject]@{PSChildName='VBoxForeign'}}
        return
    }
    Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -Filter $Filter -Force:$Force
}
function Test-Path {
    [CmdletBinding()]param([Parameter(Position=0)]$Path,$LiteralPath,$PathType)
    $target=if($PSBoundParameters.ContainsKey('LiteralPath')){$LiteralPath}else{$Path}
    if($target -like 'HKLM:*'){return $false}
    if($global:fault -eq 'race-proof' -and $target -eq $global:proofPath){
        $global:proofProbes++
        if($global:proofProbes -eq 2){[IO.File]::WriteAllText($global:proofPath,'race sentinel');return $false}
    }
    $params=@{LiteralPath=$target};if($PSBoundParameters.ContainsKey('PathType')){$params.PathType=$PathType}
    Microsoft.PowerShell.Management\Test-Path @params
}
function Open-FixtureProof($Path,$Mode,$Access,$Share) {
    $stream=[IO.File]::Open($Path,$Mode,$Access,$Share)
    if($global:fault -notin @('partial-write','flush')){return $stream}
    $wrapper=[pscustomobject]@{Stream=$stream}
    $wrapper | Add-Member ScriptMethod Write {
        param($Bytes,$Offset,$Count)
        if($global:fault -eq 'partial-write'){
            $this.Stream.Write($Bytes,$Offset,7)
            throw 'FIXTURE_PARTIAL_WRITE_FAILURE'
        }
        $this.Stream.Write($Bytes,$Offset,$Count)
    }
    $wrapper | Add-Member ScriptMethod Flush {
        param($Durable)
        throw 'FIXTURE_FLUSH_FAILURE'
    }
    $wrapper | Add-Member ScriptMethod Dispose {
        $this.Stream.Dispose()
        $global:proofDisposed=$true
    }
    return $wrapper
}
function New-Item {
    [CmdletBinding()]param($ItemType,$Path)
    if($global:fault -eq 'output-directory' -and $Path -eq $global:outPath){throw 'FIXTURE_OUTPUT_DIRECTORY_FAILURE'}
    Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path
}
function Start-Process { throw 'UNEXPECTED_NATIVE_LAUNCH' }
function Invoke-ProtectedDriver { throw 'UNEXPECTED_DRIVER_EFFECT' }
function Invoke-ProtectedSds {
    param($Operation,$TimeoutSeconds)
    $global:effects++
    Check ([IO.File]::Exists($global:proofPath)) 'proof exists before first effect'
    Check ([IO.Directory]::Exists($global:outPath)) 'output exists before first effect'
    Check ([IO.File]::ReadAllText($global:proofPath) -ceq $global:proofJson) 'exact validated JSON persisted'
    throw 'FIXTURE_FIRST_EFFECT_FAILURE'
}
function Setup([string]$Name,[bool]$Recovery=$false) {
    $global:session=Join-Path $root $Name;$global:app=Join-Path $session 'app64';$global:portable=Join-Path $root 'portable'
    $global:outPath=Join-Path $session 'cleanup';$global:proofPath=Join-Path $session $(if($Recovery){'recovery-quiescent.json'}else{'quiescent-session.json'})
    foreach($dir in @($app,(Join-Path $session 'stage'),(Join-Path $session 'start'),$portable,(Join-Path $env:SystemRoot 'INF'))){[IO.Directory]::CreateDirectory($dir)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $env:SystemRoot 'INF/oem42.inf'),'fixture only')
    $stagePath=Join-Path $session 'stage/sup-standalone.json';$startPath=Join-Path $session 'start/sup-start-results.json'
    [ordered]@{experiment='standalone-VBoxSup-primitive-INF-pnputil';oracle_version='7.2.22';pnputil_status='EXITED';pnputil_exit_code=0;package_verified=$true;system_driver_matches_package=$true;system_driver_sha256=$pinSys;services_before=@();services_after=@('VBoxSup');service_type=1;service_start=1;published_inf_schema=1;published_inf='oem42.inf';published_inf_was_absent=$true;published_inf_sha256=$pinInf}|ConvertTo-Json|Set-Content -LiteralPath $stagePath
    @{experiment='owned-standalone-VBoxSup-start';driver_running=$true;start_exit_code=0}|ConvertTo-Json|Set-Content -LiteralPath $startPath
    $global:created=[datetime]::UtcNow.ToFileTimeUtc()
    $proof=[ordered]@{experiment=$(if($Recovery){'orphan-manager-quiescent'}else{'privilege-separated-manager-quiescent'});portable_root=$portable;protected_app=$app;stage_report=$stagePath;driver_start_report=$startPath;controller_pid=4102;controller_created_filetime=$created.ToString();controller_image=(Join-Path $portable 'Portable-VirtualBox.exe');no_vbox_processes_verified=$true;source_commit='fixture'}
    if($Recovery){$proof.original_controller_pid=4101;$proof.original_controller_created_filetime=$created.ToString();@{schema=1;prepared=$true;controller_pid=4101;controller_created_filetime=$created.ToString();controller_image=$proof.controller_image;portable_root=$portable;protected_app=$app}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json')}
    $global:proofJson=$proof|ConvertTo-Json
    $global:argsForCleanup=@{AppDir=$app;StandaloneReport=$stagePath;DriverStartReport=$startPath;OutputDirectory=$outPath;ProspectiveProofJson=$proofJson}
    if($Recovery){$argsForCleanup.RecoveryReport=$proofPath}else{$argsForCleanup.PrivilegedReport=$proofPath}
    $global:effects=0;$global:controllerReads=0;$global:proofProbes=0;$global:proofDisposed=$false;$global:fault='none'
}
function Call-Cleanup {
    $global:controllerReads=0
    try { & $scriptCopy @argsForCleanup | Out-Null; return 'UNEXPECTED_SUCCESS' } catch { return $_.Exception.Message }
}
try {
    foreach($recovery in @($false,$true)){
      foreach($failure in @('signature','query','config','busy','running','late-controller','missing-stage','invalid-inf','invalid-inf-hash','foreign-app','partial-services','foreign-service')){
        Setup ($failure+'-'+$recovery) $recovery;$global:fault=$failure
        $stageBefore=[IO.File]::ReadAllText($argsForCleanup.StandaloneReport)
        switch($failure){
            'missing-stage' {[IO.File]::Delete($argsForCleanup.StandaloneReport)}
            'invalid-inf' {
                $badStage=$stageBefore|ConvertFrom-Json;$badStage.published_inf='../foreign.inf'
                [IO.File]::WriteAllText($argsForCleanup.StandaloneReport,($badStage|ConvertTo-Json))
            }
            'invalid-inf-hash' {
                $badStage=$stageBefore|ConvertFrom-Json;$badStage.published_inf_sha256=('0'*64)
                [IO.File]::WriteAllText($argsForCleanup.StandaloneReport,($badStage|ConvertTo-Json))
            }
            'foreign-app' {
                $badProof=$proofJson|ConvertFrom-Json;$badProof.protected_app=Join-Path $session 'foreign-app'
                $argsForCleanup.ProspectiveProofJson=$badProof|ConvertTo-Json
            }
        }
        $errorText=Call-Cleanup
        Check ($errorText -ne 'UNEXPECTED_SUCCESS') "$failure refused"
        Check ($effects -eq 0) "$failure no native effects"
        Check (-not [IO.File]::Exists($proofPath)) "$failure no proof"
        Check (-not [IO.Directory]::Exists($outPath)) "$failure no output"
        [IO.File]::WriteAllText($argsForCleanup.StandaloneReport,$stageBefore)
        $argsForCleanup.ProspectiveProofJson=$proofJson
        $global:fault='none';$errorText=Call-Cleanup
        Check ($errorText -like '*FIXTURE_FIRST_EFFECT_FAILURE*') "$failure retry reaches first effect: $errorText"
        Check ($effects -eq 1) "$failure exactly one first effect"
        $proofBefore=[IO.File]::ReadAllBytes($proofPath);$errorText=Call-Cleanup
        Check ($effects -eq 1) "$failure post-admission retry blocked"
        Check ([Convert]::ToBase64String($proofBefore) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($proofPath))) "$failure marker never overwritten"
      }
    }
    foreach($marker in @('quiescent-session.json','recovery-quiescent.json','partial-recovery-quiescent.json','payload-cleanup.json','payload-removed.json','cleanup')){
      Setup ('marker-'+$marker)
      $path=Join-Path $session $marker
      if($marker -eq 'cleanup'){[IO.Directory]::CreateDirectory($path)|Out-Null}else{[IO.File]::WriteAllText($path,'sentinel')}
      $errorText=Call-Cleanup
      Check ($effects -eq 0 -and $errorText -ne 'UNEXPECTED_SUCCESS') "$marker blocks effect"
      if($marker -ne 'cleanup'){Check ([IO.File]::ReadAllText($path) -ceq 'sentinel') "$marker retained"}
    }
    Setup 'wrong-proof-path';$argsForCleanup.PrivilegedReport=Join-Path $session 'other.json'
    $errorText=Call-Cleanup;Check ($effects -eq 0 -and -not [IO.Directory]::Exists($outPath)) 'noncanonical proof path rejected'
    foreach($failure in @('post-controller','race-proof')){
      Setup $failure;$global:fault=$failure;$errorText=Call-Cleanup
      Check ($effects -eq 0 -and $errorText -ne 'UNEXPECTED_SUCCESS') "$failure no effect"
      Check ([IO.File]::Exists($proofPath)) "$failure admission marker retained"
      $before=[IO.File]::ReadAllText($proofPath);$global:fault='none';$errorText=Call-Cleanup
      Check ($effects -eq 0 -and [IO.File]::ReadAllText($proofPath) -ceq $before) "$failure repeat blocked without overwrite"
    }
    foreach($recovery in @($false,$true)){
      foreach($failure in @('partial-write','flush','output-directory')){
        Setup ($failure+'-'+$recovery) $recovery;$global:fault=$failure
        $errorText=Call-Cleanup
        $expectedError=@{'partial-write'='FIXTURE_PARTIAL_WRITE_FAILURE';'flush'='FIXTURE_FLUSH_FAILURE';'output-directory'='FIXTURE_OUTPUT_DIRECTORY_FAILURE'}[$failure]
        Check ($errorText -like ('*'+$expectedError+'*')) "$failure expected failure: $errorText"
        Check ($effects -eq 0) "$failure no effects"
        Check ([IO.File]::Exists($proofPath)) "$failure proof retained"
        Check (-not [IO.Directory]::Exists($outPath)) "$failure no output directory"
        $before=[IO.File]::ReadAllBytes($proofPath)
        $expected=[Text.Encoding]::UTF8.GetBytes($proofJson)
        if($failure -eq 'partial-write'){$expected=[byte[]]$expected[0..6]}
        Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String($expected)) "$failure exact partial/full proof retained"
        if($failure -ne 'output-directory'){Check $proofDisposed "$failure stream disposed after failure"}
        $global:fault='none';$errorText=Call-Cleanup
        Check ($errorText -ne 'UNEXPECTED_SUCCESS' -and $effects -eq 0) "$failure repeat blocked"
        Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($proofPath)) -ceq [Convert]::ToBase64String($before)) "$failure proof immutable after repeat"
        Check (-not [IO.Directory]::Exists($outPath)) "$failure repeat creates no output directory"
      }
    }
    Setup 'old-live' $true;$global:fault='old-live';$errorText=Call-Cleanup
    Check ($effects -eq 0 -and -not [IO.File]::Exists($proofPath)) 'live original recovery owner rejected'
    foreach($badJson in @('null','[]','true','42','{broken}',('x'*16385))){
      Setup ('bad-json-'+[guid]::NewGuid().ToString('N'));$argsForCleanup.ProspectiveProofJson=$badJson
      $errorText=Call-Cleanup
      Check ($effects -eq 0 -and -not [IO.File]::Exists($proofPath) -and -not [IO.Directory]::Exists($outPath)) 'invalid JSON refused without admission'
    }
    Setup 'legacy';[IO.File]::WriteAllText($proofPath,$proofJson);$argsForCleanup.Remove('ProspectiveProofJson')
    $errorText=Call-Cleanup;Check ($errorText -like '*FIXTURE_FIRST_EFFECT_FAILURE*' -and $effects -eq 1) 'legacy file-proof path retained'
    Write-Host "CLEANUP_PREFLIGHT_ADMISSION_PASS checks=$checks"
} finally {
    foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$old[$name])}
    Remove-Item -LiteralPath $root -Recurse -Force
}
