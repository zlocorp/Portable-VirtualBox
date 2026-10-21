# Read-only failure evidence from the disposable runner's own Oracle process.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Disposable runner required' }
$out=Join-Path $env:RUNNER_TEMP 'manager-gui-proof'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class ManagerWindows {
 public delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback f,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 public struct Rect { public int Left,Top,Right,Bottom; }
 public class Item { public long Handle; public uint Pid; public string Title; public string Class; public bool Visible; public bool Enabled; public long Owner; }
 public static Item[] List(int pid) {
  var a=new List<Item>(); EnumWindows((h,p)=>{uint n;GetWindowThreadProcessId(h,out n);if(n==pid){
   var t=new StringBuilder(2048);var c=new StringBuilder(256);GetWindowText(h,t,2048);GetClassName(h,c,256);
   a.Add(new Item{Handle=h.ToInt64(),Pid=n,Title=t.ToString(),Class=c.ToString(),Visible=IsWindowVisible(h),Enabled=IsWindowEnabled(h),Owner=GetWindow(h,4).ToInt64()});
  }return true;},IntPtr.Zero); return a.ToArray();
 }
}
'@
$items=@()
foreach ($p in @(Get-Process -Name VirtualBox -ErrorAction SilentlyContinue)) {
 if ($p.MainModule.FileName -ine (Join-Path $PortableRoot 'app64\VirtualBox.exe')) { continue }
 $items+= [ManagerWindows]::List($p.Id)
}
$items | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'oracle-windows.json') -Encoding utf8
foreach ($item in @($items | Where-Object Visible | Select-Object -First 8)) {
 $rect=[ManagerWindows+Rect]::new();$handle=[IntPtr]$item.Handle
 if (-not [ManagerWindows]::GetWindowRect($handle,[ref]$rect)) { continue }
 $w=$rect.Right-$rect.Left;$h=$rect.Bottom-$rect.Top
 if ($w -lt 1 -or $h -lt 1 -or $w -gt 3000 -or $h -gt 2000) { continue }
 $bitmap=[Drawing.Bitmap]::new($w,$h);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 try {$dc=$graphics.GetHdc();try{$ok=[ManagerWindows]::PrintWindow($handle,$dc,2)}finally{$graphics.ReleaseHdc($dc)}
  if($ok){$bitmap.Save((Join-Path $out ('window-'+$item.Handle+'.png')),[Drawing.Imaging.ImageFormat]::Png)}
 }finally{$graphics.Dispose();$bitmap.Dispose()}
}
$items | Format-Table Handle,Pid,Title,Class,Visible,Enabled,Owner -AutoSize
