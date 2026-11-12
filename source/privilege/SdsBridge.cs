// Closed embedded bridge. Loaded only from the hash-checked, leased session/code
// resource by the fixed helper worker. This is not a general privileged launcher.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
 public enum SdsOperation { Register, UnregisterFull, UnregisterPartial }
 public sealed class SdsResult {
  public bool WithinDeadline {get;private set;}
  public bool ExitCodeKnown {get;private set;}
  public int ExitCode {get;private set;}
  public long ElapsedMs {get;private set;}
  internal SdsResult(bool deadline,bool known,int exitCode,long elapsed) {WithinDeadline=deadline;ExitCodeKnown=known;ExitCode=exitCode;ElapsedMs=elapsed;}
 }
 public static class SdsBridge {
  const string BridgeName="PortableVBox.SdsBridge.dll";
  static SecurityIdentifier Admins {get{return new SecurityIdentifier("S-1-5-32-544");}}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder name,uint size,uint flags);
  static bool Equal(string a,string b){return String.Equals(a,b,StringComparison.OrdinalIgnoreCase);}
  static string Hash(Stream stream){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}
  static string Hash(byte[] bytes){using(var stream=new MemoryStream(bytes))return Hash(stream);}
  static string Full(string path){
   string full=Path.GetFullPath(path).TrimEnd('\\');
   if(full.Length<4||full.Length>240||full[1]!=':'||full[2]!='\\'||full.IndexOf(':',2)>=0||full.IndexOfAny(new[]{'"','\r','\n','\0'})>=0)throw new InvalidOperationException("Invalid fixed SDS path");
   return full;
  }
  static bool Under(string path,string root){return path.StartsWith(root.TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase);}
  static void ValidateDeadline(SdsOperation operation,int seconds){
   if(operation==SdsOperation.Register){if(seconds==30)return;}
   else if(operation==SdsOperation.UnregisterFull){if(seconds>=5&&seconds<=90)return;}
   else if(operation==SdsOperation.UnregisterPartial){if(seconds>=10&&seconds<=75)return;}
   throw new InvalidOperationException("Unknown SDS operation/deadline");
  }
  static DirectorySecurity ExpectedSecurity(string sid){
   var security=new DirectorySecurity();
   security.SetSecurityDescriptorSddlForm("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;"+sid+")(A;OICI;RC;;;OW)");
   return security;
  }
  static void CheckProtected(string path,string sid){
   var actual=Directory.GetAccessControl(path,AccessControlSections.Owner|AccessControlSections.Access);
   if(!actual.GetOwner(typeof(SecurityIdentifier)).Equals(Admins)||!actual.AreAccessRulesProtected||
      actual.GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access)!=ExpectedSecurity(sid).GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access))
    throw new InvalidOperationException("Untrusted fixed SDS directory ACL/owner");
  }
  static void CheckInheritedCleanup(string path,string sid){
   // New-Item creates cleanup beneath the protected session. Inherited ACE flags
   // may differ, but every effective principal/right must be exactly the template.
   var actual=Directory.GetAccessControl(path,AccessControlSections.Owner|AccessControlSections.Access);
   var owner=(SecurityIdentifier)actual.GetOwner(typeof(SecurityIdentifier));
   if((!owner.Equals(Admins)&&owner.Value!=sid)||!actual.AreAccessRulesCanonical)throw new InvalidOperationException("Untrusted SDS output owner");
   var wanted=new Dictionary<string,int>(StringComparer.Ordinal){
    {"S-1-5-18",0x1f01ff},{"S-1-5-32-544",0x1f01ff},{sid,0x1200a9},{"S-1-3-4",0x20000}};
   foreach(FileSystemAccessRule rule in actual.GetAccessRules(true,true,typeof(SecurityIdentifier))){
    string principal=rule.IdentityReference.Value;int mask;
    if(!wanted.TryGetValue(principal,out mask)||rule.AccessControlType!=AccessControlType.Allow||
       (int)rule.FileSystemRights!=mask||rule.InheritanceFlags!=(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)||
       rule.PropagationFlags!=PropagationFlags.None)throw new InvalidOperationException("Untrusted SDS output ACL");
    wanted.Remove(principal);
   }
   if(wanted.Count!=0)throw new InvalidOperationException("Incomplete SDS output ACL");
  }
  sealed class Admission : IDisposable {
   readonly List<IDisposable> held=new List<IDisposable>();
   readonly HashSet<string> directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   internal void Hold(IDisposable value){held.Add(value);}
   internal void Directory(string path){
    path=Path.GetFullPath(path);
    if(!directories.Add(path))return;
    var attrs=System.IO.File.GetAttributes(path);
    if((attrs&FileAttributes.ReparsePoint)!=0||(attrs&FileAttributes.Directory)==0)throw new InvalidOperationException("Unsafe SDS directory");
    var handle=CreateFileW(path,0x81,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
    if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
    Hold(handle);CheckFinal(handle,path);
    if((System.IO.File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("Changed SDS directory");
   }
   internal void Parents(string path){
    var chain=new List<string>();var d=new DirectoryInfo(path);
    while(d!=null){chain.Add(d.FullName);d=d.Parent;}
    chain.Reverse();foreach(string item in chain)Directory(item);
   }
   internal FileStream File(string path){
    Parents(Path.GetDirectoryName(path));
    if((System.IO.File.GetAttributes(path)&(FileAttributes.ReparsePoint|FileAttributes.Directory))!=0)throw new InvalidOperationException("Unsafe SDS input");
    var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
    Hold(file);CheckFinal(file.SafeFileHandle,path);return file;
   }
   static void CheckFinal(SafeFileHandle handle,string expected){
    var actual=new StringBuilder(32768);uint count=GetFinalPathNameByHandle(handle,actual,(uint)actual.Capacity,0);
    if(count==0||count>=actual.Capacity||!Equal(actual.ToString().Replace("\\\\?\\",""),expected))throw new InvalidOperationException("Changed SDS input identity");
   }
   public void Dispose(){for(int i=held.Count-1;i>=0;i--)held[i].Dispose();}
  }
  static Dictionary<string,object> ValidateManifest(Dictionary<string,object> manifest){
   var rows=new List<string>();long bytes=0;var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(Dictionary<string,object> row in (IEnumerable)manifest["files"]){
    string path=(string)row["path"],digest=(string)row["sha256"];long size=Convert.ToInt64(row["size"],CultureInfo.InvariantCulture);
    if(String.IsNullOrEmpty(path)||path.IndexOfAny(new[]{'\t','\r','\n','\0'})>=0||size<0||!Regex.IsMatch(digest,"\\A[0-9a-f]{64}\\z")||!paths.Add(path))throw new InvalidOperationException("Invalid fixed SDS inventory row");
    rows.Add(path+"\t"+size.ToString(CultureInfo.InvariantCulture)+"\t"+digest+"\n");bytes=checked(bytes+size);
   }
   rows.Sort(StringComparer.Ordinal);
   if(rows.Count!=185||bytes!=247834716||Convert.ToInt32(manifest["file_count"])!=185||Convert.ToInt64(manifest["total_bytes"])!=247834716||
      Hash(Encoding.UTF8.GetBytes(String.Concat(rows)))!=PinnedBuild.InventorySha256)throw new InvalidOperationException("Forged or changed fixed SDS inventory");
   return manifest;
  }
  static void HoldPayload(Admission admission,string app,string sid){
   var manifestFile=admission.File(Path.Combine(app,".prepared.json"));
   if(manifestFile.Length<1||manifestFile.Length>131072)throw new InvalidOperationException("Invalid SDS inventory size");
   Dictionary<string,object> manifest;
   using(var reader=new StreamReader(manifestFile,Encoding.UTF8,true,4096,true))
    manifest=ValidateManifest(new JavaScriptSerializer {MaxJsonLength=262144}.Deserialize<Dictionary<string,object>>(reader.ReadToEnd()));
   bool sds=false;
   foreach(Dictionary<string,object> row in (IEnumerable)manifest["files"]){
    string relative=((string)row["path"]).Replace('/','\\');
    if(Path.IsPathRooted(relative)||relative.Contains("..")||relative.IndexOfAny(new[]{':','"','\r','\n','\0'})>=0)throw new InvalidOperationException("Invalid SDS inventory path");
    string path=Full(Path.Combine(app,relative));
    if(!Under(path,app))throw new InvalidOperationException("SDS inventory traversal");
    var d=new DirectoryInfo(Path.GetDirectoryName(path));
    while(d!=null&&Under(d.FullName,app)){admission.Directory(d.FullName);CheckProtected(d.FullName,sid);d=d.Parent;}
    var file=admission.File(path);
    if(file.Length!=Convert.ToInt64(row["size"])||Hash(file)!=(string)row["sha256"])throw new InvalidOperationException("Changed fixed SDS payload");
    if(Equal(relative,"VBoxSDS.exe"))sds=true;
   }
   if(!sds)throw new InvalidOperationException("Missing pinned SDS image");
  }
  public static SdsResult Run(SdsOperation operation,int timeoutSeconds){
   ValidateDeadline(operation,timeoutSeconds);
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT||!Environment.Is64BitProcess)throw new InvalidOperationException("Fixed SDS bridge requires Windows x64");
   using(var identity=WindowsIdentity.GetCurrent()){
    if(!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))throw new InvalidOperationException("Fixed SDS bridge requires elevation");
    string sid=identity.User.Value;
    if(PinnedBuild.Mode!="CI"&&PinnedBuild.Mode!="ALPHA")throw new InvalidOperationException("Unknown fixed SDS build mode");
    if(Environment.GetEnvironmentVariable("PVBOX_FIXED_HELPER_MODE")!=PinnedBuild.Mode)throw new InvalidOperationException("Fixed SDS build mode mismatch");
    string bridge=Full(typeof(SdsBridge).Assembly.Location),code=Path.GetDirectoryName(bridge),session=Path.GetDirectoryName(code);
    string store=Full(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),PinnedBuild.Mode=="ALPHA"?"PortableVirtualBox.Alpha":"PortableVirtualBox.Experiment"));
    if(!Equal(Path.GetFileName(bridge),BridgeName)||!Equal(Path.GetFileName(code),"code")||!Equal(Path.GetDirectoryName(session),store)||
       !Regex.IsMatch(Path.GetFileName(session),"\\Apvbox-manager-[1-9][0-9]*-[1-9][0-9]*\\z"))throw new InvalidOperationException("Untrusted fixed SDS assembly origin");
    using(var process=Process.GetCurrentProcess())
     if(!Equal(process.MainModule.FileName,Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe")))throw new InvalidOperationException("Fixed SDS bridge requires fixed PowerShell worker");
    string app=Path.Combine(session,"app64"),output=operation==SdsOperation.Register?session:Path.Combine(session,"cleanup");
    using(var admission=new Admission()){
     admission.Parents(code);
     foreach(string path in new[]{store,session,code,app}){admission.Directory(path);CheckProtected(path,sid);}
     admission.File(bridge);
     HoldPayload(admission,app,sid);
     if(operation!=SdsOperation.Register){admission.Directory(output);CheckInheritedCleanup(output,sid);}
     // Empty durable files are prelaunch attempt evidence, not disposable logs.
     using(var files=new SdsDiagnosticFiles(output,operation==SdsOperation.Register?"sds-register":"sds-unregister")){
      var timer=Stopwatch.StartNew();
      using(var child=FixedEffectWorker.RunSds(Path.Combine(app,"VBoxSDS.exe"),operation!=SdsOperation.Register,timeoutSeconds)){
       long elapsed=timer.ElapsedMilliseconds;
       string stdout=child.StandardOutput.GetAwaiter().GetResult(),stderr=child.StandardError.GetAwaiter().GetResult();
       files.WriteCompleted(stdout,stderr);
       child.VerifyImageObservation();
       return new SdsResult(child.WithinDeadline,child.ExitCodeKnown,child.ExitCode,elapsed);
      }
     }
    }
   }
  }
 }
}
