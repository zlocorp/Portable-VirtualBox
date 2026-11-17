# Real bounded journal writes/reads only. No helper entrypoint, Oracle or system effects.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-journal-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
try {
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $exe=Join-Path $out 'JournalContract.exe'
    $sources=@((Join-Path $PSScriptRoot 'DurableJournalTests.cs'))
    $implementation=Join-Path $repo 'source/privilege/DurableJournal.cs'
    if (Test-Path -LiteralPath $implementation) { $sources+=$implementation }
    & $csc /nologo /target:exe /platform:x64 /main:PortableVBox.DurableJournalTests ("/out:"+$exe) @sources
    if ($LASTEXITCODE -ne 0) { throw 'Durable journal contract compilation failed' }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw 'Durable journal behavioral contract failed' }
} finally { Remove-Item -LiteralPath $out -Recurse -Force }
