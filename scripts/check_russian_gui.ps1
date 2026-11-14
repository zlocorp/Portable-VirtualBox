# Read-only compiled launcher localization acceptance; no Oracle/UAC actions.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Launcher, [string]$EvidenceDirectory='build/russian-gui')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $Launcher).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('PVBox Russian GUI Тест '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$exe=Join-Path $root 'Portable-VirtualBox.exe'
Copy-Item -LiteralPath $source -Destination $exe
# Only this new fixture's window is inspected and captured.
New-Item -ItemType Directory -Path $EvidenceDirectory -ErrorAction Stop | Out-Null
$evidence=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class LocaleWindow {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 public class Control { public IntPtr Handle; public string Class,Text; public bool Fits; public int Width,Height,TextWidth,TextHeight; }
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc f,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,UIntPtr w,StringBuilder s,uint f,uint t,out UIntPtr r);
 [DllImport("user32.dll")] static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,UIntPtr w,IntPtr p,uint f,uint t,out UIntPtr r);
 [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr p);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h,IntPtr dc);
 [DllImport("user32.dll")] static extern int GetWindowLongW(IntPtr h,int i);
 [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
 [DllImport("gdi32.dll")] static extern IntPtr GetStockObject(int i);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int DrawTextW(IntPtr dc,string t,int n,ref Rect r,uint flags);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 public static string Text(IntPtr h) {
  var s=new StringBuilder(4096);UIntPtr r;
  if(SendMessageTimeoutW(h,13,(UIntPtr)4096,s,3,250,out r)==IntPtr.Zero) throw new Exception("Window text unavailable");
  return s.ToString();
 }
 static string Class(IntPtr h) {var s=new StringBuilder(256);GetClassNameW(h,s,256);return s.ToString();}
 public static IntPtr Find(int pid,string title) {
  IntPtr found=IntPtr.Zero;int count=0;
  EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);
   if(id==pid && IsWindowVisible(h) && Class(h)=="AutoIt v3 GUI" && Text(h)==title) {found=h;count++;}
   return true;},IntPtr.Zero);return count==1?found:IntPtr.Zero;
 }
 public static Control[] Controls(IntPtr owner,int pid) {
  var rows=new List<Control>();
  EnumChildWindows(owner,(h,p)=>{
   if(rows.Count>=128) throw new Exception("Control count exceeds bound");
   uint id;GetWindowThreadProcessId(h,out id);if(id!=pid || !IsWindowVisible(h)) return true;
   var c=new Control{Handle=h,Class=Class(h),Text=Text(h),Fits=true};Rect r;
   if(!GetClientRect(h,out r)) throw new Exception("Control rectangle unavailable");
   c.Width=r.Right-r.Left;c.Height=r.Bottom-r.Top;
   if(c.Class=="Button" && c.Text.Length>0) {
    UIntPtr value;if(SendMessageTimeoutW(h,0x31,UIntPtr.Zero,IntPtr.Zero,3,250,out value)==IntPtr.Zero) throw new Exception("Control font unavailable");
    IntPtr font=new IntPtr(unchecked((long)value.ToUInt64()));if(font==IntPtr.Zero) font=GetStockObject(17);
    IntPtr dc=GetDC(h);if(dc==IntPtr.Zero) throw new Exception("Control device context unavailable");
    IntPtr old=SelectObject(dc,font);
    try {
     uint flags=0x400|0x800; // CALCRECT | NOPREFIX: actual font, not guessed char count
     flags|=(GetWindowLongW(h,-16)&0x2000)!=0?0x10u:0x20u;
     Rect measure=new Rect{Right=Math.Max(1,c.Width-24)};
     if(DrawTextW(dc,c.Text,c.Text.Length,ref measure,flags)==0) throw new Exception("Text measurement failed");
     c.TextWidth=measure.Right-measure.Left;c.TextHeight=measure.Bottom-measure.Top;
     c.Fits=c.TextWidth<=c.Width-16 && c.TextHeight<=c.Height-6;
    } finally {SelectObject(dc,old);ReleaseDC(h,dc);}
   }
   rows.Add(c);return true;
  },IntPtr.Zero);return rows.ToArray();
 }
}
'@
function Await-View([Diagnostics.Process]$Process,[string]$Title,[string]$ExpectedHint) {
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    do {
        if($Process.HasExited){throw 'Launcher exited before localized view'}
        $window=[LocaleWindow]::Find($Process.Id,$Title)
        if($window -ne [IntPtr]::Zero){
            $rows=[LocaleWindow]::Controls($window,$Process.Id)
            if(@($rows | Where-Object {$_.Text.Contains($ExpectedHint)}).Count -gt 0){return $window}
        }
        Start-Sleep -Milliseconds 100
    } while([DateTime]::UtcNow -lt $deadline)
    throw "Localized view not observed: $Title"
}
function Capture-View([Diagnostics.Process]$Process,[IntPtr]$Window,[string]$Label,[string[]]$Captions) {
    $rows=[LocaleWindow]::Controls($Window,$Process.Id)
    foreach($caption in $Captions){
        if(@($rows | Where-Object {$_.Class -eq 'Button' -and $_.Text -ceq $caption}).Count -ne 1){throw "Missing exact localized button: $caption"}
    }
    $rows | Select-Object Class,Text,Width,Height,TextWidth,TextHeight,Fits | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $evidence ($Label+'.json')) -Encoding utf8
    $rect=[LocaleWindow+Rect]::new()
    if(-not [LocaleWindow]::GetWindowRect($Window,[ref]$rect)){throw 'Window rectangle missing'}
    $width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top
    if($width -lt 100 -or $height -lt 100 -or $width -gt 3000 -or $height -gt 3000){throw 'Unexpected screenshot dimensions'}
    $bitmap=[Drawing.Bitmap]::new($width,$height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $dc=$graphics.GetHdc()
        try{if(-not [LocaleWindow]::PrintWindow($Window,$dc,2)){throw 'Window capture failed'}}finally{$graphics.ReleaseHdc($dc)}
        $bitmap.Save((Join-Path $evidence ($Label+'.png')),[Drawing.Imaging.ImageFormat]::Png)
    }finally{$graphics.Dispose();$bitmap.Dispose()}
    if(@($rows | Where-Object {-not $_.Fits}).Count -gt 0){throw "Caption exceeds its actual control in $Label; see evidence JSON/PNG"}
}
function Click-Exact([Diagnostics.Process]$Process,[IntPtr]$Window,[string]$Caption){
    $matches=@([LocaleWindow]::Controls($Window,$Process.Id) | Where-Object {$_.Class -eq 'Button' -and $_.Text -ceq $Caption})
    if($matches.Count -ne 1 -or -not [LocaleWindow]::PostMessageW($matches[0].Handle,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)){throw "Could not select language: $Caption"}
}
$process=$null;$window=[IntPtr]::Zero
try{
    $process=Start-Process -FilePath $exe -ArgumentList '--lang ru' -PassThru -WorkingDirectory $root
    $null=$process.Handle # retain the actual process identity/exit code
    $window=Await-View $process 'Портативный VirtualBox' 'Копируется только папка data. Диски ВМ вне data не включены.'
    Capture-View $process $window 'launcher-ru' @('Русский','Английский','Запомнить язык','Восстановить в новую папку','Отменить копирование')
    Click-Exact $process $window 'Английский'
    $window=Await-View $process 'Portable-VirtualBox' 'Backs up data only'
    Capture-View $process $window 'launcher-en' @('Russian','English','Save language','Restore to new folder','Cancel copy')
    Click-Exact $process $window 'Russian'
    $window=Await-View $process 'Портативный VirtualBox' 'Копируется только папка data. Диски ВМ вне data не включены.'
    Capture-View $process $window 'launcher-ru-return' @('Запомнить язык','Восстановить в новую папку')
    if(-not [LocaleWindow]::PostMessageW($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)){throw 'Could not close owned fixture window'}
    if(-not $process.WaitForExit(10000) -or $process.ExitCode -ne 2){throw 'Read-only GUI did not exit normally'}
    if(@(Get-ChildItem -LiteralPath $root -Force).Count -ne 1){throw 'Language switching wrote portable files'}
    Write-Host 'PASS: actual RU/EN/RU launcher controls, preserved read-only state and font measurements; PNGs require visual review'
}finally{
    if($null -ne $process){
        if(-not $process.HasExited -and $window -ne [IntPtr]::Zero){
            $null=[LocaleWindow]::PostMessageW($window,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
            if(-not $process.WaitForExit(10000)){Write-Warning 'Owned fixture still alive; not killed'}
        }
        $process.Dispose()
    }
}
