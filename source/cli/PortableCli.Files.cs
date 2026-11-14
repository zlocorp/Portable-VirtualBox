// Read-only file/ACL validation adapted from this project's SessionHelper.
// It does NOT install, remove, create or elevate anything.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
 internal sealed class CliFiles : IDisposable {
  readonly List<IDisposable> leases=new List<IDisposable>();
  readonly HashSet<string> directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  readonly JavaScriptSerializer json=new JavaScriptSerializer {MaxJsonLength=262144,RecursionLimit=32};
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string p,uint access,uint share,IntPtr sa,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint size,uint flags);
  internal static string Full(string path) {
   if(String.IsNullOrEmpty(path) || !Path.IsPathRooted(path)) throw new InvalidOperationException("Absolute local path required");
   string p=Path.GetFullPath(path).TrimEnd('\\');
   if(p.Length<4 || p.Length>240 || p[1]!=':' || p[2]!='\\' || p.IndexOfAny(new[]{'"','\r','\n','\0'})>=0 || p.IndexOf(':',2)>=0)
    throw new InvalidOperationException("Unsafe local path");
   return p;
  }
  internal static bool Same(string a,string b) {return String.Equals(a,b,StringComparison.OrdinalIgnoreCase);}
  internal static string Hash(Stream f) {using(var s=SHA256.Create()) return BitConverter.ToString(s.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
  static string Hash(byte[] b) {using(var f=new MemoryStream(b)) return Hash(f);}
  static void ExactHandle(SafeFileHandle h,string path) {
   var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,final,(uint)final.Capacity,0);
   if(n==0 || n>=final.Capacity || !Same(final.ToString().Replace("\\\\?\\",""),path)) throw new InvalidOperationException("Changed filesystem identity");
  }
  internal void LockDirectory(string path) {
   path=Path.GetFullPath(path);
   if(directories.Contains(path)) return;
   FileAttributes a=File.GetAttributes(path);
   if((a&FileAttributes.ReparsePoint)!=0 || (a&FileAttributes.Directory)==0) throw new InvalidOperationException("Unsafe directory");
   // FILE_LIST_DIRECTORY is necessary for actual share-delete exclusion;
   // metadata-only READ_ATTRIBUTES opens do not pin the namespace.
   var h=CreateFileW(path,0x81,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero); // list/read; no share-delete
   if(h.IsInvalid) {h.Dispose();throw new Win32Exception(Marshal.GetLastWin32Error());}
   leases.Add(h);ExactHandle(h,path);
   if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new InvalidOperationException("Reparse directory refused");
   directories.Add(path);
  }
  internal void LockParents(string path) {
   var parents=new List<string>();var d=new DirectoryInfo(path);
   while(d!=null) {parents.Add(d.FullName);d=d.Parent;}
   parents.Reverse();foreach(string p in parents) LockDirectory(p);
  }
  internal FileStream Open(string path) {
   path=Full(path);LockParents(Path.GetDirectoryName(path));
   if((File.GetAttributes(path)&(FileAttributes.Directory|FileAttributes.ReparsePoint))!=0) throw new InvalidOperationException("Unsafe file");
   var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
   leases.Add(f);ExactHandle(f.SafeFileHandle,path);return f;
  }
  internal void Protected(string path,string sid) {
   LockParents(path);
   var wanted=new DirectorySecurity();
   wanted.SetSecurityDescriptorSddlForm("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;"+sid+")(A;OICI;RC;;;OW)");
   var actual=Directory.GetAccessControl(path,AccessControlSections.Owner|AccessControlSections.Access);
   if(!actual.GetOwner(typeof(SecurityIdentifier)).Equals(new SecurityIdentifier("S-1-5-32-544")) || !actual.AreAccessRulesProtected ||
      actual.GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access)!=wanted.GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access))
    throw new InvalidOperationException("Untrusted protected session directory");
  }
  internal Dictionary<string,object> ReadJson(string path,int limit) {
   var f=Open(path);
   if(f.Length<1 || f.Length>limit) throw new InvalidOperationException("Unexpected receipt size");
   var bytes=new byte[(int)f.Length];int offset=0;
   while(offset<bytes.Length) {int n=f.Read(bytes,offset,bytes.Length-offset);if(n==0) throw new InvalidOperationException("Incomplete receipt");offset+=n;}
   // Malformed encoding is never silently repaired in an authority document.
   return json.Deserialize<Dictionary<string,object>>(new UTF8Encoding(false,true).GetString(bytes).TrimStart('\ufeff'));
  }
  internal void VerifyRuntime(string runtime) {
   var manifest=ReadJson(Path.Combine(runtime,".prepared.json"),131072);
   var rows=new List<string>();long total=0;var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   var entries=manifest["files"] as IEnumerable;
   if(entries==null) throw new InvalidOperationException("Missing Oracle inventory");
   foreach(Dictionary<string,object> row in entries) {
    string file=(string)row["path"],hash=(string)row["sha256"];
    long size=Convert.ToInt64(row["size"],CultureInfo.InvariantCulture);
    if(size<0 || file.IndexOfAny(new[]{'\t','\r','\n',':','"','\0'})>=0 || Path.IsPathRooted(file) || file.Contains("..") ||
       !System.Text.RegularExpressions.Regex.IsMatch(hash,"^[a-f0-9]{64}$") || !names.Add(file)) throw new InvalidOperationException("Invalid Oracle inventory row");
    rows.Add(file+"\t"+size.ToString(CultureInfo.InvariantCulture)+"\t"+hash+"\n");total+=size;
   }
   rows.Sort(StringComparer.Ordinal);
   if(rows.Count!=185 || total!=247834716 || Hash(Encoding.UTF8.GetBytes(String.Concat(rows)))!=PinnedBuild.InventorySha256 ||
      Convert.ToInt32(manifest["file_count"])!=185 || Convert.ToInt64(manifest["total_bytes"])!=247834716)
    throw new InvalidOperationException("Pinned Oracle inventory differs");
   foreach(Dictionary<string,object> row in entries) {
    string file=Full(Path.Combine(runtime,((string)row["path"]).Replace('/','\\')));
    if(!file.StartsWith(runtime+"\\",StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Escaped Oracle inventory");
    var f=Open(file);
    if(f.Length!=Convert.ToInt64(row["size"]) || Hash(f)!=(string)row["sha256"]) throw new InvalidOperationException("Protected Oracle file differs");
   }
  }
  public void Dispose() {for(int i=leases.Count-1;i>=0;i--) leases[i].Dispose();leases.Clear();directories.Clear();}
 }
}
