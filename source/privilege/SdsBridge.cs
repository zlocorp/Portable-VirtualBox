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
 public enum EffectPurpose { Preparation, FullCleanup, PartialCleanup }
 public enum DriverOperation { AddSupPackage, StartSup, StopSup, RemoveSupPackage, DeleteSupService }
 public sealed class FixedEffectContext {
  readonly SdsBridge.ContextState state;
  internal FixedEffectContext(SdsBridge.ContextState value){state=value;}
  public SdsResult RunSds(SdsOperation operation,int timeoutSeconds){return SdsBridge.RunSds(state,operation,timeoutSeconds);}
  public SdsResult RunDriver(DriverOperation operation,int timeoutSeconds){return SdsBridge.RunDriver(state,operation,timeoutSeconds);}
 }
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
  static string ValidateStoreLocator(string locator,string mode){
   string leaf=mode=="CI"?"PortableVirtualBox.Experiment":mode=="ALPHA"?"PortableVirtualBox.Alpha":null;
   if(leaf==null||String.IsNullOrEmpty(locator)||locator.Length<4||locator.Length>240||
      !((locator[0]>='A'&&locator[0]<='Z')||(locator[0]>='a'&&locator[0]<='z'))||locator[1]!=':'||locator[2]!='\\')
    throw new InvalidOperationException("Invalid fixed SDS parent store locator");
   for(int i=0;i<locator.Length;i++)
    if(Char.IsControl(locator[i])||locator[i]=='/'||locator[i]=='"'||locator[i]=='<'||locator[i]=='>'||
       locator[i]=='|'||locator[i]=='?'||locator[i]=='*'||locator[i]=='~'||(i!=1&&locator[i]==':'))
     throw new InvalidOperationException("Invalid fixed SDS parent store locator");
   string[] parts=locator.Substring(3).Split('\\');
   foreach(string part in parts)
    if(part.Length==0||part=="."||part==".."||Char.IsWhiteSpace(part[0])||Char.IsWhiteSpace(part[part.Length-1])||
       part[part.Length-1]=='.'||Regex.IsMatch(part,@"\A(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$)(?:\.|\z)",RegexOptions.IgnoreCase|RegexOptions.CultureInvariant))
     throw new InvalidOperationException("Invalid fixed SDS parent store locator");
   if(!Equal(parts[parts.Length-1],leaf))throw new InvalidOperationException("Fixed SDS parent store mode mismatch");
   // Lexical spelling only. Existing final-handle identity/reparse/ACL checks
   // below establish the filesystem identity; this value is never authority.
   return locator;
  }
  static string ModeToken(string value){return value=="CI"||value=="ALPHA"?value:(value==null?"missing":"unknown");}
  static string Bit(bool value){return value?"true":"false";}
  // Exact existing admission predicates, factored only to identify the failing
  // comparison. Never include input paths/names or arbitrary environment text.
  static string OriginFailure(string leaf,string codeLeaf,string storeParent,string sessionName,string expectedStore,string expectedMode,string currentMode){
   bool leafMatch=Equal(leaf,BridgeName),codeMatch=Equal(codeLeaf,"code"),storeMatch=Equal(storeParent,expectedStore);
   bool sessionMatch=Regex.IsMatch(sessionName,"\\Apvbox-manager-[1-9][0-9]*-[1-9][0-9]*\\z");
   if(leafMatch&&codeMatch&&storeMatch&&sessionMatch)return null;
   return "Untrusted fixed SDS assembly origin: leaf_match="+Bit(leafMatch)+";code_match="+Bit(codeMatch)+
    ";store_parent_match="+Bit(storeMatch)+";session_name_match="+Bit(sessionMatch)+
    ";expected_mode="+ModeToken(expectedMode)+";current_mode="+ModeToken(currentMode)+
    ";leaf_length="+leaf.Length.ToString(CultureInfo.InvariantCulture)+";code_length="+codeLeaf.Length.ToString(CultureInfo.InvariantCulture)+
    ";store_parent_length="+(storeParent==null?0:storeParent.Length).ToString(CultureInfo.InvariantCulture)+
    ";session_name_length="+sessionName.Length.ToString(CultureInfo.InvariantCulture)+";expected_store_length="+expectedStore.Length.ToString(CultureInfo.InvariantCulture);
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
   internal static void CheckFinal(SafeFileHandle handle,string expected){
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
  static string HoldPayload(Admission admission,string app,string sid){
   var manifestFile=admission.File(Path.Combine(app,".prepared.json"));
   if(manifestFile.Length<1||manifestFile.Length>131072)throw new InvalidOperationException("Invalid SDS inventory size");
   Dictionary<string,object> manifest;
   using(var reader=new StreamReader(manifestFile,Encoding.UTF8,true,4096,true))
    manifest=ValidateManifest(new JavaScriptSerializer {MaxJsonLength=262144}.Deserialize<Dictionary<string,object>>(reader.ReadToEnd()));
   bool sds=false;string infHash=null;
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
    if(Equal(relative,@"drivers\vboxsup\VBoxSup.inf"))infHash=(string)row["sha256"];
   }
   if(!sds||infHash==null)throw new InvalidOperationException("Missing pinned SDS/SUP image");
   return infHash;
  }
  internal sealed class AttemptLedger {
   int attempts;bool failed;
   internal void Begin(int bit){
    if(failed||bit<0||bit>5||(attempts&(1<<bit))!=0)throw new InvalidOperationException("Fixed effect context is exhausted");
    attempts|=1<<bit;
   }
   internal void Observe(SdsResult result){if(!result.WithinDeadline||!result.ExitCodeKnown||result.ExitCode!=0)failed=true;}
   internal void Fail(){failed=true;}
  }
  internal sealed class ContextState {
   internal readonly object Sync=new object();
   internal readonly AttemptLedger Attempts=new AttemptLedger();
   internal readonly EffectPurpose Purpose;
   internal readonly string Bridge,Code,Session,Store,App,Sid,Mode,ProcessImage;
   internal readonly int ProcessId;
   internal readonly long ProcessCreated;
   internal ContextState(EffectPurpose purpose,string bridge,string code,string session,string store,string sid,string mode,int pid,long created,string processImage){
    Purpose=purpose;Bridge=bridge;Code=code;Session=session;Store=store;App=Path.Combine(session,"app64");Sid=sid;Mode=mode;ProcessId=pid;ProcessCreated=created;ProcessImage=processImage;
   }
  }
  static void ValidatePurpose(EffectPurpose purpose){
   if(purpose!=EffectPurpose.Preparation&&purpose!=EffectPurpose.FullCleanup&&purpose!=EffectPurpose.PartialCleanup)throw new InvalidOperationException("Unknown fixed effect purpose");
  }
  static void ValidateDriver(EffectPurpose purpose,DriverOperation operation,int seconds){
   ValidatePurpose(purpose);
   if(purpose==EffectPurpose.Preparation){
    if(operation==DriverOperation.AddSupPackage&&seconds>=15&&seconds<=120)return;
    if(operation==DriverOperation.StartSup&&seconds>=5&&seconds<=60)return;
   } else if(operation==DriverOperation.StopSup||operation==DriverOperation.RemoveSupPackage||operation==DriverOperation.DeleteSupService){
    if(seconds>=(purpose==EffectPurpose.FullCleanup?5:10)&&seconds<=(purpose==EffectPurpose.FullCleanup?90:75))return;
   }
   throw new InvalidOperationException("Driver operation/purpose/deadline mismatch");
  }
  static void ValidateSds(EffectPurpose purpose,SdsOperation operation,int seconds){
   ValidateDeadline(operation,seconds);
   if((purpose==EffectPurpose.Preparation&&operation==SdsOperation.Register)||
      (purpose==EffectPurpose.FullCleanup&&operation==SdsOperation.UnregisterFull)||
      (purpose==EffectPurpose.PartialCleanup&&operation==SdsOperation.UnregisterPartial))return;
   throw new InvalidOperationException("SDS operation/purpose mismatch");
  }
  public static FixedEffectContext Open(EffectPurpose purpose){
   ValidatePurpose(purpose);
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT||!Environment.Is64BitProcess)throw new InvalidOperationException("Fixed effect bridge requires Windows x64");
   using(var identity=WindowsIdentity.GetCurrent()){
    if(!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))throw new InvalidOperationException("Fixed effect bridge requires elevation");
    string sid=identity.User.Value;
    if(PinnedBuild.Mode!="CI"&&PinnedBuild.Mode!="ALPHA")throw new InvalidOperationException("Unknown fixed effect build mode");
    if(Environment.GetEnvironmentVariable("PVBOX_FIXED_HELPER_MODE")!=PinnedBuild.Mode)throw new InvalidOperationException("Fixed effect build mode mismatch");
    string bridge=Full(typeof(SdsBridge).Assembly.Location),code=Path.GetDirectoryName(bridge),session=Path.GetDirectoryName(code);
    // The parent clears the environment and supplies its already validated store.
    // This locator is not authority; exact namespace/ACL/lease/pin checks remain.
    // Child known-folder lookup remains unresolved and is not a fallback.
    string store=ValidateStoreLocator(Environment.GetEnvironmentVariable("RUNNER_TEMP"),PinnedBuild.Mode);
    string failure=OriginFailure(Path.GetFileName(bridge),Path.GetFileName(code),Path.GetDirectoryName(session),Path.GetFileName(session),store,PinnedBuild.Mode,Environment.GetEnvironmentVariable("PVBOX_FIXED_HELPER_MODE"));
    if(failure!=null)throw new InvalidOperationException(failure);
    using(var process=Process.GetCurrentProcess()){
     string image=process.MainModule.FileName;
     if(!Equal(image,Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe")))throw new InvalidOperationException("Fixed effect bridge requires fixed PowerShell");
     var state=new ContextState(purpose,bridge,code,session,store,sid,PinnedBuild.Mode,process.Id,process.StartTime.ToFileTimeUtc(),image);
     using(var admission=new Admission()){Admit(state,admission);}
     return new FixedEffectContext(state);
    }
   }
  }
  static string Admit(ContextState state,Admission admission){
   using(var identity=WindowsIdentity.GetCurrent()){
    if(identity.User.Value!=state.Sid||!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))throw new InvalidOperationException("Fixed effect token changed");
   }
   if(Environment.GetEnvironmentVariable("PVBOX_FIXED_HELPER_MODE")!=state.Mode||
      !Equal(ValidateStoreLocator(Environment.GetEnvironmentVariable("RUNNER_TEMP"),state.Mode),state.Store)||
      !Equal(Full(typeof(SdsBridge).Assembly.Location),state.Bridge))throw new InvalidOperationException("Fixed effect context origin changed");
   using(var process=Process.GetCurrentProcess())
    if(process.Id!=state.ProcessId||process.StartTime.ToFileTimeUtc()!=state.ProcessCreated||!Equal(process.MainModule.FileName,state.ProcessImage))throw new InvalidOperationException("Fixed effect process changed");
   admission.Parents(state.Code);
   foreach(string path in new[]{state.Store,state.Session,state.Code,state.App}){admission.Directory(path);CheckProtected(path,state.Sid);}
   admission.File(state.Bridge);
   return HoldPayload(admission,state.App,state.Sid);
  }
  static SdsResult Complete(FixedEffectWorker child,SdsDiagnosticFiles files,Stopwatch timer){
   long elapsed=timer.ElapsedMilliseconds;
   string output=child.StandardOutput.GetAwaiter().GetResult(),errors=child.StandardError.GetAwaiter().GetResult();
   files.WriteCompleted(output,errors);child.VerifyImageObservation();
   return new SdsResult(child.WithinDeadline,child.ExitCodeKnown,child.ExitCode,elapsed);
  }
  internal static SdsResult RunSds(ContextState state,SdsOperation operation,int seconds){
   lock(state.Sync){
    try {
     ValidateSds(state.Purpose,operation,seconds);state.Attempts.Begin(5);
     using(var admission=new Admission()){
      Admit(state,admission);
      string output=operation==SdsOperation.Register?state.Session:Path.Combine(state.Session,"cleanup");
      if(operation!=SdsOperation.Register){admission.Directory(output);CheckInheritedCleanup(output,state.Sid);}
      using(var files=new SdsDiagnosticFiles(output,operation==SdsOperation.Register?"sds-register":"sds-unregister")){
       var timer=Stopwatch.StartNew();
       using(var child=FixedEffectWorker.RunSds(Path.Combine(state.App,"VBoxSDS.exe"),operation!=SdsOperation.Register,seconds)){
        var result=Complete(child,files,timer);state.Attempts.Observe(result);return result;
       }
      }
     }
    }catch{state.Attempts.Fail();throw;}
   }
  }
  static string ValidatePublishedReceipt(Dictionary<string,object> receipt,string pinnedInf){
   object schema,name,absent,hash;
   if(!receipt.TryGetValue("published_inf_schema",out schema)||!((schema is int&&(int)schema==1)||(schema is long&&(long)schema==1))||
      !receipt.TryGetValue("published_inf",out name)||!(name is string)||!Regex.IsMatch((string)name,@"\Aoem[0-9]{1,6}\.inf\z")||
      !receipt.TryGetValue("published_inf_was_absent",out absent)||!(absent is bool)||!(bool)absent||
      !receipt.TryGetValue("published_inf_sha256",out hash)||!(hash is string)||(string)hash!=pinnedInf)
    throw new InvalidOperationException("Untrusted fixed published-INF selector");
   return (string)name;
  }
  static string PublishedInf(ContextState state,Admission admission,string pinnedInf){
   string stage=Path.Combine(state.Session,"stage");admission.Directory(stage);CheckInheritedCleanup(stage,state.Sid);
   var receipt=admission.File(Path.Combine(stage,"sup-standalone.json"));
   if(receipt.Length<1||receipt.Length>131072)throw new InvalidOperationException("Invalid fixed published-INF receipt size");
   Dictionary<string,object> row;
   using(var reader=new StreamReader(receipt,Encoding.UTF8,true,4096,true))
    row=new JavaScriptSerializer {MaxJsonLength=262144}.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());
   string name=ValidatePublishedReceipt(row,pinnedInf);
   string directory=Path.Combine(Path.GetDirectoryName(Environment.SystemDirectory),"INF");
   // Parent namespace leases persist, but release this exact INF file after
   // checking bytes so pnputil may delete it. Existing PS unique-inventory and
   // ownership checks still authorize removal; this is not new cleanup authority.
   admission.Parents(directory);
   string path=Full(Path.Combine(directory,name));
   using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)){
    if((File.GetAttributes(path)&(FileAttributes.ReparsePoint|FileAttributes.Directory))!=0)throw new InvalidOperationException("Unsafe installed INF");
    Admission.CheckFinal(file.SafeFileHandle,path);
    if(Hash(file)!=pinnedInf)throw new InvalidOperationException("Installed INF hash changed");
   }
   return name;
  }
  internal static SdsResult RunDriver(ContextState state,DriverOperation operation,int seconds){
   lock(state.Sync){
    try {
     ValidateDriver(state.Purpose,operation,seconds);state.Attempts.Begin((int)operation);
     using(var admission=new Admission()){
      string infHash=Admit(state,admission),label,folder,published=null;FixedDriverOperation fixedOperation;
      switch(operation){
       case DriverOperation.AddSupPackage: fixedOperation=FixedDriverOperation.AddSupPackage;folder="stage";label="pnputil";break;
       case DriverOperation.StartSup: fixedOperation=FixedDriverOperation.StartSup;folder="start";label="driver-start";break;
       case DriverOperation.StopSup: fixedOperation=FixedDriverOperation.StopSup;folder="cleanup";label="sup-stop";break;
       case DriverOperation.RemoveSupPackage: fixedOperation=FixedDriverOperation.RemoveSupPackage;folder="cleanup";label="sup-package-remove";published=PublishedInf(state,admission,infHash);break;
       case DriverOperation.DeleteSupService: fixedOperation=FixedDriverOperation.DeleteSupService;folder="cleanup";label="sup-service-delete";break;
       default:throw new InvalidOperationException("Unknown fixed driver operation");
      }
      string output=Path.Combine(state.Session,folder);admission.Directory(output);CheckInheritedCleanup(output,state.Sid);
      string systemImage=Path.Combine(Environment.SystemDirectory,operation==DriverOperation.AddSupPackage||operation==DriverOperation.RemoveSupPackage?"pnputil.exe":"sc.exe");
      admission.Parents(Path.GetDirectoryName(systemImage));admission.File(systemImage);
      using(var files=new SdsDiagnosticFiles(output,label)){
       var timer=Stopwatch.StartNew();
       using(var child=FixedEffectWorker.RunDriver(fixedOperation,operation==DriverOperation.AddSupPackage?state.App:null,published,seconds)){
        var result=Complete(child,files,timer);state.Attempts.Observe(result);return result;
       }
      }
     }
    }catch{state.Attempts.Fail();throw;}
   }
  }
 }
}
