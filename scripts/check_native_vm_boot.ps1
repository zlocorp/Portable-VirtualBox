# Host-side independent verification of a *compiled AutoIt* empty-VM session.
# Never installs, starts or stops a driver, service or VirtualBox VM.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$Transcript,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,60)][int]$TimeoutSeconds = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Only a disposable GitHub-hosted Windows runner is permitted'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
function Assert-Private([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Private runner directory boundary rejected'
    }
}
foreach($p in @($PortableRoot,$Transcript,$OutputDirectory)) { Assert-Private $p }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$log=(Resolve-Path -LiteralPath $Transcript).Path
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Refusing existing receipt folder' }
$out=(New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop).FullName
$transcript=Get-Content -LiteralPath $log -Raw -Encoding utf8 -ErrorAction Stop
$marker=[regex]::Matches($transcript,'(?m)^Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF, uuid=([0-9a-f-]{36})\r?$')
if ($marker.Count -ne 1) { throw 'Compiled native AutoIt success evidence is absent or ambiguous' }
$nativeUuid=$marker[0].Groups[1].Value
$vmName='pvbox_compiled_native_fixture'
$home=Join-Path $root 'data\.VirtualBox'
$machines=Join-Path $root 'data\Machines'
$vmFile=Join-Path (Join-Path $machines $vmName) ($vmName+'.vbox')
$profileFile=Join-Path $home 'VirtualBox.xml'
foreach ($file in @($vmFile,$profileFile)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Native AutoIt did not create a private VM/profile' }
}
$cli=Join-Path $root 'app64\VBoxManage.exe'
$signature=Get-AuthenticodeSignature -LiteralPath $cli
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Oracle') {
    throw 'Oracle CLI image signature is invalid'
}
$sup=Get-Service -Name 'VBoxSup' -ErrorAction Stop
$supReg=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSup' -ErrorAction Stop
if ($sup.Status -ne 'Running' -or [int]$supReg.Type -ne 1 -or [int]$supReg.Start -ne 1) {
    throw 'Expected owned signed VBoxSup is not running after native VM poweroff'
}
$services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' |
    Where-Object { $_.PSChildName -match '^VBox' } |
    ForEach-Object { $_.PSChildName })
if ($services.Count -ne 2 -or $services -notcontains 'VBoxSup' -or $services -notcontains 'VBoxSDS') {
    throw 'Expected only VBoxSup and native-created VBoxSDS services'
}
$sds=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
$expectedSds=Join-Path $root 'app64\VBoxSDS.exe'
if (([string]$sds.ImagePath).Trim().Trim('"') -ine $expectedSds -or
    [int]$sds.Type -ne 16 -or [int]$sds.Start -ne 3) {
    throw 'VBoxSDS does not point to this private application binary'
}
$vmProcesses=@(Get-Process -Name 'VirtualBoxVM' -ErrorAction SilentlyContinue)
if ($vmProcesses.Count -ne 0) { throw 'Native test VM process is still running' }
$stdout=Join-Path $out 'independent-vminfo.stdout.txt'
$stderr=Join-Path $out 'independent-vminfo.stderr.txt'
$oldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$p=$null
try {
    $env:VBOX_USER_HOME=$home
    $p=Start-Process -FilePath $cli -WorkingDirectory (Join-Path $root 'app64') -ArgumentList ('showvminfo '+$vmName+' --machinereadable') -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $p.WaitForExit($TimeoutSeconds*1000)) {
        try { $p.Kill(); [void]$p.WaitForExit(5000) } catch {}
        throw 'Independent VM state check exceeded bound'
    }
    if ($p.ExitCode -ne 0) { throw "Independent VBoxManage failed with $($p.ExitCode)" }
} finally {
    if ($null -ne $p) { $p.Dispose() }
    if ($null -eq $oldHome) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME=$oldHome }
}
$observed=Get-Content -LiteralPath $stdout -Raw -ErrorAction Stop
if ($observed -notmatch '(?m)^VMState="poweroff"\r?$') {
    throw 'Independent VM state is not VMState="poweroff"'
}
if ($observed -notmatch '(?im)^UUID="([0-9a-f-]{36})"\r?$' -or
    $Matches[1].ToLowerInvariant() -ne $nativeUuid) {
    throw 'Independent UUID does not match compiled native AutoIt receipt'
}
if (@(Get-Process -Name 'VirtualBoxVM' -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'VM process appeared after independent inspection'
}
$report=[ordered]@{
    experiment='compiled-native-autoit-empty-vm'
    installation_mode='standalone-prepared-app64'
    source_commit=$env:GITHUB_SHA
    native_boot_verified=$true
    independently_verified=$true
    vm_uuid=$nativeUuid
    startvm_returned_zero=$true
    poweroff_succeeded=$true
    final_vm_state='poweroff'
    orphaned_vm_process_count=0
    original_private_vbox_file_present=$true
    guest_os_booted=$false
    vm_disks_created=$false
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'vm-boot-results.json') -Encoding utf8
Write-Host "Native AutoIt VM receipt verified independently: uuid=$nativeUuid, VMState=poweroff, process_count=0"
