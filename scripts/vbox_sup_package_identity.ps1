# Read-only, locale-independent identity for a single exactly pinned OEM INF.
# This is NOT ownership authority on its own: callers must first validate the
# protected session/controller receipts and exclusive clean-host acquisition.
function Get-PortablePublishedInfFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InfDirectory)
    $directory=Get-Item -LiteralPath $InfDirectory -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Published INF root is not a regular directory'
    }
    $entries=@(Get-ChildItem -LiteralPath $directory.FullName -Filter 'oem*.inf' -Force -ErrorAction Stop)
    if ($entries.Count -gt 65536) { throw 'Published INF inventory exceeds bound' }
    foreach($entry in $entries) {
        if ($entry.Name -notmatch '\Aoem[0-9]{1,6}\.inf\z' -or $entry.PSIsContainer -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Published INF inventory contains an unsafe entry'
        }
        $entry
    }
}

function Get-PortableNewPublishedInf {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InfDirectory,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BeforeNames,
          [Parameter(Mandatory)][string]$ExpectedSha256)
    if ($ExpectedSha256 -cnotmatch '\A[a-f0-9]{64}\z') { throw 'Invalid pinned INF SHA256' }
    foreach($name in $BeforeNames) {
        if ($name -notmatch '\Aoem[0-9]{1,6}\.inf\z') { throw 'Invalid original OEM INF inventory' }
    }
    $matches=@(Get-PortablePublishedInfFiles -InfDirectory $InfDirectory | Where-Object {
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq $ExpectedSha256
    })
    if ($matches.Count -ne 1) { throw 'No unique exact published Oracle INF' }
    $published=$matches[0].Name.ToLowerInvariant()
    if ($BeforeNames -contains $published) { throw 'Published Oracle INF name existed before this installation' }
    return $published
}

function Get-PortableOwnedPublishedInf {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InfDirectory,
          [Parameter(Mandatory)]$Receipt,
          [Parameter(Mandatory)][string]$ExpectedSha256)
    # Missing fields and ambiguous legacy receipts fail closed. Never fall back
    # to translated PnPUtil output or infer a new receipt during cleanup.
    if ($Receipt.published_inf_schema -ne 1 -or
        $Receipt.published_inf -isnot [string] -or
        $Receipt.published_inf -notmatch '\Aoem[0-9]{1,6}\.inf\z' -or
        $Receipt.published_inf_was_absent -isnot [bool] -or -not $Receipt.published_inf_was_absent -or
        $Receipt.published_inf_sha256 -isnot [string] -or
        $Receipt.published_inf_sha256 -cne $ExpectedSha256) {
        throw 'No exact new-package identity in original staging receipt'
    }
    # Require the same unique pinned identity still present. Existing ownership
    # evidence comes from the validated receipt, never from this empty list.
    $current=Get-PortableNewPublishedInf -InfDirectory $InfDirectory -BeforeNames @() -ExpectedSha256 $ExpectedSha256
    if ($current -ine $Receipt.published_inf) { throw 'Published OEM INF changed since staging' }
    return $current
}
