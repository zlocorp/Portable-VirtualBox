# Build the ordinary-user, file-only Oracle preparer. No MSI/EXE is executed.
# Its embedded Python runtime is part of the final EXE: users need no Python.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows build host required' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$version='6.22.3'
# Build dependency is external, pinned and not committed to this repository.
python -m pip install --disable-pip-version-check --no-input --quiet "pyinstaller==$version"
if ($LASTEXITCODE -ne 0) { throw 'Pinned PyInstaller install failed' }
python -m PyInstaller --noconfirm --clean --onefile --console --name Portable-VirtualBox-Setup `
    --distpath (Join-Path $repo 'build') --workpath (Join-Path $repo 'build/pyinstaller-work') `
    --specpath (Join-Path $repo 'build') (Join-Path $repo 'scripts/portable_prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'Portable preparation compiler failed' }
$exe = Join-Path $repo 'build/Portable-VirtualBox-Setup.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'No preparer binary' }
if ((Get-Item $exe).Length -lt 10240) { throw 'Invalid preparer binary size' }
$p=Start-Process -FilePath $exe -ArgumentList '--version' -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $repo 'build/preparer-version.txt')
if ($p.ExitCode -ne 0) { throw 'Frozen preparer does not respond to --version' }
if ((Get-Content -LiteralPath (Join-Path $repo 'build/preparer-version.txt') -Raw) -notmatch 'Oracle 7\.2\.22') { throw 'Preparer version mismatched' }
Write-Host ('Offline non-admin preparer built (SHA256 '+(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()+')')
