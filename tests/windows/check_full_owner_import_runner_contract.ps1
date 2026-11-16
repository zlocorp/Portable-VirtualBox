# Actual runner tail with a closed synthetic command; not native fault evidence.
param([ValidateSet('pass','wait-normal-status','wait-normal-marker','wait-negative-status','wait-negative-marker','false-normal-status','false-normal-marker','false-negative-status','false-negative-marker')][string]$Scenario='pass')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'check_full_owner_import_faults.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Runner parse failure' }
$statements=@($ast.EndBlock.Statements);$loops=@($statements | Where-Object { $_ -is [Management.Automation.Language.ForEachStatementAst] })
if ($loops.Count -ne 1) { throw 'Expected one top-level case loop' }
$index=[Array]::IndexOf($statements,$loops[0])
$tail=[scriptblock]::Create((($statements[$index..($statements.Count-1)] | ForEach-Object { $_.Extent.Text }) -join "`n"))
$script:count=0
function Invoke-ClosedCase([string]$Mode,[string]$Negative='') {
    $script:count++
    if ($Mode -notin @('wait-failed','false-outputs') -or $Negative -notin @('','--fail-after-retention')) { throw 'Unknown closed case' }
    $family=if($Mode -eq 'wait-failed'){'wait'}else{'false'}
    $phase=if($Negative){'negative'}else{'normal'}
    $global:LASTEXITCODE=if($Negative){1}else{0}
    if ($Scenario -eq ($family+'-'+$phase+'-status')) {$global:LASTEXITCODE=9}
    if ($Scenario -eq ($family+'-'+$phase+'-marker')) {'FULL_OWNER_FAULT_PASS mode='+$Mode+' incomplete';return}
    if ($Negative) {'FULL_OWNER_FAULT_EXPECTED_FAILURE mode='+$Mode+' child_exit=23 natural_exit=true'}
    else {'FULL_OWNER_FAULT_PASS mode='+$Mode+' checks=20 real_creates=1 original_closes=0 owner_exit_queries=0 run_returned=false run_threw=false run_finally=false fixture_mutex_reacquired=false child_exit=23 natural_exit=true instrumented_imports=true production_bodies_unchanged=true'}
}
function Nested {
    $exe='Invoke-ClosedCase';. $tail
    if ($script:count -ne 4) { throw 'Did not check four isolated hosts' }
    Write-Host 'FULL_OWNER_RUNNER_NESTED_RETURNED'
}
try { Nested;if(Test-Path variable:LASTEXITCODE){exit $LASTEXITCODE};exit 0 }
catch {Write-Host ('FULL_OWNER_RUNNER_REJECTED '+$Scenario);exit 91}
