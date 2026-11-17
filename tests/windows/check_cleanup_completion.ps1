# Cross-platform, managed-only tests of the actual private production sequence.
# Never invokes helper Main, payload deletion, native APIs or a system worker.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Add-Type -Path @((Join-Path $repo 'source/privilege/SessionHelper.CleanupCompletion.cs'),(Join-Path $PSScriptRoot 'CleanupCompletionTests.cs'))
if ([PortableVBox.CleanupCompletionTests]::Main() -ne 0) { throw 'Cleanup sequence failed' }
