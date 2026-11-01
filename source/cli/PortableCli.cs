// Medium-token CLI for an already prepared, build-paired portable session.
// UI concept: portable VBoxManage wrappers / upstream issue #103. Independent
// implementation, no PocketVBox binaries/source or legacy runtime imported.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;
namespace PortableVBox {
 public static class PortableCli {
  internal static string ArgumentLine(string[] args) {
   var line=new StringBuilder();
   foreach(string arg in args) {
    if(arg==null || arg.IndexOf('\0')>=0) throw new InvalidOperationException("Invalid argument");
    if(line.Length>0) line.Append(' ');
    line.Append('"');int backslashes=0;
    foreach(char c in arg) {
     if(c=='\\') {backslashes++;continue;}
     if(c=='"') line.Append('\\',backslashes*2+1);else line.Append('\\',backslashes);
     backslashes=0;line.Append(c);
    }
    line.Append('\\',backslashes*2);line.Append('"');
    if(line.Length>30000) throw new InvalidOperationException("Command line exceeds supported bound");
   }
   return line.ToString();
  }
  internal static ProcessStartInfo Command(string exe,string[] args,string cwd,string profile) {
   var info=new ProcessStartInfo {FileName=exe,Arguments=ArgumentLine(args),WorkingDirectory=cwd,UseShellExecute=false};
   info.EnvironmentVariables["VBOX_USER_HOME"]=profile;
   return info;
  }
  internal static void CheckArguments(string[] args) {
   if(args==null || args.Length==0) throw new InvalidOperationException("Oracle command required");
   bool unregister=false,delete=false;
   foreach(string a in args) {
    if(String.Equals(a,"unregistervm",StringComparison.OrdinalIgnoreCase)) unregister=true;
    if(a.StartsWith("--delete",StringComparison.OrdinalIgnoreCase) || a.StartsWith("-delete",StringComparison.OrdinalIgnoreCase)) delete=true;
   }
   if(unregister && delete) throw new InvalidOperationException("Destructive unregister is not supported by the portable adapter");
  }
  static string Text(Dictionary<string,object> d,string k) {
   object value;if(d==null || !d.TryGetValue(k,out value) || !(value is string)) throw new InvalidOperationException("Missing receipt field: "+k);
   return (string)value;
  }
  static int Number(Dictionary<string,object> d,string k) {
   object value;if(d==null || !d.TryGetValue(k,out value) || !(value is int)) throw new InvalidOperationException("Invalid numeric receipt field: "+k);
   return (int)value;
  }
  static bool Flag(Dictionary<string,object> d,string k) {
   object value;return d!=null && d.TryGetValue(k,out value) && value is bool && (bool)value;
  }
  internal static bool Medium(TokenFacts f) {return f!=null && !f.Administrator && !f.Elevated && f.Integrity>=8192 && f.Integrity<12288;}
  internal static void ValidateBinding(Dictionary<string,object> binding,Dictionary<string,object> receipt,TokenFacts controller,TokenFacts caller,string root,string session,int pid,int cycle) {
   string image=Path.Combine(root,PinnedBuild.FrontendName);
   if(pid<1 || pid>999999999 || cycle<1 || cycle>999 || !Medium(controller) || !Medium(caller) || controller.Session!=caller.Session || controller.Sid!=caller.Sid ||
      controller.Pid!=pid || !CliFiles.Same(controller.Image,image) || Number(binding,"pid")!=pid || Number(binding,"cycle")!=cycle ||
      Text(binding,"created")!=controller.Created.ToString(CultureInfo.InvariantCulture) || Text(binding,"sid")!=caller.Sid ||
      !CliFiles.Same(Text(binding,"image"),image) || !CliFiles.Same(Text(binding,"root"),root) ||
      Number(receipt,"schema")!=1 || !Flag(receipt,"prepared") || Number(receipt,"controller_pid")!=pid ||
      Text(receipt,"controller_created_filetime")!=Text(binding,"created") || !CliFiles.Same(Text(receipt,"controller_image"),image) ||
      !CliFiles.Same(Text(receipt,"portable_root"),root) || !CliFiles.Same(Text(receipt,"protected_app"),Path.Combine(session,"app64")))
    throw new InvalidOperationException("Portable session/controller identity mismatch");
  }
  static void Host(string root) {
   if(!Environment.Is64BitProcess || !Environment.Is64BitOperatingSystem) throw new InvalidOperationException("Windows x64 required");
   if(PinnedBuild.Mode=="ALPHA") return; // The exact live ALPHA frontend and protected helper already enforce workstation policy.
   string temp=Environment.GetEnvironmentVariable("RUNNER_TEMP");
   if(PinnedBuild.Mode!="CI" || Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true" ||
      Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted" || Environment.GetEnvironmentVariable("RUNNER_OS")!="Windows" ||
      Environment.GetEnvironmentVariable("GITHUB_REPOSITORY")!="zlocorp/Portable-VirtualBox" || String.IsNullOrEmpty(temp) ||
      !root.StartsWith(CliFiles.Full(temp)+"\\",StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Disposable CI adapter only");
  }
  static void NotFinishing(string session) {
   foreach(string name in new[]{"quiescent-session.json","payload-removed.json","cleanup","recovery-quiescent.json","partial-recovery-quiescent.json"})
    if(File.Exists(Path.Combine(session,name)) || Directory.Exists(Path.Combine(session,name))) throw new InvalidOperationException("Session is finishing or already cleaned");
  }
  static void Services(string runtime) {
   using(var key=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\VBoxSDS")) {
    if(key==null || !(key.GetValue("ImagePath") is string) || !CliFiles.Same(((string)key.GetValue("ImagePath")).Trim().Trim('"'),Path.Combine(runtime,"VBoxSDS.exe")) ||
       !Object.Equals(key.GetValue("Type"),16) || !Object.Equals(key.GetValue("Start"),3) || !Object.Equals(key.GetValue("ObjectName"),"LocalSystem"))
     throw new InvalidOperationException("Different VBoxSDS registration");
   }
   using(var key=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\VBoxSup")) {
    if(key==null || !Object.Equals(key.GetValue("Type"),1) || !Object.Equals(key.GetValue("Start"),1) ||
       !(key.GetValue("ImagePath") is string) || !CliFiles.Same((string)key.GetValue("ImagePath"),@"\SystemRoot\System32\drivers\VBoxSup.sys"))
     throw new InvalidOperationException("Different VBoxSup registration");
   }
   using(var sup=new ServiceController("VBoxSup")) if(sup.Status!=ServiceControllerStatus.Running) throw new InvalidOperationException("VBoxSup is not running");
  }
  static int Execute(string[] args) {
   CheckArguments(args);
   string root=CliFiles.Full(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location));
   Host(root);
   var caller=TokenFacts.Read(Process.GetCurrentProcess().Id);
   if(!Medium(caller)) throw new InvalidOperationException("Run the adapter as an ordinary medium-token user, not as administrator");
   string store=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),PinnedBuild.Mode=="ALPHA"?"PortableVirtualBox.Alpha":"PortableVirtualBox.Experiment");
   string profile=Path.Combine(root,@"data\.VirtualBox");
   using(var files=new CliFiles()) {
    files.LockParents(root);files.LockParents(profile);files.LockDirectory(Path.Combine(root,@"data\Machines"));files.LockDirectory(Path.Combine(root,"logs"));
    if(CliFiles.Hash(files.Open(Path.Combine(root,PinnedBuild.FrontendName)))!=PinnedBuild.FrontendSha256) throw new InvalidOperationException("Frontend is not paired to this CLI build");
    files.Protected(store,caller.Sid);
    string session=null;Dictionary<string,object> binding=null;int pid=0,cycle=0;
    foreach(string folder in Directory.GetDirectories(store,"pvbox-manager-*",SearchOption.TopDirectoryOnly)) {
     if(File.Exists(Path.Combine(folder,"payload-removed.json"))) continue;
     if(!File.Exists(Path.Combine(folder,"controller.json")) || !File.Exists(Path.Combine(folder,"session.json"))) continue;
     files.Protected(folder,caller.Sid);
     var b=files.ReadJson(Path.Combine(folder,"controller.json"),16384);
     if(!CliFiles.Same(Text(b,"root"),root)) continue;
     var match=Regex.Match(Path.GetFileName(folder),@"^pvbox-manager-([1-9][0-9]{0,8})-([1-9][0-9]{0,2})$");
     if(!match.Success || session!=null) throw new InvalidOperationException("Ambiguous portable session");
     session=folder;binding=b;pid=int.Parse(match.Groups[1].Value,CultureInfo.InvariantCulture);cycle=int.Parse(match.Groups[2].Value,CultureInfo.InvariantCulture);
    }
    if(session==null) throw new InvalidOperationException("No prepared session. Start VirtualBox in the ALPHA Manager window first");
    IntPtr controller=TokenFacts.OpenProcess(0x101000,false,pid);
    if(controller==IntPtr.Zero) throw new InvalidOperationException("Original controller is not available");
    try {
     NotFinishing(session);
     var receipt=files.ReadJson(Path.Combine(session,"session.json"),16384);
     ValidateBinding(binding,receipt,TokenFacts.ReadHandle(controller,pid),caller,root,session,pid,cycle);
     string gate="Local\\PortableVirtualBox.Cli."+pid.ToString(CultureInfo.InvariantCulture)+"."+cycle.ToString(CultureInfo.InvariantCulture);
     using(var mutex=Mutex.OpenExisting(gate,MutexRights.Synchronize|MutexRights.Modify))
     using(var ready=EventWaitHandle.OpenExisting(gate+".Ready",EventWaitHandleRights.Synchronize)) {
      bool acquired=false,release=false;
      try {
       // AbandonedMutexException grants ownership, but that is NOT success.
       // Do not release it: process exit preserves abandonment for the controller.
       acquired=mutex.WaitOne(0);
       if(!acquired) throw new InvalidOperationException("Another portable command or cleanup is active");
       release=true;
       if(!ready.WaitOne(0)) throw new InvalidOperationException("Controller is not accepting portable commands");
       string runtime=Path.Combine(session,"app64");
       files.Protected(runtime,caller.Sid);files.VerifyRuntime(runtime);Services(runtime);
       NotFinishing(session);
       ValidateBinding(binding,receipt,TokenFacts.ReadHandle(controller,pid),caller,root,session,pid,cycle);
       if(!ready.WaitOne(0)) throw new InvalidOperationException("Controller stopped accepting commands");
       // Inherit the caller's actual working directory, stdin/stdout/stderr.
       // No command shell, argument re-expansion, implicit install or elevation.
       var start=Command(Path.Combine(runtime,"VBoxManage.exe"),args,Environment.CurrentDirectory,profile);
       ConsoleCancelEventHandler cancel=(sender,e)=>{e.Cancel=true;};
       Console.CancelKeyPress+=cancel;
       try {
        using(var child=new Process()) {
         child.StartInfo=start;
         // Any uncertain start/exit keeps the lease abandoned on process exit.
         release=false;
         if(!child.Start()) throw new InvalidOperationException("Oracle process did not start");
         child.WaitForExit();int code=child.ExitCode;release=true;return code;
        }
       } finally {Console.CancelKeyPress-=cancel;}
      } finally {if(acquired && release) mutex.ReleaseMutex();}
     }
    } finally {TokenFacts.CloseHandle(controller);}
   }
  }
  public static int Main(string[] args) {
   if(args.Length==1 && args[0]=="--portable-help") {
    Console.WriteLine("VBoxManage.cmd <Oracle arguments>\nRequires the paired ALPHA controller with an active prepared session.\nUses this folder's data\\.VirtualBox; never falls back to an installed VirtualBox.\nNo elevation or driver actions. Finish the session in the launcher.\nNot a VM backup or safety sandbox; unregistervm --delete is refused.");return 0;
   }
   if(args.Length==0) {Console.Error.WriteLine("Usage: VBoxManage.cmd <Oracle arguments> (see --portable-help)");return 64;}
   try {return Execute(args);}
   catch(Exception e) {Console.Error.WriteLine("Portable CLI refused: "+e.Message);return 3;}
  }
 }
}
