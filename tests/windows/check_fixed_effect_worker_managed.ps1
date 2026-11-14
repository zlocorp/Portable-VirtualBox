$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# Actual private production code, managed methods only; no helper Main/native calls.
Add-Type -Path @((Join-Path $repo 'source/privilege/FixedEffectWorker.cs'),(Join-Path $PSScriptRoot 'FixedEffectWorkerManagedTests.cs'),(Join-Path $repo 'source/privilege/SdsDiagnosticFiles.cs'),(Join-Path $PSScriptRoot 'SdsDiagnosticFilesTests.cs'))
if ([PortableVBox.FixedEffectWorkerManagedTests]::Main() -ne 0) { throw 'Fixed worker managed assertions failed' }

if ([PortableVBox.SdsDiagnosticFilesTests]::Main() -ne 0) { throw 'SDS diagnostic file assertions failed' }
