# Execute the real adapter argument/binding logic without a driver or Oracle.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-cli-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$pin='namespace PortableVBox { internal static class PinnedBuild { internal const string FrontendSha256="test-only"; internal const string FrontendName="Portable-VirtualBox.exe"; internal const string InventorySha256="test-only"; internal const string Mode="CI"; } }'
[IO.File]::WriteAllText((Join-Path $out 'Pin.cs'),$pin)
$test=@'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
namespace PortableVBox {
 public static class PortableCliTests {
  static int count;
  static void Check(bool ok,string message) { count++;if(!ok) throw new Exception(message); }
  static void Refuses(Action call,string label) { bool failed=false;try {call();}catch(InvalidOperationException){failed=true;} Check(failed,label); }
  static Dictionary<string,object> Copy(Dictionary<string,object> d) {return new Dictionary<string,object>(d);}
  public static int Main(string[] args) {
   if(args.Length>0 && args[0]=="--child") {
    Console.OutputEncoding=new UTF8Encoding(false);
    var tail=new string[args.Length-1];Array.Copy(args,1,tail,0,tail.Length);
    Console.Write(new JavaScriptSerializer().Serialize(tail));
    Console.Error.Write("stderr-preserved");
    return 23;
   }
   string[] inputs={"", "one", "two words", "кириллица", "&echo not-a-shell", "%PATH%", "!", "(x)", "a\"b", "a\\\"b", "ends\\", "two words\\", "\\\\server\\path", "'literal'", "\t", "line\nnext"};
   var invocation=new List<string>();invocation.Add("--child");invocation.AddRange(inputs);
   var start=PortableCli.Command(Process.GetCurrentProcess().MainModule.FileName,invocation.ToArray(),Environment.CurrentDirectory,@"C:\portable profile");
   Check(!start.UseShellExecute,"native process, not shell");
   string parentHome=Environment.GetEnvironmentVariable("VBOX_USER_HOME");
   Check(start.EnvironmentVariables["VBOX_USER_HOME"]==@"C:\portable profile","explicit child profile");
   Check(Environment.GetEnvironmentVariable("VBOX_USER_HOME")==parentHome,"caller environment untouched");
   start.RedirectStandardOutput=true;start.RedirectStandardError=true;
   start.StandardOutputEncoding=new UTF8Encoding(false);
   using(var child=Process.Start(start)) {
    string stdout=child.StandardOutput.ReadToEnd(),stderr=child.StandardError.ReadToEnd();
    child.WaitForExit();
    var got=new JavaScriptSerializer().Deserialize<string[]>(stdout);
    Check(child.ExitCode==23 && stderr=="stderr-preserved","real process exit and stderr");
    Check(got.Length==inputs.Length,"argument count preserved");
    for(int i=0;i<inputs.Length;i++) Check(got[i]==inputs[i],"argument fidelity index "+i);
   }
   Refuses(()=>PortableCli.ArgumentLine(new[]{"bad\0value"}),"NUL refused");
   Refuses(()=>PortableCli.ArgumentLine(new[]{new string('x',32768)}),"Windows command bound");
   Refuses(()=>PortableCli.CheckArguments(new[]{"unregistervm","uuid","--delete"}),"no VM deletion switch");
   Refuses(()=>PortableCli.CheckArguments(new[]{"--nologo","unregistervm","uuid","--delete"}),"global option cannot bypass deletion guard");
   PortableCli.CheckArguments(new[]{"unregistervm","uuid"});
   var controller=new TokenFacts {Pid=123,Created=456,Image=@"C:\portable\Portable-VirtualBox.exe",Sid="S-1-5-21-1",Integrity=8192,Session=2};
   var caller=new TokenFacts {Pid=124,Created=457,Image=@"C:\portable\VBoxManagePortable.exe",Sid=controller.Sid,Integrity=8192,Session=2};
   var binding=new Dictionary<string,object> {{"pid",123},{"created","456"},{"image",controller.Image},{"sid",controller.Sid},{"cycle",3},{"root",@"C:\portable"}};
   var receipt=new Dictionary<string,object> {{"schema",1},{"prepared",true},{"controller_pid",123},{"controller_created_filetime","456"},{"controller_image",controller.Image},{"portable_root",@"C:\portable"},{"protected_app",@"C:\protected\pvbox-manager-123-3\app64"}};
   PortableCli.ValidateBinding(binding,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3);
   foreach(string key in new[]{"created","image","sid","root","pid","cycle"}) {
    var bad=Copy(binding);bad[key]="changed";
    Refuses(()=>PortableCli.ValidateBinding(bad,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"original binding field "+key);
   }
   foreach(string key in new[]{"schema","prepared","controller_pid","controller_created_filetime","controller_image","portable_root","protected_app"}) {
    var bad=Copy(receipt);bad[key]="changed";
    Refuses(()=>PortableCli.ValidateBinding(binding,bad,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"session receipt field "+key);
   }
   controller.Created=999;
   Refuses(()=>PortableCli.ValidateBinding(binding,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"recycled PID");controller.Created=456;
   caller.Administrator=true;
   Refuses(()=>PortableCli.ValidateBinding(binding,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"admin refused");caller.Administrator=false;
   caller.Session=3;
   Refuses(()=>PortableCli.ValidateBinding(binding,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"different desktop session refused");caller.Session=2;
   caller.Sid="S-1-5-21-2";
   Refuses(()=>PortableCli.ValidateBinding(binding,receipt,controller,caller,@"C:\portable",@"C:\protected\pvbox-manager-123-3",123,3),"different SID refused");
   Console.WriteLine("PASS portable CLI: "+count+" native argument/profile/receipt assertions");return 0;
  }
 }
}
'@
[IO.File]::WriteAllText((Join-Path $out 'Test.cs'),$test,[Text.Encoding]::UTF8)
try {
    $exe=Join-Path $out 'CliContract.exe'
    & $csc /nologo /target:exe /platform:x64 /main:PortableVBox.PortableCliTests /reference:System.Web.Extensions.dll /reference:System.ServiceProcess.dll ("/out:"+$exe) (Join-Path $out 'Pin.cs') (Join-Path $out 'Test.cs') (Join-Path $repo 'source/privilege/TokenFacts.cs') (Join-Path $repo 'source/cli/PortableCli.cs') (Join-Path $repo 'source/cli/PortableCli.Files.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Portable CLI contract compilation failed' }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw 'Portable CLI behavioral contract failed' }
} finally { Remove-Item -LiteralPath $out -Recurse -Force }
