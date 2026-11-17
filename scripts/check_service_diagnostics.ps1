# Compiled query-only CLI acceptance. No Oracle runtime or elevation required.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$launcherPath = (Resolve-Path -LiteralPath $Launcher).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('Portable Service Report Тест ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$exe = Join-Path $root 'Portable-VirtualBox.exe'
Copy-Item -LiteralPath $launcherPath -Destination $exe
$expectedNames = @('VBoxDrv','VBoxSup','VBoxUSB','VBoxUSBMon','VBoxSDS','VBoxNetAdp','VBoxNetAdp6','VBoxNetLwf','VBoxNetFlt','VBoxNetNAT')
$servicesBefore = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object PSChildName -match '^VBox' | Select-Object -ExpandProperty PSChildName | Sort-Object)
if ($servicesBefore.Count -ne 0) { throw 'Compiled diagnostics fixture requires an initially clean VBox host' }
function Invoke-Report([string]$Arguments,[string]$Label,[int]$ExpectedExit = 0) {
    $stdout = Join-Path $root ($Label + '.stdout.txt')
    $stderr = Join-Path $root ($Label + '.stderr.txt')
    $p = Start-Process -FilePath $exe -ArgumentList $Arguments -WorkingDirectory $root -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    try {
        if (-not $p.WaitForExit(20000)) { throw "Report process did not exit: $Label" }
        if ($p.ExitCode -ne $ExpectedExit) { throw "Report $Label exit $($p.ExitCode), expected $ExpectedExit" }
    } finally { $p.Dispose() }
    if ((Get-Item -LiteralPath $stderr).Length -ne 0) { throw "Unexpected report stderr: $Label" }
    return [IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8)
}
$beforeFiles = @(Get-ChildItem -LiteralPath $root -Force | Select-Object -ExpandProperty Name)
$en = Invoke-Report '--lang en --diagnose-services' 'services-en'
$ru = Invoke-Report '--lang ru --diagnose-services' 'services-ru'
if (-not $en.Contains('Service status') -or -not $ru.Contains('Состояние служб')) { throw 'Missing RU/EN report header' }
foreach ($name in $expectedNames) {
    if ($en -notmatch ('(?m)^' + [regex]::Escape($name) + '\s+ABSENT(?:\s|$)') -or $ru -notmatch ('(?m)^' + [regex]::Escape($name) + '\s+ОТСУТСТВУЕТ(?:\s|$)')) { throw "Missing exact absent service row: $name" }
}
$enJson = Invoke-Report '--lang en --diagnose-services-json' 'services-en-json'
$ruJson = Invoke-Report '--lang ru --diagnose-services-json' 'services-ru-json'
if ($enJson -cne $ruJson) { throw 'JSON depends on display language on the same clean fixture' }
$json = $enJson | ConvertFrom-Json
if ($json.schema -ne 1 -or $json.exit_code -ne 0 -or @($json.services).Count -ne 10) { throw 'Wrong service-report schema' }
if ((@($json.services | ForEach-Object name) -join '|') -cne ($expectedNames -join '|')) { throw 'Service names/order changed' }
foreach ($row in $json.services) {
    if ($row.observation -ne 'ABSENT' -or $row.state -ne 'ABSENT' -or $row.win32_error -ne 1060 -or $row.ownership -ne 'NOT_APPLICABLE') { throw 'False absent/ownership report' }
    if ((@($row.PSObject.Properties.Name | Sort-Object) -join '|') -cne 'name|observation|ownership|state|win32_error') { throw 'Unexpected metadata exported' }
}
if ($json.PSObject.Properties.Name.Count -ne 3) { throw 'Unexpected top-level metadata exported' }
$diagnostic = Invoke-Report '--diagnose' 'full-report'
foreach ($name in $expectedNames) { if (-not $diagnostic.Contains($name)) { throw "Full report omitted $name" } }
$null = Invoke-Report '--diagnose-services unexpected' 'bad-text-arity' 64
$null = Invoke-Report '--diagnose-services-json unexpected' 'bad-json-arity' 64
foreach ($name in @('data','logs','app64')) {
    if (Test-Path -LiteralPath (Join-Path $root $name)) { throw "Read-only diagnostics created $name" }
}
if (@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object PSChildName -match '^VBox').Count -ne 0 -or
    @(Get-Process | Where-Object ProcessName -match '^(VBox|VirtualBox)').Count -ne 0) { throw 'Diagnostics started VBox activity' }
$afterFiles = @(Get-ChildItem -LiteralPath $root -Force | Where-Object Name -notmatch '\.(stdout|stderr)\.txt$' | Select-Object -ExpandProperty Name)
if (($afterFiles -join '|') -cne ($beforeFiles -join '|')) { throw 'Read-only report created unexpected files' }
Write-Host 'PASS: compiled RU/EN service snapshots and stable JSON; no Oracle launch, profile creation or service effects'
# Leave the small isolated result files for inspection; never delete user data.
