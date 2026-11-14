# Managed admission rules only. Never calls the facade Run or any Windows effect.
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 Framework required' }
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$directory=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-sds-admission-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
try {
    $inventory=Get-Content -LiteralPath (Join-Path $repo 'source/privilege/oracle-7.2.22-pin.json') -Raw | ConvertFrom-Json
    if ($inventory.manifest_rows_sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'Invalid fixture inventory pin' }
    $pin=Join-Path $directory 'SdsAdmissionTestPin.cs'
    [IO.File]::WriteAllText($pin,('namespace PortableVBox { internal static class PinnedBuild { internal const string Mode="CI"; internal const string InventorySha256="'+$inventory.manifest_rows_sha256+'"; } }'))
    $output=Join-Path $directory 'SdsBridgeAdmissionTests.exe'
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $sources=@('source/privilege/FixedEffectWorker.cs','source/privilege/SdsDiagnosticFiles.cs','source/privilege/SdsBridge.cs','tests/windows/SdsBridgeAdmissionTests.cs') | ForEach-Object { Join-Path $repo $_ }
    & $compiler /nologo /codepage:65001 /target:exe /platform:x64 /langversion:5 /warnaserror+ /reference:System.Web.Extensions.dll /main:PortableVBox.SdsBridgeAdmissionTests ("/out:"+$output) @sources $pin
    if ($LASTEXITCODE -ne 0) { throw 'SDS admission fixture compilation failed' }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'SDS admission validation failed' }
} finally {
    Remove-Item -LiteralPath $directory -Recurse -Force
}
