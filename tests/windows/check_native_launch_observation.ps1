# Test-only, disposable file writes. Never invokes VBox, helper Main or system tools.
[CmdletBinding()]
param([switch]$ManagedOnly,[string]$EvidenceDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($ManagedOnly) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'NativeLaunchObservation.cs'),(Join-Path $PSScriptRoot 'NativeLaunchObservationTests.cs'),(Join-Path $PSScriptRoot 'NativeProcessRuntimeInspection.cs'))
    if ([PortableVBox.NativeLaunchObservationTests]::RunManaged() -ne 0) { throw 'Managed observation contracts failed' }
    $inspector=[PortableVBox.NativeLaunchObservationTests].Assembly.GetType('PortableVBox.NativeProcessRuntimeInspection')
    $flags=[Reflection.BindingFlags]'Static,NonPublic'
    $capture=$inspector.GetMethod('CaptureForPaths',$flags)
    # Return the original raw JSON for strict parsing by Python, including failures.
    Write-Output $capture.Invoke($null,[object[]]@($null,$null))
    Write-Output $capture.Invoke($null,[object[]]@('',$null))
    Write-Output $capture.Invoke($null,[object[]]@($null,''))
    return
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Output 'SKIP native launch observations: Windows required'
    return
}
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-launch-build-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$started=$false
try {
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $child=Join-Path $out 'NativeLaunchFixtureChild.exe'
    & $csc /nologo /target:exe /platform:x64 /langversion:5 /warnaserror+ ('/out:'+$child) (Join-Path $PSScriptRoot 'NativeLaunchFixtureChild.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Fixed file-only fixture compilation failed' }
    $exe=Join-Path $out 'NativeLaunchObservationTests.exe'
    $sources=@('NativeLaunchObservation.cs','NativeLaunchObservationTests.cs','NativeLaunchObservationNative.cs',
        'NativeLaunchObservationNativeTests.cs','NativeProcessRuntimeInspection.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & $csc /nologo /target:exe /platform:x64 /langversion:5 /warnaserror+ /main:PortableVBox.NativeLaunchObservationTests ('/out:'+$exe) @sources
    if ($LASTEXITCODE -ne 0) { throw 'Native observation contracts compilation failed' }
    foreach ($program in @($child,$exe)) {
        [IO.File]::WriteAllText(($program+'.config'),'<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>')
    }
    $log=Join-Path $out 'native-launch-observations.jsonl'
    $started=$true
    $lines=@(& $exe)
    $nativeExit=$LASTEXITCODE
    $text=($lines -join "`n")+"`n"
    if ([Text.Encoding]::UTF8.GetByteCount($text) -gt 262144) { throw 'Native output evidence bound exceeded' }
    [IO.File]::WriteAllText($log,$text,(New-Object Text.UTF8Encoding($false)))
    $lines | ForEach-Object { Write-Output $_ }
    if ($EvidenceDirectory) {
        if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null }
        foreach ($name in @('native-launch-observations.jsonl','runtime-process-inspection.json')) {
            $source=Join-Path $out $name
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $bytes=[IO.File]::ReadAllBytes($source)
            if ($bytes.Length -gt 262144) { throw ('Evidence bound exceeded: '+$name) }
            $destination=Join-Path $EvidenceDirectory $name
            $file=New-Object IO.FileStream($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            try { $file.Write($bytes,0,$bytes.Length);$file.Flush($true) } finally { $file.Dispose() }
        }
    }
    if ($nativeExit -ne 0) { throw ('Native observation contracts failed: '+$nativeExit) }
    if (-not (Test-Path -LiteralPath (Join-Path $out 'safe-to-cleanup'))) { throw 'Missing verified drain completion; generated files retained' }
} finally {
    if (-not $started -or (Test-Path -LiteralPath (Join-Path $out 'safe-to-cleanup'))) {
        # Only this generated compiler/output directory, never paths obtained from logs.
        Remove-Item -LiteralPath $out -Recurse -Force
    } else {
        Write-Warning ('UNRESOLVED: verified child drain missing; generated build/fixture files preserved. OS process teardown is not drain evidence. Build root: '+$out)
    }
}
