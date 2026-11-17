# Compile and execute only small, nonprivileged native test harnesses.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AutoItRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$compiler = Join-Path $AutoItRoot 'Aut2Exe\Aut2exe_x64.exe'
$out = Join-Path $repo 'build/native'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$env:PVBOX_NATIVE_TEST_DIR = Join-Path $env:RUNNER_TEMP ('pvbox-native-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:PVBOX_NATIVE_TEST_DIR | Out-Null
$tests = @(Get-ChildItem (Join-Path $repo 'tests/native') -Filter 'test_*.au3' -File | Sort-Object Name)
if ($tests.Count -eq 0) { throw 'No native tests found' }
$failures = @()
foreach ($test in $tests) {
    Write-Host "NATIVE HARNESS: $($test.Name)"
    try {
        $exe = Join-Path $out ($test.BaseName + '.exe')
        if (Test-Path -LiteralPath $exe) { throw 'Refusing stale native test executable' }
        $argsText = '/in "' + $test.FullName + '" /out "' + $exe + '" /x64 /console /nopack'
        $process = Start-Process -FilePath $compiler -ArgumentList $argsText -PassThru -NoNewWindow
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Native test compilation timeout' }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'Native compile failed' }
        $run = Start-Process -FilePath $exe -PassThru -NoNewWindow
        if (-not $run.WaitForExit(30000)) { $run.Kill(); throw 'Native test timed out' }
        if ($run.ExitCode -ne 0) { throw "Native test exit $($run.ExitCode)" }
    } catch {
        $failure = "$($test.Name): $($_.Exception.Message)"
        $failures += $failure
        Write-Host "NATIVE FAILURE: $failure"
    }
}
if ($failures.Count -gt 0) { throw ($failures -join '; ') }
Write-Host "Native harnesses passed: $($tests.Count)"
