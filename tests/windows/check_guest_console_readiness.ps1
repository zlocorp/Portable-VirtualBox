# Harmless fixture self-test: no VM, helper, service or driver invocation.
$ErrorActionPreference='Stop'
Add-Type -Path @((Join-Path $PSScriptRoot 'GuestConsoleObservation.cs'),(Join-Path $PSScriptRoot 'GuestConsoleObservationTests.cs'))
. (Join-Path $PSScriptRoot 'GuestConsoleReadiness.ps1')
[PortableVBox.Tests.GuestConsoleObservationTests]::Run((Join-Path $PSScriptRoot '../fixtures/guest-console'))
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-console-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $folder | Out-Null
try {
    # Exercise the actual Windows PNG reader with exact observed BGRA bytes.
    $pngChecks=0
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    foreach ($name in @('observed-shell','command-as-login')) {
        $file=[IO.File]::OpenRead((Join-Path $PSScriptRoot ('../fixtures/guest-console/'+$name+'.bgra.gz')))
        $zip=[IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionMode]::Decompress)
        $mem=[IO.MemoryStream]::new()
        try { $zip.CopyTo($mem);$pixels=$mem.ToArray() } finally { $zip.Dispose();$file.Dispose();$mem.Dispose() }
        $bitmap=[Drawing.Bitmap]::new(1024,768,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $rect=[Drawing.Rectangle]::new(0,0,1024,768)
            $locked=$bitmap.LockBits($rect,[Drawing.Imaging.ImageLockMode]::WriteOnly,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try { [Runtime.InteropServices.Marshal]::Copy($pixels,0,$locked.Scan0,$pixels.Length) } finally { $bitmap.UnlockBits($locked) }
            $path=Join-Path $folder ($name+'.png');$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
        $actual=Read-GuestConsole $path
        if ([PortableVBox.Tests.GuestConsoleObservation]::Shell($actual) -ne ($name -eq 'observed-shell')) { throw 'Actual PNG reader changed observation' }
        if ([PortableVBox.Tests.GuestConsoleObservation]::Login($actual)) { throw 'Historical completed/bad frame accepted as ready login' }
    }
        $pngChecks++
    }
    # Byte/count limits are tested before any PNG decode or input.
    $b=New-GuestObservationBudget
    for($i=0;$i -lt 30;$i++) { Reserve-GuestObservation $b }
    $refused=$false;try { Reserve-GuestObservation $b } catch { $refused=$true }
    if (-not $refused) { throw 'Observation count limit ignored' }
    $b=New-GuestObservationBudget;$b.bytes=$b.max_bytes-1
    $oversize=Join-Path $folder 'over-budget.png';[IO.File]::WriteAllBytes($oversize,[byte[]]@(1,2))
    $refused=$false;try { Accept-GuestObservationFile $oversize $b } catch { $refused=$true }
    if (-not $refused -or (Test-Path $oversize) -or -not (Test-Path ($oversize+'.refused.json'))) { throw 'Aggregate byte limit ignored' }
    $oversize=Join-Path $folder 'over-frame.png';[IO.File]::WriteAllBytes($oversize,(New-Object byte[] 262145))
    $refused=$false;try { Accept-GuestObservationFile $oversize (New-GuestObservationBudget) } catch { $refused=$true }
    if (-not $refused -or (Test-Path $oversize)) { throw 'Frame byte limit ignored' }
    $oversize=Join-Path $folder 'failed-remove.png';[IO.File]::WriteAllBytes($oversize,(New-Object byte[] 262145))
    function Remove-Item { throw 'injected fixture removal failure' }
    $failure='';try { Accept-GuestObservationFile $oversize (New-GuestObservationBudget) } catch { $failure=$_.Exception.Message }
    Microsoft.PowerShell.Management\Remove-Item Function:Remove-Item
    if ($failure -notmatch 'byte budget exhausted.*removal failed' -or -not (Test-Path $oversize)) { throw 'Removal failure masked gate or continued' }
    # Exercise real wait/orchestration with controlled guest observations only.
    $script:events=[Collections.Generic.List[string]]::new();$script:loginObservations=0;$script:testNonce=''
    $script:scenario='success'
    $originalBudget=(Get-Item Function:New-GuestObservationBudget).ScriptBlock
    function New-GuestObservationBudget { $b=& $originalBudget;$b.max_observations=5;return $b }
    function Start-Sleep { }
    function Oracle([string]$Arguments,[string]$Label) {
        $script:events.Add($Arguments)
        if ($Arguments -match 'screenshotpng "([^"]+)"') { [IO.File]::WriteAllBytes($Matches[1],[byte[]]@(1)) }
        if ($Label -eq 'observed-guest-write') {
            if ($Arguments -notmatch 'PVBOX_ ([a-f0-9]{32})"$') { throw 'No split fresh nonce in command' }
            $script:testNonce=$Matches[1]
        }
    }
    function Read-GuestConsole([string]$Path) {
        if ($script:scenario -eq 'no-login') { return ,@('?not-ready') }
        if ($script:scenario -eq 'no-ack' -and $Path -match 'write-ack') { return ,@('localhost:~#') }
        if ($Path -match 'login-ready') {
            $script:loginObservations++
            if ($script:loginObservations -eq 1) { return ,@('?unsupported-console-geometry') }
            return ,@('localhost login:')
        }
        if ($Path -match 'shell-ready') { return ,@('localhost:~#') }
        if ($Path -match 'write-ack') { return ,@(('PVBOX_'+$script:testNonce),'localhost:~#') }
        throw 'Unexpected screenshot'
    }
    $receipt=Invoke-ObservedGuestWrite 'fixture-uuid' $folder 'PVBOX_TEST'
    if ($script:loginObservations -ne 2 -or $receipt.nonce -ne $script:testNonce) { throw 'Observation sequence skipped or wrong nonce' }
    $text=$script:events -join "`n"
    if (($script:events | Where-Object { $_ -match 'keyboardputstring root' }).Count -ne 1 -or
        ($script:events | Where-Object { $_ -match 'dd of=/dev/sda' }).Count -ne 1) { throw 'Guest commands repeated' }
    $loginAt=$text.IndexOf('guest-login-ready-2.png');$shellAt=$text.IndexOf('guest-shell-ready-1.png')
    if ($loginAt -lt 0 -or $shellAt -lt 0 -or
        $loginAt -gt $text.IndexOf('keyboardputstring root') -or
        $shellAt -gt $text.IndexOf('dd of=/dev/sda')) { throw 'Command preceded observed readiness' }
    if (-not (Test-Path (Join-Path $folder 'guest-write-ack.json'))) { throw 'Acknowledgment evidence not retained' }
    foreach ($scenario in @('no-login','no-ack')) {
        $script:scenario=$scenario;$script:events.Clear();$script:loginObservations=0
        $caseFolder=Join-Path $folder $scenario;New-Item -ItemType Directory $caseFolder | Out-Null
        $refused=$false;try { $null=Invoke-ObservedGuestWrite 'fixture-uuid' $caseFolder 'PVBOX_TEST' } catch { $refused=$true }
        if (-not $refused -or (Test-Path (Join-Path $caseFolder 'guest-write-ack.json'))) { throw 'Missing observation accepted' }
        $writes=@($script:events | Where-Object { $_ -match 'dd of=/dev/sda' }).Count
        $inputs=@($script:events | Where-Object { $_ -match 'keyboardput' }).Count
        if (($scenario -eq 'no-login' -and $inputs -ne 0) -or ($scenario -eq 'no-ack' -and $writes -ne 1)) { throw 'Premature or repeated guest command' }
    }
    Write-Host ('GUEST_CONSOLE_SEQUENCE_PASS png_platform_checked='+($pngChecks -gt 0))
} finally { Remove-Item -LiteralPath $folder -Recurse -Force }
