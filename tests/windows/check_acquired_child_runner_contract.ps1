# Execute the actual production test-runner tail, with a closed synthetic command.
# This tests PowerShell control/exit propagation, not native child behaviour.
param([ValidateSet('pass','normal-status','normal-marker','before-status','before-marker','after-status','after-marker')][string]$Scenario='pass')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tests/windows/check_fixed_effect_acquired_child.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Runner parse error' }
$statements=@($ast.EndBlock.Statements)
$loops=@($statements | Where-Object { $_ -is [Management.Automation.Language.ForEachStatementAst] })
if ($loops.Count -ne 1) { throw 'Expected one top-level runner case loop' }
$index=[Array]::IndexOf($statements,$loops[0])
$tail=[scriptblock]::Create((($statements[$index..($statements.Count-1)] | ForEach-Object { $_.Extent.Text }) -join "`n"))
$script:fixtureCalls=0
function Invoke-ClosedRunnerFixture([string]$Mode='') {
    $script:fixtureCalls++
    if ($Mode -eq '') {
        $global:LASTEXITCODE=0
        if ($Scenario -eq 'normal-status') { $global:LASTEXITCODE=2 }
        if ($Scenario -eq 'normal-marker') { 'WRONG_NORMAL_MARKER' }
        else { 'ACQUIRED_CHILD_RETENTION_PASS assertions=56 synthetic=true' }
    } elseif ($Mode -in @('--fail-before-adoption','--fail-after-retention')) {
        $phase=if ($Mode -eq '--fail-before-adoption') { 'before' } else { 'after' }
        $global:LASTEXITCODE=1
        if ($Scenario -eq ($phase+'-status')) { $global:LASTEXITCODE=0 }
        if ($Scenario -eq ($phase+'-marker')) { 'WRONG_NEGATIVE_MARKER' }
        else { 'ACQUIRED_CHILD_EXPECTED_FAILURE mode='+$Mode+' child_exit=23 natural_exit=true' }
    } else { throw 'Unexpected closed fixture mode' }
}
function Invoke-RunnerNested {
    $exe='Invoke-ClosedRunnerFixture'
    . $tail
    if ($script:fixtureCalls -ne 3) { throw 'Actual runner did not validate all three cases' }
    Write-Host 'RUNNER_NESTED_RETURNED'
}
try {
    Invoke-RunnerNested
    # Match GitHub's powershell wrapper: a successful script must not leave the
    # last expected-negative native status as the final step's process exit.
    if (Test-Path variable:LASTEXITCODE) { exit $LASTEXITCODE }
    exit 0
} catch {
    Write-Host ('RUNNER_CONTRACT_REJECTED scenario='+$Scenario)
    exit 91
}
