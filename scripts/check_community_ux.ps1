# Exercise the ordinary compiled interface, never hidden driver/VM modes.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:RUNNER_TEMP) { throw 'Private test directory required' }
$source = (Resolve-Path -LiteralPath $Launcher).Path
$root = Join-Path $env:RUNNER_TEMP ('Community UX Тест ' + [guid]::NewGuid().ToString('N'))
$logs = Join-Path $env:RUNNER_TEMP ('Community logs ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root,$logs -ErrorAction Stop | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $root 'Portable-VirtualBox_x64.exe')
function Invoke-Checked([string]$Root, [string]$Arguments, [int]$Expected, [string]$Label) {
    $out = Join-Path $logs ($Label + '.out.txt')
    $err = Join-Path $logs ($Label + '.err.txt')
    $p = Start-Process -FilePath (Join-Path $Root 'Portable-VirtualBox_x64.exe') -WorkingDirectory $Root -ArgumentList $Arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    try {
        if (-not $p.WaitForExit(20000)) { throw "Public CLI timed out: $Label" }
        if ($p.ExitCode -ne $Expected) {
            throw "$Label exit=$($p.ExitCode), expected=$Expected; $(Get-Content $err -Raw -ErrorAction SilentlyContinue)"
        }
    } finally { $p.Dispose() }
    return [string](Get-Content -LiteralPath $out -Raw -Encoding utf8)
}
$about = Invoke-Checked $root '--lang en --about' 0 'about'
foreach ($credit in @('Portable-VirtualBox','CC BY-NC-SA 3.0','CREDITS.md','startup is currently disabled')) {
    if (-not $about.Contains($credit)) { throw "Missing compiled credit/boundary: $credit" }
}
if ($about.Length -ge 400 -or $about.Contains('Deac2')) { throw 'About contains unnecessary contributor detail' }
$aboutRu = Invoke-Checked $root '--lang ru --about' 0 'about-ru'
if ($aboutRu.Length -ge 400 -or $aboutRu.Contains('Deac2') -or -not $aboutRu.Contains('Запуск виртуальных машин')) { throw 'Russian About is not compact/localized' }
Write-Host ('About RU (' + $aboutRu.Trim().Length + ' characters):' + [Environment]::NewLine + $aboutRu.Trim())
$missing = Invoke-Checked $root '--lang ru --app-status' 2 'missing-app'
if (-not $missing.Contains('app64')) { throw 'Missing-app explanation absent' }
if (Test-Path (Join-Path $root 'data')) { throw 'Read-only commands created a profile' }
$null = Invoke-Checked $root '--save-language ru' 0 'save-ru'
$settings = Join-Path $root 'data\launcher.ini'
$before = (Get-FileHash -LiteralPath $settings).Hash
$ru = Invoke-Checked $root '--help' 0 'saved-ru'
if (-not $ru.Contains('Портативный VirtualBox')) { throw 'Saved Russian did not survive restart' }
$en = Invoke-Checked $root '--lang en --help' 0 'temporary-en'
if (-not $en.Contains('diagnostic preview')) { throw 'Explicit language did not override saved preference' }
if ((Get-FileHash -LiteralPath $settings).Hash -ne $before) { throw '--lang modified persistent settings' }
$null = Invoke-Checked $root '--save-language auto' 0 'auto'
if (-not (Get-Content -LiteralPath $settings -Raw).Contains('language=auto')) { throw 'Auto preference not saved' }
$null = Invoke-Checked $root '--save-language fr' 64 'reject-locale'
$null = Invoke-Checked $root '--save-language en' 0 'save-en'
$sentinel = Join-Path $root 'data\.VirtualBox\existing-user-file.txt'
[IO.File]::WriteAllText($sentinel, 'do not overwrite')
$moved = $root + ' relocated'
Move-Item -LiteralPath $root -Destination $moved
$root = $moved
$en = Invoke-Checked $root '--help' 0 'relocated-en'
if (-not $en.Contains('diagnostic preview')) { throw 'Saved language lost after relocation' }
if ([IO.File]::ReadAllText((Join-Path $root 'data\.VirtualBox\existing-user-file.txt')) -ne 'do not overwrite') { throw 'User data changed' }
$settings = Join-Path $root 'data\launcher.ini'
[IO.File]::WriteAllText($settings, 'foreign configuration')
$null = Invoke-Checked $root '--save-language ru' 3 'foreign-config'
if ([IO.File]::ReadAllText($settings) -ne 'foreign configuration') { throw 'Invalid settings were overwritten' }
$app = Join-Path $root 'app64'
New-Item -ItemType Directory -Path $app | Out-Null
[IO.File]::WriteAllText((Join-Path $app 'VirtualBox.exe'), 'fixture, not executed')
$incomplete = Invoke-Checked $root '--lang en --app-status' 3 'incomplete-app'
if (-not $incomplete.Contains('VBoxManage.exe') -or -not $incomplete.Contains('VBoxSup.sys')) { throw 'Incomplete application was not explained' }
$incomplete = Invoke-Checked $root '--lang ru --check-readiness' 3 'incomplete-readiness'
if (-not $incomplete.Contains('VBoxManage.exe')) { throw 'Readiness bypassed app completeness' }
Remove-Item -LiteralPath (Join-Path $root 'data\Machines') # empty test directory only
$folders = Invoke-Checked $root '--lang en --check-readiness' 3 'missing-machines'
if (-not $folders.Contains('data\Machines')) { throw 'Missing Machines folder not identified' }
$diag = Invoke-Checked $root '--lang en --diagnose' 0 'activity'
foreach ($label in @('Manager processes:','VM processes (GUI/headless):','VirtualBox background processes:')) {
    if (-not $diag.Contains($label)) { throw "Activity category absent: $label" }
}
Write-Host 'PASS: ordinary compiled CLI preserves language across restart/relocation, rejects foreign settings, reports incomplete app64/missing Machines, and carries credits'
