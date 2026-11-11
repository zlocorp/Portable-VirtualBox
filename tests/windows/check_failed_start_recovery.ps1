# Real partial-cleanup decision and mutation sequence, synthetic OS boundaries.
# Earlier owner/signature/INF/intent checks are outside the selected block and
# remain covered by the separate exact ownership tests and isolated Windows CI.
param([string]$Repository)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'scripts/vbox_sup_partial_cleanup.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$begin=@($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$startExists'
})[0].Extent.StartOffset
$body=[scriptblock]::Create($ast.Extent.Text.Substring($begin))
function Assert-True($Value,[string]$Message) { if (-not $Value) { throw $Message } }
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-failed-start-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    foreach ($case in @('Stage','Started','FailedStopped','LateWmiRunning','WmiQueryError','Timeout','LaunchError','MissingReport','MissingWmi','WmiRunning','ScmRunning','ZeroExit','NegativeExit','StringExit','MissingExit','RunningReceipt','WmiReceiptRunning','SdsMarker','SdsLog','ForeignService','ChangedHash','UnknownOwner','MissingBoolean','StringBoolean')) {
        $session=Join-Path $testRoot $case; $app=Join-Path $session 'app64'
        New-Item -ItemType Directory -Path (Join-Path $session 'start') -Force | Out-Null
        $startPath=Join-Path $session 'start/sup-start-results.json'
        $sdsMarkerPath=Join-Path $session 'sds-registered.json'; $outPath=Join-Path $session 'cleanup'
        $sys=Join-Path $session 'VBoxSup.sys'; $installedInf=Join-Path $session 'oem7.inf'; $published='oem7.inf'
        Set-Content -LiteralPath $sys -Value 'owned driver'; Set-Content -LiteralPath $installedInf -Value 'owned inf'
        $pinSys='sys-hash'; $pinInf='inf-hash'; $TimeoutSeconds=10; $env:SystemRoot=$session
        $receipt=@{experiment='owned-standalone-VBoxSup-start';start_status='EXITED';start_exit_code=5;initial_status='Stopped';service_status_after='Stopped';wmi_driver_state='Stopped';driver_running=$false;no_other_vbox_services_before=$true}
        switch ($case) {
            'Started' { $receipt.start_exit_code=0; $receipt.service_status_after='Running'; $receipt.wmi_driver_state='Running'; $receipt.driver_running=$true }
            'Timeout' { $receipt.start_status='TIMEOUT' }
            'LaunchError' { $receipt.start_status='LAUNCH_ERROR'; $receipt.start_exit_code=$null }
            'ZeroExit' { $receipt.start_exit_code=0 }
            'NegativeExit' { $receipt.start_exit_code=-1 }
            'StringExit' { $receipt.start_exit_code='5' }
            'MissingExit' { $receipt.Remove('start_exit_code') }
            'RunningReceipt' { $receipt.service_status_after='Running';$receipt.driver_running=$true }
            'WmiReceiptRunning' { $receipt.wmi_driver_state='Running' }
            'SdsMarker' { Set-Content -LiteralPath $sdsMarkerPath -Value '{}' }
            'SdsLog' { Set-Content -LiteralPath (Join-Path $session 'sds-register.stdout.txt') -Value '' }
            'MissingBoolean' { $receipt.Remove('driver_running') }
            'StringBoolean' { $receipt.driver_running='false' }
        }
        if ($case -notin @('MissingReport','Stage')) { $receipt | ConvertTo-Json | Set-Content -LiteralPath $startPath }
        if ($case -eq 'Stage') { Remove-Item -LiteralPath (Join-Path $session 'start') -Recurse }
        $effects=@{Stopped=($case -ne 'Started');WmiCalls=0;Commands=[Collections.Generic.List[string]]::new()}
        function Get-VBoxNames {
            if ($case -eq 'ForeignService') { return @('VBoxSup','VBoxForeign') }
            if (Microsoft.PowerShell.Management\Test-Path -LiteralPath $sys) { return @('VBoxSup') }
            return @()
        }
        function Get-VBoxProcesses { return @() }
        function Require-Quiescent { if ($case -eq 'UnknownOwner') { throw 'unknown owner' } }
        function Get-Service { return [pscustomobject]@{Status=$(if ($case -eq 'ScmRunning' -or -not $effects.Stopped) { 'Running' } else { 'Stopped' })} }
        function Get-CimInstance {
            $effects.WmiCalls++
            if ($case -eq 'WmiQueryError') { throw 'WMI unavailable' }
            if ($case -eq 'MissingWmi') { return $null }
            return [pscustomobject]@{State=$(if ($case -eq 'WmiRunning' -or ($case -eq 'LateWmiRunning' -and $effects.WmiCalls -gt 1)) { 'Running' } else { 'Stopped' })}
        }
        function Get-FileHash {
            param($LiteralPath,$Algorithm)
            return [pscustomobject]@{Hash=$(if ($case -eq 'ChangedHash') { 'changed' } elseif ($LiteralPath -eq $sys) { $pinSys } else { $pinInf })}
        }
        function Test-Path {
            param($LiteralPath,$Path,$PathType)
            $value=if ($LiteralPath) { $LiteralPath } else { $Path }
            if ($value -like 'HKLM:*') { return $case -eq 'SdsMarker' }
            return Microsoft.PowerShell.Management\Test-Path -LiteralPath $value
        }
        function Start-Process {
            param($FilePath,$ArgumentList,$RedirectStandardOutput,$RedirectStandardError,[switch]$NoNewWindow,[switch]$PassThru,$ErrorAction)
            $effects.Commands.Add($ArgumentList)
            if ($case -eq 'Started' -and $ArgumentList -eq 'stop VBoxSup') { $effects.Stopped=$true }
            elseif ($ArgumentList -eq '/delete-driver oem7.inf /uninstall') { Remove-Item -LiteralPath $sys,$installedInf }
            else { throw "Unexpected mutation: $ArgumentList" }
            $p=[pscustomobject]@{Handle=[IntPtr]1;ExitCode=0}
            $p | Add-Member ScriptMethod WaitForExit { param($ms) return $true }
            $p | Add-Member ScriptMethod Dispose {}
            return $p
        }
        function Start-Sleep {}
        $failed=$false
        try { & $body } catch { $failed=$true }
        if ($case -in @('FailedStopped','Stage','Started')) {
            Assert-True (-not $failed) 'Known failed-stopped activation could not recover its exact package'
            Assert-True (($effects.Commands -join ';') -eq $(if ($case -eq 'Started') { 'stop VBoxSup;/delete-driver oem7.inf /uninstall' } else { '/delete-driver oem7.inf /uninstall' })) 'Recovery stopped/deleted unrelated resources'
            $report=Get-Content -LiteralPath (Join-Path $outPath 'cleanup-results.json') -Raw | ConvertFrom-Json
            Assert-True ($report.cleanup_verified -and $report.validated_checkpoint -eq $(if ($case -eq 'FailedStopped') { 'StartFailedStopped' } elseif ($case -eq 'Started') { 'Start' } else { 'Stage' }) -and $report.service_stop -eq $(if ($case -eq 'Started') { 'EXIT_0' } else { 'NOT_ATTEMPTED' })) 'Failed-stopped cleanup report invalid'
        } else {
            Assert-True $failed "$case should retain unknown resources"
            Assert-True ($effects.Commands.Count -eq 0) "$case mutated resources despite uncertainty"
            Assert-True ((Test-Path -LiteralPath $sys) -and (Test-Path -LiteralPath $installedInf)) "$case removed driver bytes"
        }
    }
} finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
Write-Host 'PASS failed-stopped recovery'
