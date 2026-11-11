# File-only behavioral contracts. Never invokes the helper entrypoint or SCM/PnP effects.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Output 'SKIP payload cleanup native runner: Windows required'
    return
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-payload-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
try {
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    foreach ($target in @('PayloadCleanupJournal','PayloadCleanupPlan','PayloadObject','PayloadOwner')) {
        $exe=Join-Path $out ($target+'.exe')
        $sources=@((Join-Path $PSScriptRoot ($target+'Tests.cs')))
        $options=@('/nologo','/target:exe','/platform:x64','/langversion:5',('/main:PortableVBox.'+$target+'Tests'),('/out:'+$exe))
        if ($target -eq 'PayloadOwner') {
            $pin=Join-Path $out 'PinnedBuild.cs'
            [IO.File]::WriteAllText($pin,'namespace PortableVBox { internal static class PinnedBuild { internal const string FrontendSha256="test-only"; internal const string FrontendName="Portable-VirtualBox.exe"; internal const string InventorySha256="test-only"; internal const string Mode="CI"; internal const string HelperName="Portable-VirtualBox-Helper-Test.exe"; } }')
            $sources+=@(Get-ChildItem (Join-Path $repo 'source/privilege/*.cs') | ForEach-Object { $_.FullName })
            $sources+=$pin
            $options+=@('/r:System.Web.Extensions.dll','/r:System.ServiceProcess.dll')
            foreach ($script in @('privileged_session_worker.ps1','vbox_sup_standalone.ps1','vbox_sup_start_owned.ps1','vbox_sup_cleanup.ps1','vbox_sup_partial_cleanup.ps1','vbox_sup_package_identity.ps1')) {
                $options+=('/resource:'+(Join-Path $repo ('scripts/'+$script))+','+$script)
            }
        } elseif ($target -eq 'PayloadObject') {
            $sources+=Join-Path $repo 'source/privilege/SessionHelper.PayloadObjects.cs'
            $options+='/define:PAYLOAD_OBJECT_TEST_STUBS'
        } else {
            $sources+=Join-Path $repo 'source/privilege/PayloadCleanupJournal.cs'
            if ($target -eq 'PayloadCleanupPlan') { $sources+=Join-Path $repo 'source/privilege/PayloadCleanupPlan.cs' }
        }
        & $csc @options @sources
        if ($LASTEXITCODE -ne 0) { throw ($target+' compilation failed') }
        & $exe
        if ($LASTEXITCODE -ne 0) { throw ($target+' behavioral contracts failed') }
    }
} finally { Remove-Item -LiteralPath $out -Recurse -Force }
