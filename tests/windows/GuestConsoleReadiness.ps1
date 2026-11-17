# TEST ONLY. Dot-source from guarded disposable Windows fixtures after ISO verification.
# Exact fixed Alpine 1024x768 / 8x16 observations, never fuzzy OCR or system authority.
if (-not ('PortableVBox.Tests.GuestConsoleObservation' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'GuestConsoleObservation.cs')
}
Add-Type -AssemblyName System.Drawing
function New-GuestObservationBudget { return @{observations=0;bytes=0;max_observations=30;max_bytes=4194304;max_frame_bytes=262144} }
function Reserve-GuestObservation($Budget) {
    if ($Budget.observations -ge $Budget.max_observations) { throw 'Guest observation count exhausted' }
    $Budget.observations++
}
function Accept-GuestObservationFile([string]$Path,$Budget) {
    $length=(Get-Item -LiteralPath $Path -ErrorAction Stop).Length
    if ($length -gt $Budget.max_frame_bytes -or $length -gt ($Budget.max_bytes-$Budget.bytes)) {
        # Only this newly-created fixture screenshot is removed, never prior
        # evidence, runtime data, or helper files. Keep bounded refusal metadata.
        @{reason='guest-observation-byte-budget';bytes=$length;accepted_bytes=$Budget.bytes} |
            ConvertTo-Json | Set-Content -LiteralPath ($Path+'.refused.json') -Encoding UTF8
        try { Remove-Item -LiteralPath $Path -ErrorAction Stop }
        catch { throw ('Guest observation byte budget exhausted; own oversized frame removal failed: '+$_.Exception.Message) }
        throw 'Guest observation byte budget exhausted'
    }
    $Budget.bytes+=$length
}
function Read-GuestConsole([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 262144) { throw 'Guest screenshot too large before decode' }
    $original=[Drawing.Bitmap]::new($Path)
    $bitmap=$null;$locked=$null
    try {
        if ($original.Width -ne 1024 -or $original.Height -ne 768) { return ,@('?unsupported-console-geometry') }
        $rect=[Drawing.Rectangle]::new(0,0,1024,768)
        $bitmap=$original.Clone($rect,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $locked=$bitmap.LockBits($rect,[Drawing.Imaging.ImageLockMode]::ReadOnly,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        if ($locked.Stride -ne 4096) { throw 'Unsupported fixed Alpine console stride' }
        $pixels=New-Object byte[] (4096*768)
        [Runtime.InteropServices.Marshal]::Copy($locked.Scan0,$pixels,0,$pixels.Length)
        return ,([PortableVBox.Tests.GuestConsoleObservation]::Decode($pixels,1024,768,4096))
    } finally {
        if ($null -ne $locked) { $bitmap.UnlockBits($locked) }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        $original.Dispose()
    }
}
function Wait-GuestConsole([string]$Uuid,[string]$Output,[string]$Phase,$Budget,[string]$Nonce='') {
    $timer=[Diagnostics.Stopwatch]::StartNew();$attempt=0
    do {
        Reserve-GuestObservation $Budget
        $attempt++
        $label='guest-'+$Phase+'-'+$attempt
        $screen=Join-Path $Output ($label+'.png')
        if (Test-Path -LiteralPath $screen) { throw 'Guest observation target already exists' }
        $null=Oracle ('controlvm '+$Uuid+' screenshotpng "'+$screen+'"') $label
        Accept-GuestObservationFile $screen $Budget
        $lines=Read-GuestConsole $screen
        $lines | Set-Content -LiteralPath (Join-Path $Output ($label+'.txt')) -Encoding UTF8
        $matched=switch ($Phase) {
            'login-ready' { [PortableVBox.Tests.GuestConsoleObservation]::Login($lines) }
            'shell-ready' { [PortableVBox.Tests.GuestConsoleObservation]::Shell($lines) }
            'write-ack' { [PortableVBox.Tests.GuestConsoleObservation]::Acknowledged($lines,$Nonce) }
            default { throw 'Unknown guest observation phase' }
        }
        if ($matched) { return $label }
        Start-Sleep -Milliseconds 2000
    } while ($timer.Elapsed.TotalSeconds -lt 90)
    throw ('Guest console did not prove '+$Phase+' within observation deadline')
}
function Invoke-ObservedGuestWrite([string]$Uuid,[string]$Output,[string]$Marker) {
    if ($Marker -notmatch '^PVBOX_[A-Z0-9_]+$') { throw 'Unexpected fixed guest marker' }
    $budget=New-GuestObservationBudget
    $login=Wait-GuestConsole $Uuid $Output 'login-ready' $budget
    $null=Oracle ('controlvm '+$Uuid+' keyboardputstring root') 'observed-guest-login'
    $null=Oracle ('controlvm '+$Uuid+' keyboardputscancode 1c 9c') 'observed-guest-login-enter'
    $shell=Wait-GuestConsole $Uuid $Output 'shell-ready' $budget
    $nonce=[Guid]::NewGuid().ToString('N')
    # The typed command never contains the full fresh acknowledgment string.
    # Only successful dd and sync followed by printf may produce its own line.
    $command='echo '+$Marker+' | dd of=/dev/sda bs=512 seek=2048 conv=notrunc && sync && printf ''\n%s%s\n'' PVBOX_ '+$nonce
    $null=Oracle ('controlvm '+$Uuid+' keyboardputstring "'+$command+'"') 'observed-guest-write'
    $null=Oracle ('controlvm '+$Uuid+' keyboardputscancode 1c 9c') 'observed-guest-write-enter'
    $ack=Wait-GuestConsole $Uuid $Output 'write-ack' $budget $nonce
    $evidence=[ordered]@{schema=1;login_observation=$login;shell_observation=$shell;write_ack_observation=$ack;nonce=$nonce;marker=$Marker;observations=$budget.observations;screenshot_bytes=$budget.bytes;offline_disk_readback_verified=$false}
    $evidence | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'guest-write-ack.json') -Encoding UTF8
    return $evidence
}
