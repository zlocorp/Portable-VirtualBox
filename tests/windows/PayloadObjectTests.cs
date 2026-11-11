// Windows-only native tests. Operate exclusively inside an owned GUID temp tree.
// Compile with SessionHelper.PayloadObjects.cs and PAYLOAD_OBJECT_TEST_STUBS to
// isolate the native wrapper, or without that symbol alongside the real helper.
using System;
using System.Collections;
using System.ComponentModel;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
 public static class PayloadObjectTests {
  static string root,sid;static int checks;
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetFileSecurityW(string path,uint information,byte[] descriptor);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateHardLinkW(string link,string existing,IntPtr attributes);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateSymbolicLinkW(string link,string target,uint flags);
  static object Call(string method,params object[] args) {
   try {return typeof(SessionHelper).GetMethod(method,BindingFlags.NonPublic|BindingFlags.Static).Invoke(null,args);}
   catch(TargetInvocationException error) {throw error.InnerException;}
  }
  static void Check(bool value,string label) {++checks;if(!value) throw new Exception("FAIL payload objects: "+label);}
  static void Refuses(Action action,string label) {
   bool refused=false;try {action();} catch(IOException) {refused=true;} catch(Win32Exception) {refused=true;} catch(InvalidOperationException) {refused=true;}
   Check(refused,label);
  }
  static byte[] Descriptor(string sddl) {var sd=new RawSecurityDescriptor(sddl);var bytes=new byte[sd.BinaryLength];sd.GetBinaryForm(bytes,0);return bytes;}
  static void SetSecurity(string path,bool directory) {
   byte[] bytes=directory?((DirectorySecurity)Call("Security",sid)).GetSecurityDescriptorBinaryForm():Descriptor("O:BA");
   if(!SetFileSecurityW(path,directory?0x80000005U:1U,bytes)) throw new Win32Exception(Marshal.GetLastWin32Error());
  }
  static string NewFile(string name) {string path=Path.Combine(root,name);File.WriteAllBytes(path,new byte[]{1,2,3});SetSecurity(path,false);return path;}
  static string NewDirectory(string name) {string path=Path.Combine(root,name);Directory.CreateDirectory(path);SetSecurity(path,true);return path;}
  static string Digest {get {using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(new byte[]{1,2,3})).Replace("-","").ToLowerInvariant();}}
  static string Capture(string path,bool directory) {return (string)Call("CapturePayloadObject",path,sid,directory,directory?0L:3L,directory?null:Digest);}
  static void Delete(string path,bool directory,string identity) {Call("DeletePayloadObject",path,sid,directory,directory?0L:3L,directory?null:Digest,identity);}
  static void ReleaseLocks() {
   var field=typeof(SessionHelper).GetField("Locks",BindingFlags.NonPublic|BindingFlags.Static);
   var locks=(IList)field.GetValue(null);foreach(IDisposable item in locks) item.Dispose();locks.Clear();
   object names=typeof(SessionHelper).GetField("LockedDirs",BindingFlags.NonPublic|BindingFlags.Static).GetValue(null);names.GetType().GetMethod("Clear").Invoke(names,null);
  }
  public static int Main() {
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT) {Console.WriteLine("SKIP payload object native tests: Windows required");return 0;}
   if(!new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator)) throw new InvalidOperationException("Payload object fixture requires an elevated Windows test process to assign Administrators ownership");
   // A distinct, valid low-user SID avoids duplicate administrator/system ACEs.
   sid="S-1-5-21-111111111-222222222-333333333-1234";
   root=Path.Combine(Path.GetTempPath(),"pvbox-object-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
   try {
    SetSecurity(root,true);
    Check(!(bool)Call("PayloadExists",Path.Combine(root,"missing")),"explicit missing is absent");
    string file=NewFile("file"),identity=Capture(file,false);
    Check(identity==Capture(file,false),"stable file handle identity");
    File.Move(file,file+".old");NewFile("file");
    Check(identity!=Capture(file,false),"same bytes recreated file has different identity");
    Refuses(()=>Delete(file,false,identity),"recreated file cannot inherit delete authority");
    File.WriteAllBytes(file,new byte[]{3,2,1});
    Refuses(()=>Capture(file,false),"changed content rejected");
    File.WriteAllBytes(file,new byte[]{1,2,3});identity=Capture(file,false);
    using(var locked=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)) Refuses(()=>Delete(file,false,identity),"locked object cannot report success");
    Check((bool)Call("PayloadExists",file),"locked object remains present");
    using(var evidence=(IDisposable)Call("OpenPayloadEvidenceGuard",file,sid)) {
     using(var writer=new FileStream(file,FileMode.Open,FileAccess.ReadWrite,FileShare.Read)) Check(writer.Length==3,"evidence guard permits journal writer");
     Refuses(()=>File.Move(file,file+".moved"),"evidence guard pins rename");
    }
    string badAcl=NewFile("bad-acl");
    if(!SetFileSecurityW(badAcl,0x80000004U,Descriptor("D:P(A;;FA;;;BA)(A;;FR;;;WD)"))) throw new Win32Exception(Marshal.GetLastWin32Error());
    Refuses(()=>Capture(badAcl,false),"unexpected file ACL rejected");
    Refuses(()=>Call("OpenPayloadEvidenceGuard",badAcl,sid),"evidence guard rejects unexpected ACL");
    Refuses(()=>Capture(file,true),"file cannot satisfy directory expectation");
    string link=Path.Combine(root,"hardlink");
    if(CreateHardLinkW(link,file,IntPtr.Zero)) {Refuses(()=>Capture(file,false),"hardlinked file rejected");File.Delete(link);} else Console.WriteLine("SKIP hardlink fixture: Win32 "+Marshal.GetLastWin32Error());
    string symlink=Path.Combine(root,"symlink");
    if(CreateSymbolicLinkW(symlink,file,0)) {Refuses(()=>Capture(symlink,false),"reparse object rejected");File.Delete(symlink);} else Console.WriteLine("SKIP symlink fixture: Win32 "+Marshal.GetLastWin32Error());
    Delete(file,false,identity);Check(!(bool)Call("PayloadExists",file),"file explicit absence after deletion");
    string pending=NewFile("pending");string pendingId=Capture(pending,false);
    using(var retained=new FileStream(pending,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete)) Refuses(()=>Delete(pending,false,pendingId),"delete-pending cannot report absence");
    string directory=NewDirectory("directory"),directoryId=Capture(directory,true);
    Directory.Move(directory,directory+".old");NewDirectory("directory");
    Check(directoryId!=Capture(directory,true),"recreated directory has different identity");
    Refuses(()=>Delete(directory,true,directoryId),"recreated directory cannot inherit delete authority");
    Delete(directory,true,Capture(directory,true));Check(!(bool)Call("PayloadExists",directory),"directory explicit absence after deletion");
    Console.WriteLine("PASS payload object native tests: "+checks);return 0;
   } finally {ReleaseLocks();Directory.Delete(root,true);}
  }
 }
#if PAYLOAD_OBJECT_TEST_STUBS
 // Only dependencies unrelated to object queries are supplied by the fixture.
 // Native identity, ACL, content and deletion code is always production code.
 public static partial class SessionHelper {
  static readonly SecurityIdentifier Admins=new SecurityIdentifier("S-1-5-32-544"),SystemSid=new SecurityIdentifier("S-1-5-18");
  static readonly System.Collections.Generic.List<IDisposable> Locks=new System.Collections.Generic.List<IDisposable>();
  static readonly System.Collections.Generic.HashSet<string> LockedDirs=new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr attributes,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder buffer,uint size,uint flags);
  static string Full(string path) {return Path.GetFullPath(path).TrimEnd('\\');}
  static void LockParents(string path) {
   if(String.IsNullOrEmpty(path)) return;LockParents(Path.GetDirectoryName(path));if(!LockedDirs.Add(path)) return;
   var handle=CreateFileW(path,0x80,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
   if(handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());Locks.Add(handle);
  }
  static string Hash(Stream stream) {using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}
  static DirectorySecurity Security(string sid) {var security=new DirectorySecurity();security.SetSecurityDescriptorSddlForm("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;"+sid+")(A;OICI;RC;;;OW)");return security;}
 }
#endif
}
