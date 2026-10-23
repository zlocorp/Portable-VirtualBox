# Compile a fixed-action, embedded-code helper bound to this exact frontend build.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Frontend)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$front=(Resolve-Path -LiteralPath $Frontend).Path
$out=Split-Path $front -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework compiler missing' }
$sig=Get-AuthenticodeSignature -LiteralPath $compiler
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { throw 'Untrusted Framework compiler' }
$hash=(Get-FileHash -LiteralPath $front -Algorithm SHA256).Hash.ToLowerInvariant()
$inventory=Get-Content -LiteralPath (Join-Path $repo 'source/privilege/oracle-7.2.22-pin.json') -Raw | ConvertFrom-Json
if ($inventory.manifest_rows_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid compiled inventory pin' }
$pin=Join-Path $out 'SessionBuildPin.cs'
[IO.File]::WriteAllText($pin,('namespace PortableVBox { internal static class PinnedBuild { internal const string FrontendSha256="'+$hash+'"; internal const string InventorySha256="'+$inventory.manifest_rows_sha256+'"; } }'))
$target=Join-Path $out 'Portable-VirtualBox-Helper-Test.exe'
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/reference:System.Web.Extensions.dll',('/out:'+ $target))
foreach($name in @('privileged_session_worker.ps1','vbox_sup_standalone.ps1','vbox_sup_start_owned.ps1','vbox_sup_cleanup.ps1','vbox_sup_partial_cleanup.ps1')) {
    $arguments+=('/resource:'+(Join-Path $repo ('scripts\'+$name))+','+$name)
}
$arguments+=@((Join-Path $repo 'source\privilege\TokenFacts.cs'),(Join-Path $repo 'source\privilege\SessionHelper.cs'),(Join-Path $repo 'source\privilege\SessionHelper.Main.cs'),$pin)
& $compiler @arguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Fixed helper compilation failed' }
Write-Host ('Helper built with embedded effect code/inventory for frontend SHA256 '+$hash)
