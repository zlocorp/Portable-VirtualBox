# CI fixture arrangement only. The elevated runner prepared these files;
# make ONLY its throwaway portable INPUT tree belong to the actual user SID.
# The helper's protected copy must keep its own unmodified ACL and deny writes.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') { throw 'Disposable hosted fixture only' }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$temp=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not $root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture must stay below runner temp' }
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
$items=@(Get-Item -LiteralPath $root)+@(Get-ChildItem -LiteralPath $root -Recurse -Force)
foreach ($item in $items) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'No links in input fixture' }
    $acl=Get-Acl -LiteralPath $item.FullName
    $acl.SetOwner($owner)
    $inherit=if ($item.PSIsContainer) { [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' } else { [Security.AccessControl.InheritanceFlags]::None }
    $rule=[Security.AccessControl.FileSystemAccessRule]::new($owner,[Security.AccessControl.FileSystemRights]::Modify,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $item.FullName -AclObject $acl
}
Write-Host ('User-owned portable input fixture: '+$owner.Value+'; no protected helper paths changed')
