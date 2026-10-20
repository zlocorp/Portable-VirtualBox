# Inventory-only metadata of inherited binary tools. NEVER execute them.
[CmdletBinding()]
param([string]$OutputDirectory = '.reports')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$paths = @(
    'source\Aut2Exe\Aut2exe.exe',
    'source\Aut2Exe\Aut2exe_x64.exe',
    'source\i_data\tools\7za.exe',
    'source\i_data\tools\devcon_x64.exe',
    'source\i_data\tools\devcon_x86.exe',
    'source\i_data\tools\snetcfg_x64.exe',
    'source\i_data\tools\snetcfg_x86.exe'
)
$items = foreach ($relative in $paths) {
    $file = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing inherited tool: $relative" }
    $info = Get-Item -LiteralPath $file
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    [pscustomobject]@{
        path = $relative.Replace('\', '/')
        size_bytes = $info.Length
        sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        file_version = [string]$info.VersionInfo.FileVersion
        product_version = [string]$info.VersionInfo.ProductVersion
        publisher = [string]$info.VersionInfo.CompanyName
        signature_status = [string]$signature.Status
        certificate_subject = if ($null -ne $signature.SignerCertificate) {
            [string]$signature.SignerCertificate.Subject
        } else { '' }
        included_in_modern_runtime = $false
        policy = 'legacy-only; quarantine pending dependency/license/provenance review'
    }
}
$dest = Join-Path $repo $OutputDirectory
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$report = [ordered]@{
    inventory_only = $true
    source_commit = $env:GITHUB_SHA
    inherited_files = @($items)
    modern_toolchain = 'Official signed AutoIt 3.3.18.0 via pinned CI download'
    modern_virtualbox = 'Signed official Oracle VirtualBox 7.2.20 prepared from MSI/CAB'
    binaries_executed = $false
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dest 'bundled-tools.json') -Encoding utf8
$items | Format-Table path,file_version,signature_status,publisher -AutoSize
Write-Host "Legacy binary inventory: $(@($items).Count) items; none executed"
