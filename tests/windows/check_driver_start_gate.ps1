# Executes the real activation/Prepare blocks with Windows effects replaced at
# their boundaries. Never invokes SCM, registry writes, SDS or Oracle binaries.
param([string]$Repository, [ValidateSet('Start','Privileged','Manager')][string]$Target)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$env:GITHUB_STEP_SUMMARY=''
function Parse-Script([string]$Name) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository ('scripts/'+$Name)),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    return $ast
}
function Assert-True($Value,[string]$Message) { if (-not $Value) { throw $Message } }
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-start-gate-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    if ($Target -eq 'Start') {
        $ast=Parse-Script 'vbox_sup_start_owned.ps1'
        # The preceding code proves exclusive staging, signature and initially
        # stopped state. Exercise every real statement from native launch on.
        $begin=@($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$proc'
        })[0].Extent.StartOffset
        $body=[scriptblock]::Create($ast.Extent.Text.Substring($begin))
        foreach ($case in @('Success','ExitFailure','ExitFailureStopped','Stopped','MissingService','MissingWmi','WmiStopped','Pending','TimeoutRunning','LaunchError')) {
            $out=Join-Path $testRoot $case
            New-Item -ItemType Directory -Path $out | Out-Null
            $sc='never-executed'; $stdout=Join-Path $out 'stdout'; $stderr=Join-Path $out 'stderr'; $TimeoutSeconds=5
            function Start-Process {
                if ($case -eq 'LaunchError') { throw 'simulated launch failure' }
                $p=[pscustomobject]@{Handle=[IntPtr]1;ExitCode=$(if ($case -in @('ExitFailure','ExitFailureStopped')) { 5 } else { 0 })}
                $p | Add-Member ScriptMethod WaitForExit { param($ms) if ($null -ne $ms) { return $case -ne 'TimeoutRunning' } }
                $p | Add-Member ScriptMethod Dispose {}
                return $p
            }
            function Get-Service {
                if ($case -eq 'MissingService') { return $null }
                return [pscustomobject]@{Status=$(if ($case -in @('Stopped','ExitFailureStopped')) { 'Stopped' } elseif ($case -eq 'Pending') { 'StartPending' } else { 'Running' })}
            }
            function Get-CimInstance {
                if ($case -eq 'MissingWmi') { return $null }
                return [pscustomobject]@{State=$(if ($case -in @('WmiStopped','ExitFailureStopped')) { 'Stopped' } else { 'Running' })}
            }
            function Start-Sleep {}
            $failed=$false
            try { & $body } catch { $failed=$true }
            $report=Get-Content -LiteralPath (Join-Path $out 'sup-start-results.json') -Raw | ConvertFrom-Json
            Assert-True ($report.experiment -eq 'owned-standalone-VBoxSup-start') "$case lost diagnostic evidence"
            Assert-True ($failed -eq ($case -ne 'Success')) "$case activation returned success without confirmed driver start"
            if ($case -eq 'TimeoutRunning') { Assert-True ($report.start_status -eq 'TIMEOUT') 'Late completion became success' }
        }
    } else {
        $name=if ($Target -eq 'Privileged') { 'privileged_session_worker.ps1' } else { 'manager_session_worker.ps1' }
        $ast=Parse-Script $name
        $prepare=$ast.Find({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq "`$Action -eq 'Prepare'"},$true)
        Assert-True ($null -ne $prepare) 'Prepare branch not found'
        $block=$prepare.Clauses[0].Item2.Extent.Text
        $fixture=Join-Path $testRoot 'effects'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $body=Join-Path $fixture 'prepare.ps1'
        Set-Content -LiteralPath $body -Value $block.Substring(1,$block.Length-2)
        Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_standalone.ps1') -Value 'param($AppDir,$OutputDirectory)'
        Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_start_owned.ps1') -Value @'
param($StandaloneReport,$OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
if ($case -ne 'MissingReceipt') {
    $fixtureReceipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'sup-start-results.json')
}
'@
        foreach ($case in @('Success','ExitFailure','Timeout','Stopped','WrongExperiment','MissingReceipt','WrongInitial','ForeignServices','WmiStopped','MissingField','StringTrue')) {
            $session=Join-Path $testRoot $case; $root=$session; $app=Join-Path $session 'app64'
            $PSScriptRoot=$fixture
            $TestBreakAfter='None'; $ControllerPid=123; $ControllerCreated=456L; $controllerImage='controller.exe'; $parentId=123; $parentStart='456'; $parentPath='controller.exe'
            if ($Target -eq 'Privileged') {
                New-Item -ItemType Directory -Path $session | Out-Null
                Set-Content -LiteralPath (Join-Path $session 'prepare-intent.json') -Value '{}'
            }
            $fixtureReceipt=@{experiment='owned-standalone-VBoxSup-start';start_status='EXITED';start_exit_code=0;driver_running=$true;initial_status='Stopped';service_status_after='Running';wmi_driver_state='Running';no_other_vbox_services_before=$true}
            switch ($case) {
                'ExitFailure' { $fixtureReceipt.start_exit_code=5 }
                'Timeout' { $fixtureReceipt.start_status='TIMEOUT' }
                'Stopped' { $fixtureReceipt.driver_running=$false; $fixtureReceipt.service_status_after='Stopped' }
                'WrongExperiment' { $fixtureReceipt.experiment='unrelated' }
                'WrongInitial' { $fixtureReceipt.initial_status='Running' }
                'ForeignServices' { $fixtureReceipt.no_other_vbox_services_before=$false }
                'WmiStopped' { $fixtureReceipt.wmi_driver_state='Stopped' }
                'MissingField' { $fixtureReceipt.Remove('driver_running') }
                'StringTrue' { $fixtureReceipt.driver_running='true' }
            }
            $effects=@{Calls=0}
            function Check-App {}
            function Run-Sds { $effects.Calls++ }
            function Run-Oracle { $effects.Calls++ }
            function Get-ItemProperty { return [pscustomobject]@{ImagePath=(Join-Path $app 'VBoxSDS.exe');Type=16;Start=3;ObjectName='LocalSystem'} }
            # Only the HKLM existence probe is synthetic. Local receipt reads
            # and writes use the real filesystem and ConvertFrom-Json.
            function Test-Path {
                param($LiteralPath,$Path,$PathType)
                $value=if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($value -like 'HKLM:*') { return $false }
                return Microsoft.PowerShell.Management\Test-Path -LiteralPath $value
            }
            $failed=$false
            try { & $body } catch { $failed=$true; if ($case -eq 'Success') { throw } }
            Assert-True ($failed -eq ($case -ne 'Success')) "$Target/$case preparation did not fail closed"
            Assert-True ($effects.Calls -eq $(if ($case -eq 'Success') { 1 } else { 0 })) "$Target/$case ran downstream effects before confirmation"
            Assert-True ((Test-Path -LiteralPath (Join-Path $session 'session.json')) -eq ($case -eq 'Success')) "$Target/$case emitted invalid prepared receipt"
            if ($case -ne 'Success') { Assert-True (-not (Test-Path -LiteralPath (Join-Path $session 'sds-registered.json'))) "$Target/$case emitted SDS receipt" }
        }
    }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
Write-Host "PASS $Target driver start gate"
