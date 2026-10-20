# Isolated GitHub CI-only configuration fixture; NEVER starts a guest VM.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(5,120)][int]$TimeoutSeconds=30
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') { throw 'Disposable GitHub Actions host required' }
$app=(Resolve-Path -LiteralPath $AppDir -ErrorAction Stop).Path
$vbox=Join-Path $app 'VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vbox -PathType Leaf)) { throw 'Missing VBoxManage.exe' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Refusing existing output folder' }
$root=(New-Item -ItemType Directory -Path $OutputDirectory).FullName
$vboxHome=(New-Item -ItemType Directory -Path (Join-Path $root 'VBOX_HOME_Тест')).FullName
$machine=(New-Item -ItemType Directory -Path (Join-Path $root 'Machines Test Тест')).FullName
$fixture='portable_probe_fixture'
$results=@()
$old=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
$steps=@(
    @{name='set_machine_folder';arguments=@('setproperty','machinefolder',$machine)},
    @{name='get_properties';arguments=@('list','systemproperties')},
    @{name='create_definition';arguments=@('createvm','--name',$fixture,'--platform-architecture','x86','--register')},
    @{name='list_definitions';arguments=@('list','vms')}
)
function Invoke-VBoxStep {
    param([string]$Name,[string[]]$Arguments)
    $stdout=Join-Path $root ($Name+'.stdout.txt')
    $stderr=Join-Path $root ($Name+'.stderr.txt')
    $argsText=($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $status='LAUNCH_ERROR'; $exitCode=$null; $problem=''; $proc=$null
    try {
        $proc=Start-Process -FilePath $vbox -ArgumentList $argsText -WorkingDirectory $app -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.WaitForExit($TimeoutSeconds*1000)) { $status='EXITED'; $exitCode=$proc.ExitCode }
        else {
            $status='TIMEOUT'
            try { $proc.Kill(); [void]$proc.WaitForExit(5000) }
            catch { $problem='Timed-out process did not terminate' }
        }
    } catch { $problem=$_.Exception.Message }
    finally { $watch.Stop(); if ($null -ne $proc) { $proc.Dispose() } }
    return [pscustomobject]@{name=$Name;status=$status;exit_code=$exitCode;elapsed_ms=$watch.ElapsedMilliseconds;error=$problem;stdout_file=(Split-Path $stdout -Leaf);stderr_file=(Split-Path $stderr -Leaf)}
}
try {
    $env:VBOX_USER_HOME=$vboxHome
    foreach ($step in $steps) {
        $r=Invoke-VBoxStep -Name $step.name -Arguments $step.arguments
        $results+= $r
        Write-Host "$($r.name): $($r.status) / $($r.exit_code); argv count=$($step.arguments.Count)"
        if ($r.status -ne 'EXITED' -or $r.exit_code -ne 0) { break }
    }
} finally {
    if ($null -eq $old) { Remove-Item Env:\VBOX_USER_HOME -ErrorAction SilentlyContinue }
    else { $env:VBOX_USER_HOME=$old }
}
$config=Join-Path $vboxHome 'VirtualBox.xml'
$vboxFiles=@(Get-ChildItem -LiteralPath $machine -Filter '*.vbox' -File -Recurse -ErrorAction SilentlyContinue)
$propertiesText=if (Test-Path (Join-Path $root 'get_properties.stdout.txt')) { Get-Content -LiteralPath (Join-Path $root 'get_properties.stdout.txt') -Raw } else { '' }
$listText=if (Test-Path (Join-Path $root 'list_definitions.stdout.txt')) { Get-Content -LiteralPath (Join-Path $root 'list_definitions.stdout.txt') -Raw } else { '' }
$machineFolderExpected=($propertiesText -match '(?m)^Default machine folder:\s+(.+)$' -and $Matches[1].TrimEnd() -ieq $machine)
$registrationFound=($listText -match [regex]::Escape($fixture))
$pass=($results.Count -eq $steps.Count -and @($results | Where-Object { $_.status -ne 'EXITED' -or $_.exit_code -ne 0 }).Count -eq 0 -and $machineFolderExpected -and $registrationFound -and (Test-Path -LiteralPath $config -PathType Leaf) -and $vboxFiles.Count -eq 1)
$report=[ordered]@{
    experiment='portable-configuration-no-VM-boot'
    source_commit=$env:GITHUB_SHA
    successful=[bool]$pass
    commands=$results
    profile_xml_in_isolated_home=(Test-Path -LiteralPath $config -PathType Leaf)
    reported_machinefolder_matches_portable_folder=[bool]$machineFolderExpected
    fixture_registration_listed=[bool]$registrationFound
    machine_definition_files=$vboxFiles.Count
    machine_definition_inside_portable_folder=($vboxFiles.Count -eq 1)
    vm_started=$false
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'config-results.json') -Encoding utf8
Write-Host "Portable config fixture: success=$pass, config=$($report.profile_xml_in_isolated_home), vbox_files=$($vboxFiles.Count)"
if (-not $pass) { throw 'Portable configuration fixture failed; diagnostic files retained' }
