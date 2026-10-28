# Inspect a pinned official package on a disposable runner. No installer is run.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work = New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop
$exe = Join-Path $work.FullName 'VirtualBox-7.2.22-175245-Win.exe'
$expected = 'afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f'
function Get-VBoxServiceSnapshot {
    @((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
        Where-Object PSChildName -match '^VBox' | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath
            [pscustomobject]@{name=$_.PSChildName; properties=$p}
        }) | ConvertTo-Json -Depth 5 -Compress)
}
$before = Get-VBoxServiceSnapshot
python (Join-Path $repo 'scripts/oracle_release.py') 7.2.22 --download $exe
if ($LASTEXITCODE -ne 0) { throw 'Verified Oracle download failed' }
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Oracle wrapper checksum does not match pinned input'
}
$signature = Get-AuthenticodeSignature -LiteralPath $exe
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Oracle') {
    throw 'Oracle wrapper signature is not valid'
}
$stage = Join-Path $work.FullName 'extracted'
python (Join-Path $repo 'scripts/oracle_extract.py') $exe $stage --sha256 $expected
if ($LASTEXITCODE -ne 0) { throw 'Passive PE resource extraction failed' }
$packageReport = Get-Content (Join-Path $stage 'packages.json') -Raw | ConvertFrom-Json
$entries = @($packageReport.packages | Where-Object { $_.name -match '\.msi$' -and $_.architecture -in @('all','amd64') })
if ($entries.Count -ne 1) { throw 'Expected exactly one x64-compatible MSI' }
$msi = Join-Path $stage $entries[0].name
$msiHashBefore = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant()
if ($msiHashBefore -ne $entries[0].sha256) { throw 'Extracted MSI differs from extraction manifest' }
$installer = New-Object -ComObject WindowsInstaller.Installer
$db = $null
$info = $null
try {
    Write-Host ('MSI inspection stage: OpenDatabase; path-type=' + $msi.GetType().FullName)
    # Use PowerShell's COM adapter to marshal the path and numeric read-only mode.
    $db = $installer.OpenDatabase([string]$msi, [int]0)
    function Read-MsiProperty([string]$Name) {
        Write-Host ('MSI inspection stage: property ' + $Name)
        $query = 'SELECT `Value` FROM `Property` WHERE `Property` = ''' + $Name + ''''
        $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($query))
        $record = $null
        try {
            $null = $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
            $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
            if ($null -eq $record) { throw "MSI property missing: $Name" }
            return $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
        } finally {
            if ($null -ne $record) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
        }
    }
    $product = Read-MsiProperty 'ProductName'
    $version = Read-MsiProperty 'ProductVersion'
    $manufacturer = Read-MsiProperty 'Manufacturer'
    Write-Host 'MSI inspection stage: SummaryInformation'
    $info = $db.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $db, @(0))
    $template = $info.GetType().InvokeMember('Property', 'GetProperty', $null, $info, @(7))
    if ($product -notmatch 'VirtualBox' -or $version -notmatch '^7\.2\.22(?:\.|$)' -or $manufacturer -notmatch 'Oracle') {
        throw "Unexpected MSI identity: $product / $version / $manufacturer"
    }
    if ($template -notmatch '^x64;') { throw "MSI does not target x64: $template" }
    if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant() -ne $msiHashBefore) { throw 'Read-only MSI inspection modified its input' }
    if (($before | Out-String) -cne ((Get-VBoxServiceSnapshot) | Out-String)) { throw 'VBox service state changed' }
    $report = [ordered]@{
        sourceCommit=$env:GITHUB_SHA; installerSha256=$expected
        wrapperSignature=$signature.Status.ToString(); signer=$signature.SignerCertificate.Subject
        product=$product; productVersion=$version; manufacturer=$manufacturer; platform=$template
        packages=$packageReport.packages; installerExecuted=$false; msiInstalled=$false
        vboxServiceRegistryUnchanged=$true; msiDatabaseUnchanged=$true; databaseOpenMode='read-only'
    }
    $reports = Join-Path $repo '.reports'
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $reports 'oracle-inspection.json') -Encoding utf8
    Write-Host "PASS: $product; $version; $template. No Oracle installer or MSI executed."
} catch {
    Write-Host ('MSI inspection failure location: ' + $_.ScriptStackTrace)
    throw
} finally {
    if ($null -ne $info) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($info) }
    if ($null -ne $db) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db) }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
