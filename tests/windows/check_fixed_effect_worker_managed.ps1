$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# Diagnostics are bounded and best-effort: never change process status or
# replace a test failure with a reporting failure.
function Write-ManagedMarker([string]$marker) {
    try { Write-Host $marker } catch { }
}
function Write-ManagedExitStatus([string]$phase) {
    try {
        $v=Get-Variable -Name LASTEXITCODE -ErrorAction Ignore
        $last=if ($null -eq $v) { 'absent' } elseif ($v.Value -is [int]) { $v.Value.ToString([Globalization.CultureInfo]::InvariantCulture) } else { 'other' }
        $environment=[Environment]::ExitCode.ToString([Globalization.CultureInfo]::InvariantCulture)
        Write-Host ("MANAGED_EXIT_STATUS phase=$phase last_exit=$last environment_exit=$environment")
    } catch { }
}
Write-ManagedExitStatus 'before'
try {
    # Actual private production code, managed methods only; no helper Main/native calls.
    Add-Type -Path @((Join-Path $repo 'source/privilege/FixedEffectWorker.cs'),(Join-Path $PSScriptRoot 'FixedEffectWorkerManagedTests.cs'),(Join-Path $repo 'source/privilege/SdsDiagnosticFiles.cs'),(Join-Path $PSScriptRoot 'SdsDiagnosticFilesTests.cs'))
    $fixedResult=[PortableVBox.FixedEffectWorkerManagedTests]::Main()
    Write-ManagedMarker ("FIXED_EFFECT_MANAGED_RETURNED result=" + $fixedResult.ToString([Globalization.CultureInfo]::InvariantCulture))
    Write-ManagedExitStatus 'after_fixed'
    if ($fixedResult -ne 0) { throw 'Fixed worker managed assertions failed' }
    $sdsResult=[PortableVBox.SdsDiagnosticFilesTests]::Main()
    Write-ManagedMarker ("SDS_DIAGNOSTIC_FILES_RETURNED result=" + $sdsResult.ToString([Globalization.CultureInfo]::InvariantCulture))
    Write-ManagedExitStatus 'after_sds'
    if ($sdsResult -ne 0) { throw 'SDS diagnostic file assertions failed' }
} finally {
    Write-ManagedExitStatus 'final'
}
