# TEST ONLY: create/delete stopped GUID services on an authorized disposable host.
# No VBox, driver, service start/stop, production context, or cleanup retry.
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess -or
    $env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Authorized disposable GitHub-hosted Windows x64 only'
}
. (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
$directory=Join-Path $env:RUNNER_TEMP ('pvbox-service-identity-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
$exe=Join-Path $directory 'ServiceIdentityNativeTests.exe'
Compile-FixedFixtureSources @((Join-Path $PSScriptRoot 'ServiceIdentityNativeTests.cs')) $exe 'PortableVBox.ServiceIdentityModel.ServiceIdentityNativeTests'
$lines=@(& $exe --disposable-scm-identity)
$status=$LASTEXITCODE
$text=$lines -join "`n"
$lines | ForEach-Object { Write-Host $_ }
if ($status -ne 0 -or $text -notmatch '(?m)^SERVICE_IDENTITY_NATIVE_PASS checks=6 service_started=false production_authority=false$') {
    throw 'Disposable SCM identity characterization failed; no production capability established'
}
$global:LASTEXITCODE=0
