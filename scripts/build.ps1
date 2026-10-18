# Build only. This script never runs Portable-VirtualBox or modifies Windows services.
[CmdletBinding()]
param(
    [string] $AutoItRoot = ""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $repo "source\Portable-VirtualBox.au3"
$icon = Join-Path $repo "source\VirtualBox.ico"
$outDir = Join-Path $repo "build"
$out = Join-Path $outDir "Portable-VirtualBox_x64.exe"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing AutoIt source: $source" }
if (-not (Test-Path -LiteralPath $icon -PathType Leaf)) { throw "Missing icon: $icon" }

if (-not $AutoItRoot) {
    $locations = @(
        (Join-Path ${env:ProgramFiles(x86)} "AutoIt3"),
        (Join-Path $env:ProgramFiles "AutoIt3")
    )
    foreach ($location in $locations) {
        if (Test-Path -LiteralPath $location -PathType Container) {
            $AutoItRoot = $location
            break
        }
    }
}
if (-not $AutoItRoot) { throw "AutoIt root not found; pass -AutoItRoot" }
$compiler = Join-Path $AutoItRoot "Aut2Exe\Aut2exe_x64.exe"
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Pinned AutoIt installation must include Aut2exe_x64.exe: $compiler"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

Write-Host "Source: $source"
Write-Host "Compiler: $compiler"
Write-Host "Output: $out"

# Explicit argument quoting is necessary for checkout paths containing whitespace.
$argsString = '/in "' + $source + '" /out "' + $out + '" /icon "' + $icon + '" /x64 /nopack'
$process = Start-Process -FilePath $compiler -ArgumentList $argsString -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Aut2Exe exited with code $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath $out -PathType Leaf)) { throw "Compiler did not create $out" }
$file = Get-Item -LiteralPath $out
if ($file.Length -lt 10240) { throw "Output is implausibly small: $($file.Length) bytes" }
$stream = [System.IO.File]::OpenRead($out)
try {
    $byte1 = $stream.ReadByte()
    $byte2 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($byte1 -ne 0x4D -or $byte2 -ne 0x5A) { throw "Output is not a Windows executable (MZ header missing)" }
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash.ToLowerInvariant()
"$sha  Portable-VirtualBox_x64.exe" | Set-Content -LiteralPath (Join-Path $outDir "SHA256SUMS.txt") -Encoding ascii
Write-Host "Build OK: $($file.Length) bytes; SHA256 $sha"
