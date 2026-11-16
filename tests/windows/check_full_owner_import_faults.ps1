# TEST ONLY: harmless real PowerShell child; instrumented imports, unchanged bodies.
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 required' }
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') { throw 'Disposable GitHub-hosted repository runner only' }
. (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$directory=Join-Path $env:RUNNER_TEMP ('pvbox-full-owner-fault-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $directory | Out-Null
python (Join-Path $repo 'tests/generate_owner_fault_fixture.py') $directory
if ($LASTEXITCODE -ne 0) { throw 'Source-bound owner generation failed' }
$exe=Join-Path $directory 'FullOwnerFaultProbe.exe'
Compile-FixedFixtureSources @((Join-Path $directory 'FixedEffectWorker.instrumented.cs'),(Join-Path $PSScriptRoot 'FullOwnerFaultBoundary.cs'),(Join-Path $PSScriptRoot 'FullOwnerFaultProbe.cs')) $exe 'PortableVBox.FullOwnerFaultProbe'
$manifest=Get-Content -LiteralPath (Join-Path $directory 'owner-fault-source-manifest.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath (Join-Path $repo 'source/privilege/FixedEffectWorker.cs') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.source_sha256 -or
    (Get-FileHash -LiteralPath (Join-Path $directory 'FixedEffectWorker.instrumented.cs') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.generated_sha256) { throw 'Source changed during fixture compilation' }
foreach ($mode in @('wait-failed','false-outputs')) {
    foreach ($negative in @($false,$true)) {
        if ($negative) { $lines=@(& $exe $mode --fail-after-retention) } else { $lines=@(& $exe $mode) }
        $status=$LASTEXITCODE;$text=$lines -join "`n";$lines | ForEach-Object { Write-Host $_ }
        if ($negative) {
            $expected='FULL_OWNER_FAULT_EXPECTED_FAILURE mode='+$mode+' child_exit=23 natural_exit=true'
            if ($status -ne 1 -or $text -notmatch ('(?m)^'+[regex]::Escape($expected)+'$')) { throw 'Expected negative did not prove natural child exit' }
        } else {
            $expected='FULL_OWNER_FAULT_PASS mode='+$mode+' checks='
            $suffix=' real_creates=1 original_closes=0 owner_exit_queries=0 run_returned=false run_threw=false run_finally=false fixture_mutex_reacquired=false child_exit=23 natural_exit=true instrumented_imports=true production_bodies_unchanged=true'
            if ($status -ne 0 -or $text -notmatch ('(?m)^'+[regex]::Escape($expected)+'[1-9][0-9]*'+[regex]::Escape($suffix)+'$')) { throw 'Full owner import fault failed' }
        }
    }
}
Write-Host 'FULL_OWNER_IMPORT_CASES_PASS fault_modes=2 hosts=4 expected_failures=2 production_recovery=false'
$global:LASTEXITCODE=0
