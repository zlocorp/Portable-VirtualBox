# Compile a fixed-action, embedded-code helper bound to this exact frontend build.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Frontend,[switch]$AlphaCandidate)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$front=(Resolve-Path -LiteralPath $Frontend).Path
# Accept only these known compiled experiment frontends, never a chosen path.
$frontName=Split-Path $front -Leaf
if ($frontName -notin @('Portable-VirtualBox-Session-Test.exe','Portable-VirtualBox_x64.exe')) {
    throw 'Unrecognized compiled frontend name'
}
$controllerName=if ($frontName -eq 'Portable-VirtualBox_x64.exe') { 'Portable-VirtualBox.exe' } else { 'Portable-VirtualBox-Session-Test.exe' }
if ($AlphaCandidate -and $frontName -ne 'Portable-VirtualBox_x64.exe') {
    throw 'Interactive alpha must bind only the actual compiled main launcher'
}
$mode=if ($AlphaCandidate) { 'ALPHA' } else { 'CI' }
$helperName=if ($AlphaCandidate) { 'Portable-VirtualBox-Helper-Alpha.exe' } else { 'Portable-VirtualBox-Helper-Test.exe' }
$out=Split-Path $front -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework compiler missing' }
$sig=Get-AuthenticodeSignature -LiteralPath $compiler
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { throw 'Untrusted Framework compiler' }
$hash=(Get-FileHash -LiteralPath $front -Algorithm SHA256).Hash.ToLowerInvariant()
$inventory=Get-Content -LiteralPath (Join-Path $repo 'source/privilege/oracle-7.2.22-pin.json') -Raw | ConvertFrom-Json
if ($inventory.manifest_rows_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid compiled inventory pin' }
$pin=Join-Path $out 'SessionBuildPin.cs'
[IO.File]::WriteAllText($pin,('namespace PortableVBox { internal static class PinnedBuild { internal const string FrontendSha256="'+$hash+'"; internal const string FrontendName="'+$controllerName+'"; internal const string Mode="'+$mode+'"; internal const string HelperName="'+$helperName+'"; internal const string InventorySha256="'+$inventory.manifest_rows_sha256+'"; } }'))
$target=Join-Path $out $helperName
# Fixed bridge exists only as an embedded resource in the paired helper.
$bridge=Join-Path $out 'PortableVBox.SdsBridge.dll'
if (Test-Path -LiteralPath $bridge) { throw 'Stale bridge build output' }
try {
    $bridgeArguments=@('/nologo','/target:library','/platform:x64','/optimize+','/reference:System.Web.Extensions.dll',('/out:'+$bridge),
        (Join-Path $repo 'source/privilege/FixedEffectWorker.cs'),
        (Join-Path $repo 'source/privilege/SdsDiagnosticFiles.cs'),
        (Join-Path $repo 'source/privilege/SdsBridge.cs'),$pin)
    & $compiler @bridgeArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw 'Fixed SDS bridge compilation failed' }
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/reference:System.Web.Extensions.dll','/reference:System.ServiceProcess.dll',('/out:'+ $target))
$arguments+=('/resource:'+$bridge+',PortableVBox.SdsBridge.dll')
foreach($name in @('privileged_session_worker.ps1','vbox_sup_standalone.ps1','vbox_sup_start_owned.ps1','vbox_sup_cleanup.ps1','vbox_sup_partial_cleanup.ps1','vbox_sup_package_identity.ps1')) {
    $arguments+=('/resource:'+(Join-Path $repo ('scripts\'+$name))+','+$name)
}
$arguments+=@((Join-Path $repo 'source\privilege\TokenFacts.cs'),(Join-Path $repo 'source\privilege\SessionHelper.cs'),(Join-Path $repo 'source\privilege\DurableJournal.cs'),(Join-Path $repo 'source\privilege\PayloadCleanupJournal.cs'),(Join-Path $repo 'source\privilege\PayloadCleanupPlan.cs'),(Join-Path $repo 'source\privilege\SessionHelper.PayloadObjects.cs'),(Join-Path $repo 'source\privilege\SessionHelper.PayloadCleanup.cs'),(Join-Path $repo 'source\privilege\SessionHelper.CleanupCompletion.cs'),(Join-Path $repo 'source\privilege\FixedEffectWorker.cs'),(Join-Path $repo 'source\privilege\SessionHelper.Main.cs'),$pin)
& $compiler @arguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Fixed helper compilation failed' }
} finally { if (Test-Path -LiteralPath $bridge) { Remove-Item -LiteralPath $bridge -Force } }
Write-Host ('Helper built with embedded effect code/inventory for frontend SHA256 '+$hash)

# Ordinary console adapter: same frontend/inventory pin, no embedded effects.
$cli=Join-Path $out 'VBoxManagePortable.exe'
& $compiler /nologo /target:exe /platform:x64 /optimize+ /reference:System.Web.Extensions.dll /reference:System.ServiceProcess.dll ("/out:"+$cli) (Join-Path $repo 'source/privilege/TokenFacts.cs') (Join-Path $repo 'source/cli/PortableCli.cs') (Join-Path $repo 'source/cli/PortableCli.Files.cs') $pin
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'Portable CLI compilation failed' }
Copy-Item -LiteralPath (Join-Path $repo 'source/cli/VBoxManage.cmd') -Destination (Join-Path $out 'VBoxManage.cmd') -Force
Write-Host 'Build-paired ordinary-token portable CLI compiled (no elevation or system actions)'
