# Read-only failure evidence from the disposable runner's own controller/Oracle.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot,[int]$ControllerProcessId=0)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Disposable runner required' }
$out=Join-Path $env:RUNNER_TEMP 'manager-gui-proof'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Add-Type -AssemblyName System.Drawing
if (-not ('ManagerWindows' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Diagnostics;
public static class ManagerWindows {
 public delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback f,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,Callback f,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,UIntPtr w,StringBuilder b,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint n);
 [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 public struct Rect { public int Left,Top,Right,Bottom; }
 public class Item { public long Handle; public uint Pid; public string Title; public string Class; public bool Visible; public bool Enabled; public long Owner; public long Parent; public int ControlId; public bool TopLevel; }
 public static Item[] List(int pid) {
  var a=new List<Item>(); EnumWindows((h,p)=>{uint n;GetWindowThreadProcessId(h,out n);if(n==pid){
   var t=new StringBuilder(2048);var c=new StringBuilder(256);GetWindowText(h,t,2048);GetClassName(h,c,256);
   a.Add(new Item{Handle=h.ToInt64(),Pid=n,Title=t.ToString(),Class=c.ToString(),Visible=IsWindowVisible(h),Enabled=IsWindowEnabled(h),Owner=GetWindow(h,4).ToInt64(),TopLevel=true});
  }return true;},IntPtr.Zero); return a.ToArray();
 }
 static Item Describe(IntPtr h,uint pid,bool topLevel) {
  var t=new StringBuilder(2048);var c=new StringBuilder(256);UIntPtr result;
  GetClassName(h,c,256);
  if(topLevel) GetWindowText(h,t,2048);
  else if(SendMessageTimeoutW(h,13,(UIntPtr)2048,t,3,100,out result)==IntPtr.Zero) t.Clear();
  return new Item{Handle=h.ToInt64(),Pid=pid,Title=t.ToString(),Class=c.ToString(),Visible=IsWindowVisible(h),Enabled=IsWindowEnabled(h),Owner=GetWindow(h,4).ToInt64(),Parent=GetParent(h).ToInt64(),ControlId=GetDlgCtrlID(h),TopLevel=topLevel};
 }
 public static Item[] Controller(int pid) {
  // Bound both the number of controls and time spent reading a hung UI.
  var a=new List<Item>();var timer=Stopwatch.StartNew();
  EnumWindows((h,p)=> {
   if(a.Count>=128 || timer.ElapsedMilliseconds>=5000) return false;
   uint n;GetWindowThreadProcessId(h,out n);if(n!=pid) return true;
   a.Add(Describe(h,n,true));
   if(IsWindowVisible(h)) EnumChildWindows(h,(child,x)=> {
    if(a.Count>=128 || timer.ElapsedMilliseconds>=5000) return false;
    uint childPid;GetWindowThreadProcessId(child,out childPid);
    if(childPid==pid) a.Add(Describe(child,childPid,false));
    return true;
   },IntPtr.Zero);
   return true;
  },IntPtr.Zero);
  return a.ToArray();
 }
}
'@
}
$controllerPaths=@((Join-Path $PortableRoot 'Portable-VirtualBox.exe'),(Join-Path $PortableRoot 'Portable-VirtualBox-Session-Test.exe'))
$controllers=if($ControllerProcessId -gt 0) {
 @(Get-Process -Id $ControllerProcessId -ErrorAction SilentlyContinue)
} else {
 @(Get-Process -Name 'Portable-VirtualBox','Portable-VirtualBox-Session-Test' -ErrorAction SilentlyContinue)
}
foreach($controller in $controllers) {
 try {
  if($controller.MainModule.FileName -notin $controllerPaths) { continue }
  $controllerItems=@([ManagerWindows]::Controller($controller.Id))
  ConvertTo-Json -InputObject $controllerItems -Depth 4 | Set-Content -LiteralPath (Join-Path $out ('controller-windows-'+$controller.Id+'.json')) -Encoding utf8
  Write-Host "Controller UI evidence: PID $($controller.Id), $($controllerItems.Count) windows/controls (128 item / 5 second limit)"
  $controllerItems | Where-Object { $_.TopLevel -or $_.Class -in @('Edit','Button','ComboBox','ComboBoxEx32','Static') } |
   Select-Object -First 48 | Format-Table Handle,Parent,ControlId,Title,Class,Visible,Enabled,Owner -AutoSize
 } catch { Write-Warning ('Controller UI evidence unavailable: '+$_.Exception.Message) }
}
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
# Read the Oracle profile log before its processes are released. Do not copy
# VM media, arbitrary user files, or replace any Oracle setting.
$profile=Join-Path $PortableRoot 'data\.VirtualBox'
foreach ($name in @('VBoxSVC.log','VBoxSDS.log','selectorwindow.log')) {
 $path=Join-Path $profile $name
 if (Test-Path -LiteralPath $path -PathType Leaf) {
  Get-Content -LiteralPath $path -Tail 160 | Set-Content -LiteralPath (Join-Path $out $name.Replace('.log','-tail.txt')) -Encoding utf8
 }
}
# Accessibility exposes Qt's error details without guessing an OK answer.
try {
 Add-Type -AssemblyName UIAutomationClient
 Add-Type -AssemblyName UIAutomationTypes
 $nodes=@()
 foreach ($item in @($items | Where-Object { $_.Visible -and $_.Title -like '*Error*' })) {
  $element=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$item.Handle)
  $all=$element.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
  foreach ($child in $all) {
   $nodes+=[ordered]@{name=$child.Current.Name;type=$child.Current.ControlType.ProgrammaticName;id=$child.Current.AutomationId;patterns=@($child.GetSupportedPatterns() | ForEach-Object ProgrammaticName)}
  }
 }
 $nodes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'oracle-error-accessibility.json') -Encoding utf8
} catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $out 'accessibility-error.txt') }
