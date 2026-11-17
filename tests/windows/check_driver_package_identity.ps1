# Execute the real file-only package identity code in an owned scratch directory.
# No PnPUtil, service, registry, process, Oracle or elevation operations.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$implementation=Join-Path $repo 'scripts/vbox_sup_package_identity.ps1'
if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) { throw 'Missing locale-independent package identity implementation' }
. $implementation
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-inf-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$script:checks=0
function Check([bool]$Pass,[string]$Name) {
    $script:checks++
    if (-not $Pass) { throw "FAIL INF identity: $Name" }
}
function Denied([scriptblock]$Action,[string]$Name) {
    $blocked=$false
    try { & $Action | Out-Null } catch { $blocked=$true }
    Check $blocked $Name
}
function Receipt([string]$Name,[string]$Hash) {
    # JSON roundtrip matches the actual protected staging evidence format.
    return ([ordered]@{published_inf_schema=1;published_inf=$Name;
        published_inf_sha256=$Hash;published_inf_was_absent=$true} |
        ConvertTo-Json | ConvertFrom-Json)
}
try {
    $inf=Join-Path $root 'INF'
    New-Item -ItemType Directory -Path $inf | Out-Null
    $package=Join-Path $root 'VBoxSup.inf'
    [IO.File]::WriteAllText($package,"[Version]`r`nProvider=Oracle`r`n; VBoxSup fixture",[Text.Encoding]::Unicode)
    $hash=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $inf 'oem2.inf'),'unrelated package')
    $before=@(Get-PortablePublishedInfFiles -InfDirectory $inf | ForEach-Object Name)
    Copy-Item -LiteralPath $package -Destination (Join-Path $inf 'oem17.inf')
    # Deliberately misleading EN/RU transcripts are not inputs or authority.
    foreach($log in @('Published Name: oem999.inf',([char]0x0418).ToString()+' oem888.inf', '')) {
        [IO.File]::WriteAllText((Join-Path $root 'pnputil.stdout.txt'),$log)
        Check ((Get-PortableNewPublishedInf -InfDirectory $inf -BeforeNames $before -ExpectedSha256 $hash) -ceq 'oem17.inf') 'exact new bytes independent of transcript'
    }
    $proof=Receipt 'oem17.inf' $hash
    Check ((Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $proof -ExpectedSha256 $hash) -ceq 'oem17.inf') 'receipt and current bytes match'
    Denied { Get-PortableNewPublishedInf -InfDirectory $inf -BeforeNames @('oem2.inf','OEM17.INF') -ExpectedSha256 $hash } 'preexisting name never adopted'
    Copy-Item -LiteralPath $package -Destination (Join-Path $inf 'oem18.inf')
    Denied { Get-PortableNewPublishedInf -InfDirectory $inf -BeforeNames $before -ExpectedSha256 $hash } 'duplicate exact hashes refused'
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $proof -ExpectedSha256 $hash } 'duplicate current identities refused'
    Remove-Item -LiteralPath (Join-Path $inf 'oem18.inf')
    foreach($name in @('../oem17.inf','oem17.inf:stream','oem17.inf ',"oem17.inf`n",'oem*.inf','oem-1.inf','oem1234567.inf','VBoxSup.inf','')) {
        $bad=Receipt $name $hash
        Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } ('invalid leaf '+$name)
    }
    $bad=Receipt 'oem17.inf' $hash; $bad.published_inf_was_absent=$false
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } 'absence false'
    $bad=Receipt 'oem17.inf' $hash; $bad.published_inf_was_absent='true'
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } 'truthy string refused'
    $bad=Receipt 'oem17.inf' $hash; $bad.published_inf_schema=2
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } 'wrong schema'
    $bad=Receipt 'oem17.inf' $hash; $bad.PSObject.Properties.Remove('published_inf_sha256')
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } 'missing receipt field'
    $bad=Receipt 'oem17.inf' ('0'*64)
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $bad -ExpectedSha256 $hash } 'changed receipt hash'
    [IO.File]::WriteAllText((Join-Path $inf 'oem17.inf'),'changed')
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $proof -ExpectedSha256 $hash } 'changed published bytes'
    Denied { Get-PortableNewPublishedInf -InfDirectory $inf -BeforeNames $before -ExpectedSha256 $hash } 'no exact package'
    Remove-Item -LiteralPath (Join-Path $inf 'oem17.inf')
    Denied { Get-PortableOwnedPublishedInf -InfDirectory $inf -Receipt $proof -ExpectedSha256 $hash } 'missing published file'
    New-Item -ItemType Directory -Path (Join-Path $inf 'oem17.inf') | Out-Null
    Denied { Get-PortablePublishedInfFiles -InfDirectory $inf } 'directory cannot be INF'
    Remove-Item -LiteralPath (Join-Path $inf 'oem17.inf')
    # A directory junction works without symbolic-link elevation and must be refused.
    $junction=Join-Path $root 'linked-INF'
    if ($env:OS -eq 'Windows_NT') {
        New-Item -ItemType Junction -Path $junction -Target $inf | Out-Null
        Denied { Get-PortablePublishedInfFiles -InfDirectory $junction } 'reparse root refused'
        [IO.Directory]::Delete($junction)
    } else {
        New-Item -ItemType SymbolicLink -Path $junction -Target $inf | Out-Null
        Denied { Get-PortablePublishedInfFiles -InfDirectory $junction } 'reparse root refused'
        Remove-Item -LiteralPath $junction
    }
    Check ((Get-Content -LiteralPath (Join-Path $inf 'oem2.inf') -Raw) -ceq 'unrelated package') 'unrelated file unchanged'
    Write-Host "DRIVER_PACKAGE_IDENTITY_PASS checks=$script:checks"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
