# Non-release packaging: no Windows services, drivers or Oracle processes run.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stage=Join-Path $repo 'build/alpha-stage'
if ((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $Output)) { throw 'Refusing to overwrite an alpha package/stage' }
$exe=Join-Path $repo 'build/Portable-VirtualBox_x64.exe'
$helper=Join-Path $repo 'build/Portable-VirtualBox-Helper-Alpha.exe'
$setup=Join-Path $repo 'build/Portable-VirtualBox-Setup.exe'
$pin=Get-Content -LiteralPath (Join-Path $repo 'build/SessionBuildPin.cs') -Raw -Encoding UTF8
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($pin -notmatch [regex]::Escape('FrontendSha256="'+$hash+'"') -or
    $pin -notmatch 'Mode="ALPHA"' -or
    $pin -notmatch 'HelperName="Portable-VirtualBox-Helper-Alpha.exe"' -or
    $pin -notmatch 'FrontendName="Portable-VirtualBox.exe"') { throw 'Alpha frontend/helper pin mismatch' }
$files=[ordered]@{
  'Portable-VirtualBox.exe'=$exe
  'Portable-VirtualBox-Setup.exe'=$setup
  'Portable-VirtualBox-Helper-Alpha.exe'=$helper
  'README.md'=(Join-Path $repo 'README.md')
  'README.ru.md'=(Join-Path $repo 'README.ru.md')
  'LICENSE.md'=(Join-Path $repo 'LICENSE.md')
  'CREDITS.md'=(Join-Path $repo 'CREDITS.md')
  'ALPHA-TEST-ONLY.md'=(Join-Path $repo 'docs/ALPHA-WINDOWS-TEST.md')
}
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
foreach($name in $files.Keys) {
  if (-not (Test-Path -LiteralPath $files[$name] -PathType Leaf)) { throw "Missing mandatory artifact input $name" }
  Copy-Item -LiteralPath $files[$name] -Destination (Join-Path $stage $name)
}
$rows=@(Get-ChildItem -LiteralPath $stage -File | Sort-Object Name | ForEach-Object {
  (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.Name
})
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'),[string[]]$rows,[Text.Encoding]::ASCII)
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $Output -CompressionLevel Optimal -ErrorAction Stop
if (-not (Test-Path -LiteralPath $Output -PathType Leaf)) { throw 'Alpha archive missing' }
Write-Host ('NON-RELEASE alpha SHA-256: '+(Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash.ToLowerInvariant())
