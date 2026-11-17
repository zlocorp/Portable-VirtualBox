# Childless, no system effects. Run the unchanged owner in a separate test EXE.
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 required' }
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable GitHub-hosted Windows only' }
. (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$directory=Join-Path $env:RUNNER_TEMP ('pvbox-retention-probe-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$exe=Join-Path $directory 'FixedEffectWorkerRetentionProbe.exe'
Compile-FixedFixtureSources @((Join-Path $repo 'source/privilege/FixedEffectWorker.cs'),(Join-Path $PSScriptRoot 'FixedEffectWorkerRetentionProbe.cs')) $exe 'PortableVBox.FixedEffectWorkerRetentionProbe'
& $exe
if ($LASTEXITCODE -ne 0) { throw 'Childless native WAIT_FAILED retention probe failed' }
