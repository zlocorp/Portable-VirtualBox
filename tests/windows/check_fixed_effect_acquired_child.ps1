# Real closed harmless child; no services, drivers, elevated effects or arbitrary command.
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 required' }
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable GitHub-hosted Windows only' }
. (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$directory=Join-Path $env:RUNNER_TEMP ('pvbox-acquired-probe-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$exe=Join-Path $directory 'FixedEffectAcquiredChildProbe.exe'
Compile-FixedFixtureSources @((Join-Path $repo 'source/privilege/FixedEffectWorker.cs'),(Join-Path $PSScriptRoot 'FixedEffectAcquiredChildProbe.cs')) $exe 'PortableVBox.FixedEffectAcquiredChildProbe'
foreach ($mode in @('', '--fail-before-adoption', '--fail-after-retention')) {
    if ($mode -eq '') { $lines=@(& $exe) } else { $lines=@(& $exe $mode) }
    $status=$LASTEXITCODE
    $text=$lines -join "`n"
    $lines | ForEach-Object { Write-Host $_ }
    if ($mode -eq '') {
        if ($status -ne 0 -or $text -notmatch '(?m)^ACQUIRED_CHILD_RETENTION_PASS ') { throw 'Actual-child restricted-handle retention probe failed' }
    } else {
        $marker='ACQUIRED_CHILD_EXPECTED_FAILURE mode='+$mode+' child_exit=23 natural_exit=true'
        if ($status -ne 1 -or $text -notmatch ('(?m)^'+[regex]::Escape($marker)+'$')) { throw 'Expected fixture assertion did not verify natural child teardown' }
    }
}
Write-Host 'ACQUIRED_CHILD_CASES_PASS cases=3 expected_failures=2'
# All expected-negative statuses were checked above. Do not leak the final
# intentional exit 1 into GitHub's wrapper or a caller's native exit status.
$global:LASTEXITCODE=0
