# TEST ONLY. Evidence from exactly a newly created disposable fixture VM.
# This is not VM discovery, runtime cleanup, or permission to retry effects.
function Assert-FixturePlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse path refused' }
        }
        $parent=[IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break };$current=$parent
    }
}
function Get-FixtureVmDirectory($Binding) {
    if ($Binding.name -notin @('pvbox_manager_gui_fixture','pvbox_helper_boundary_fixture')) { throw 'Foreign fixture name' }
    $root=[IO.Path]::GetFullPath($Binding.root)
    $runner=[IO.Path]::GetFullPath($Binding.runner).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (-not $root.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture root outside runner' }
    $directory=Join-Path (Join-Path $root 'data/Machines') $Binding.name
    Assert-FixturePlainPath $directory
    return $directory
}
function New-FixtureVmLogBinding([string]$PortableRoot,[string]$Name,[string]$RunnerTemp) {
    $binding=@{root=[IO.Path]::GetFullPath($PortableRoot);name=$Name;runner=[IO.Path]::GetFullPath($RunnerTemp);uuid=''}
    $directory=Get-FixtureVmDirectory $binding
    if (Test-Path -LiteralPath $directory) { throw 'Fixture VM directory must not preexist creation' }
    return $binding
}
function Write-FixtureEvidenceBytes([string]$Path,[byte[]]$Bytes) {
    $file=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $file.Write($Bytes,0,$Bytes.Length);$file.Flush() } finally { $file.Dispose() }
}
function Export-FixtureVmLog($Binding,[string]$Output) {
    $report=[ordered]@{schema=1;status='not_created';vm_name='';vm_uuid='';source='';limit_bytes=131072;observed_length=0;offset=0;exported_bytes=0;truncated=$false;failure='';authority='none'}
    try {
        if ($null -ne $Binding -and $Binding.uuid) {
            $directory=Get-FixtureVmDirectory $Binding
            if ($Binding.uuid -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'Invalid created fixture UUID' }
            $report.vm_name=$Binding.name;$report.vm_uuid=$Binding.uuid
            $config=Join-Path $directory ($Binding.name+'.vbox')
            Assert-FixturePlainPath $config
            if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { $report.status='config_not_found' }
            else {
                if ((Get-Item -LiteralPath $config).Length -gt 1048576) { throw 'Fixture config too large' }
                $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=1048576
                $reader=[Xml.XmlReader]::Create($config,$settings)
                try { $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader) } finally { $reader.Dispose() }
                $machine=$doc.SelectNodes('/*[local-name()="VirtualBox"]/*[local-name()="Machine"]')
                if ($machine.Count -ne 1 -or $machine[0].GetAttribute('uuid').Trim('{}') -ine $Binding.uuid) { throw 'Foreign fixture UUID' }
                $log=Join-Path $directory 'Logs/VBox.log';$report.source='Logs/VBox.log'
                Assert-FixturePlainPath $log
                if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { $report.status='log_not_found' }
                else {
                    $stream=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                    try {
                        $length=$stream.Length;$offset=[Math]::Max(0,$length-131072)
                        $report.observed_length=$length;$report.offset=$offset;$report.truncated=($offset -gt 0)
                        [void]$stream.Seek($offset,[IO.SeekOrigin]::Begin)
                        $bytes=New-Object byte[] ([int]($length-$offset));$read=0
                        while ($read -lt $bytes.Length) { $n=$stream.Read($bytes,$read,$bytes.Length-$read);if ($n -eq 0) { break };$read+=$n }
                        if ($read -ne $bytes.Length) { throw 'Fixture log shortened during bounded read' }
                        Write-FixtureEvidenceBytes (Join-Path $Output 'fixture-vbox-tail.txt') $bytes
                        $report.exported_bytes=$read;$report.status='exported'
                    } finally { $stream.Dispose() }
                }
            }
        }
    } catch {
        $report.status='refused_or_read_error'
        $report.failure=switch ($_.Exception.Message) {
            'Reparse path refused' { 'reparse_refused' }
            'Foreign fixture name' { 'foreign_name' }
            'Fixture root outside runner' { 'foreign_root' }
            'Invalid created fixture UUID' { 'invalid_uuid' }
            'Fixture config too large' { 'config_size_limit' }
            'Foreign fixture UUID' { 'uuid_mismatch' }
            'Fixture log shortened during bounded read' { 'log_changed_during_read' }
            default { 'read_or_validation_failed' }
        }
    }
    $json=$report | ConvertTo-Json -Depth 4
    Write-FixtureEvidenceBytes (Join-Path $Output 'fixture-vbox-log-evidence.json') ([Text.UTF8Encoding]::new($false).GetBytes($json))
    return $report
}
