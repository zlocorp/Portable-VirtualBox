# Read-only VBoxSup driver inspection after an OFFICIAL installation on a
# disposable GitHub-hosted Windows runner. No driver install/start/uninstall.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$InstallReport,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Only a disposable GitHub-hosted runner is authorized'
}
$reference=(Get-Content -LiteralPath $InstallReport -Raw -ErrorAction Stop | ConvertFrom-Json)
if ($reference.status -ne 'EXITED' -or $reference.exit_code -ne 0 -or
    $reference.feature -ne 'VBoxApplication' -or
    @($reference.services_before).Count -ne 0 -or
    @($reference.services_after) -notcontains 'VBoxSup') {
    throw 'No verified clean-host official VBoxApplication installation evidence'
}
$app=(Resolve-Path -LiteralPath $AppDir -ErrorAction Stop).Path
if ($app -ine ([string]$reference.install_directory).TrimEnd('\')) {
    throw 'Official installation directory differs from install report'
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output must be a new directory' }
$folder=(New-Item -ItemType Directory -Path $OutputDirectory).FullName
$key='HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup'
if (-not (Test-Path -LiteralPath $key)) { throw 'Official MSI did not register VBoxSup' }

$reg=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
$svc=Get-Service -Name VBoxSup -ErrorAction Stop
$expectedNtPath='\SystemRoot\system32\DRIVERS\VBoxSup.sys'
$validConfiguration=([int]$reg.Type -eq 1 -and [int]$reg.Start -eq 1 -and
    ([string]$reg.ImagePath -ieq $expectedNtPath))
$installedSys=Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'
$sourceSys=Join-Path $app 'drivers\vboxsup\VBoxSup.sys'
$catalog=Join-Path $app 'drivers\vboxsup\VBoxSup.cat'
$inf=Join-Path $app 'drivers\vboxsup\VBoxSup.inf'

$installedExists=Test-Path -LiteralPath $installedSys -PathType Leaf
$sourceExists=Test-Path -LiteralPath $sourceSys -PathType Leaf
$catalogExists=Test-Path -LiteralPath $catalog -PathType Leaf
$infExists=Test-Path -LiteralPath $inf -PathType Leaf
$installedHash=if ($installedExists) {(Get-FileHash -Algorithm SHA256 -LiteralPath $installedSys).Hash.ToLowerInvariant()} else {''}
$sourceHash=if ($sourceExists) {(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceSys).Hash.ToLowerInvariant()} else {''}
$sysSignature=if ($installedExists) {Get-AuthenticodeSignature -LiteralPath $installedSys} else {$null}
$catSignature=if ($catalogExists) {Get-AuthenticodeSignature -LiteralPath $catalog} else {$null}
$driver=Get-CimInstance Win32_SystemDriver -Filter "Name='VBoxSup'" -ErrorAction SilentlyContinue

$report=[ordered]@{
    experiment='official-VBoxSup-read-only-reference'
    source_commit=$env:GITHUB_SHA
    service_present=$true
    service_state=[string]$svc.Status
    service_type=[int]$reg.Type
    service_start=[int]$reg.Start
    service_image_path=[string]$reg.ImagePath
    service_configuration_matches_official_inf=[bool]$validConfiguration
    system_driver_file_present=[bool]$installedExists
    packaged_driver_file_present=[bool]$sourceExists
    packaged_inf_present=[bool]$infExists
    packaged_catalog_present=[bool]$catalogExists
    installed_sha256=$installedHash
    packaged_sha256=$sourceHash
    installed_equals_packaged=[bool]($installedExists -and $sourceExists -and $installedHash -eq $sourceHash)
    installed_sys_signature_status=$(if ($null -ne $sysSignature) {[string]$sysSignature.Status} else {''})
    installed_sys_signer=$(if ($null -ne $sysSignature -and $null -ne $sysSignature.SignerCertificate) {[string]$sysSignature.SignerCertificate.Subject} else {''})
    catalog_signature_status=$(if ($null -ne $catSignature) {[string]$catSignature.Status} else {''})
    catalog_signer=$(if ($null -ne $catSignature -and $null -ne $catSignature.SignerCertificate) {[string]$catSignature.SignerCertificate.Subject} else {''})
    wmi_driver_state=$(if ($null -ne $driver) {[string]$driver.State} else {'MISSING'})
    wmi_driver_started=$(if ($null -ne $driver) {[bool]$driver.Started} else {$false})
    vm_started=$false
    driver_service_mutated=$false
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'sup-results.json') -Encoding utf8
Write-Host "VBoxSup: service=$($report.service_state); driver=$installedExists; package=$sourceExists; SHA-equal=$($report.installed_equals_packaged); WMI=$($report.wmi_driver_state); signature=$($report.installed_sys_signature_status)"
if ($env:GITHUB_STEP_SUMMARY) {
    '### Official VBoxSup installation reference' | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Service state: $($report.service_state), WMI: $($report.wmi_driver_state)" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "- Installed package hash match: $($report.installed_equals_packaged)" | Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
if (-not $validConfiguration -or -not $installedExists -or -not $sourceExists -or
    -not $infExists -or -not $catalogExists) {
    throw 'Official VBoxSup layout/installation differs from expected; inspect JSON report'
}
