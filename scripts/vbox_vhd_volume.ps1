# Disposable GitHub-hosted Windows VHDX helper. Never format a physical disk.
# The ONLY volume created/formatted by this tool is a newly created VHDX file
# beneath RUNNER_TEMP; letter changes are checked against that exact disk image.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Create','Reletter')][string]$Action,
    [Parameter(Mandatory)][string]$BackingFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
    throw 'Disposable GitHub-hosted Windows runner required'
}
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP -ErrorAction Stop).Path.TrimEnd('\')+'\'
$file=[IO.Path]::GetFullPath($BackingFile)
if (-not $file.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($file) -ine '.vhdx' -or
    $file -match '["\r\n]' -or
    -not (Test-Path -LiteralPath (Split-Path $file -Parent) -PathType Container)) {
    throw 'VHDX must be a new or owned private file under RUNNER_TEMP'
}
$sourceLetter='P'
$destLetter='Q'
function Assert-Volume([string]$Letter,[string]$Image) {
    $diskImage=Get-DiskImage -ImagePath $Image -ErrorAction Stop
    if (-not $diskImage.Attached) { throw 'Owned VHD is not attached' }
    $disk=$diskImage | Get-Disk -ErrorAction Stop
    if ($null -eq $disk -or $disk.Number -lt 0) { throw 'Cannot resolve VHD-backed disk identity' }
    $partitions=@(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop |
        Where-Object { $_.DriveLetter -eq $Letter })
    if ($partitions.Count -ne 1) { throw 'Selected drive letter is not on this VHD' }
    $volume=Get-Volume -DriveLetter $Letter -ErrorAction Stop
    if ($volume.FileSystem -ne 'NTFS' -or $volume.FileSystemLabel -ne 'PVBOX_TEMP') {
        throw 'Selected letter does not refer to the expected NTFS VHD volume'
    }
    return $partitions[0]
}
if ($Action -eq 'Create') {
    if (Test-Path -LiteralPath $file) { throw 'Refusing to reuse existing VHDX' }
    if ((Test-Path -LiteralPath 'P:\') -or (Test-Path -LiteralPath 'Q:\')) {
        throw 'P: or Q: already assigned on hosted Windows'
    }
    $diskpartScript=Join-Path $env:RUNNER_TEMP ('create-vhdx-'+[guid]::NewGuid().ToString('N')+'.txt')
    $lines=@(
        ('create vdisk file="' + $file + '" maximum=1024 type=expandable'),
        ('select vdisk file="' + $file + '"'),
        'attach vdisk',
        'create partition primary',
        'format fs=ntfs quick label=PVBOX_TEMP',
        'assign letter=P'
    )
    $lines | Set-Content -LiteralPath $diskpartScript -Encoding ascii
    $exe=Join-Path $env:SystemRoot 'System32\diskpart.exe'
    $stdout=Join-Path $env:RUNNER_TEMP 'vhd-creation-diskpart.stdout.txt'
    $stderr=Join-Path $env:RUNNER_TEMP 'vhd-creation-diskpart.stderr.txt'
    $p=$null
    try {
        $p=Start-Process -FilePath $exe -ArgumentList ('/s "'+$diskpartScript+'"') -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $ownedHandle=$p.Handle
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Owned DiskPart child handle unavailable' }
        if (-not $p.WaitForExit(120000)) {
            # Formatting the *owned* VHDX must not be interrupted halfway by
            # killing DiskPart. Retain its process until it exits, then refuse.
            $p.WaitForExit()
            throw 'Disposable VHDX creation exceeded deadline; state requires inspection'
        }
        if ($p.ExitCode -ne 0) { throw "DiskPart exited $($p.ExitCode)" }
    } finally { if ($null -ne $p) { $p.Dispose() } }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        -not (Test-Path -LiteralPath 'P:\')) {
        throw 'DiskPart did not create the VHDX and P:'
    }
    $part=Assert-Volume $sourceLetter $file
    Write-Host "Disposable VHD mounted as P: (partition $($part.PartitionNumber))"
} else {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        -not (Test-Path -LiteralPath 'P:\') -or
        (Test-Path -LiteralPath 'Q:\')) {
        throw 'Expected P: exists and Q: absent before reassignment'
    }
    $partition=Assert-Volume $sourceLetter $file
    Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $destLetter -ErrorAction Stop
    if ((Test-Path -LiteralPath 'P:\') -or -not (Test-Path -LiteralPath 'Q:\')) {
        throw 'VHD drive letter change did not take effect'
    }
    $after=Assert-Volume $destLetter $file
    if ($after.DiskNumber -ne $partition.DiskNumber -or
        $after.PartitionNumber -ne $partition.PartitionNumber) {
        throw 'Mounted VHD partition identity changed during reassignment'
    }
    Write-Host "Disposable VHD reassigned P: -> Q: (same disk $($after.DiskNumber), partition $($after.PartitionNumber))"
}
