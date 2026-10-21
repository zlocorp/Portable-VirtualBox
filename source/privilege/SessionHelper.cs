// Fixed, separately elevated effect helper for the non-distributed session experiment.
// It accepts only Prepare/Finish plus numeric controller PID and cycle. No paths,
// command strings, script names or caller-provided ownership receipts are accepted.
// Embedded source, pinned Oracle inventory, protected copies and live controller
// binding are security measures; GitHub environment checks are accident guards only.
using System;
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
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
    public static partial class SessionHelper {
        static readonly string[] Scripts={"privileged_session_worker.ps1","vbox_sup_standalone.ps1","vbox_sup_start_owned.ps1","vbox_sup_cleanup.ps1"};
        static readonly SecurityIdentifier Admins=new SecurityIdentifier("S-1-5-32-544"),SystemSid=new SecurityIdentifier("S-1-5-18");
        static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=262144 };
        static readonly List<IDisposable> Locks=new List<IDisposable>();
        static readonly HashSet<string> LockedDirs=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        [StructLayout(LayoutKind.Sequential)] struct SA { public int Size; public IntPtr Descriptor; public int Inherit; }
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectoryW(string p,ref SA sa);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string p,uint access,uint share,IntPtr sa,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint size,uint flags);
        static string Hash(byte[] b) { using(var s=SHA256.Create()) return BitConverter.ToString(s.ComputeHash(b)).Replace("-","").ToLowerInvariant(); }
        static string Hash(Stream stream) { using(var s=SHA256.Create()) return BitConverter.ToString(s.ComputeHash(stream)).Replace("-","").ToLowerInvariant(); }
        static string ResourceText(string name) { return Encoding.UTF8.GetString(Resource(name)).TrimStart('\ufeff'); }
        static byte[] Resource(string name) {
            using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
                if(s==null) throw new InvalidOperationException("Missing embedded resource");
                using(var m=new MemoryStream()) { s.CopyTo(m);return m.ToArray(); }
            }
        }
        static string Full(string path) {
            string p=Path.GetFullPath(path).TrimEnd('\\');
            if(p.Length<4 || p.Length>240 || p[1]!=':' || p[2]!='\\' || p.IndexOfAny(new[]{'"','\r','\n','\0'})>=0 || p.IndexOf(':',2)>=0) throw new InvalidOperationException("Invalid local path");
            return p;
        }
        static bool Under(string path,string parent) { return path.StartsWith(parent.TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase); }
        static void LockDirectory(string path) {
            path=Path.GetFullPath(path);
            if(!LockedDirs.Add(path)) return;
            FileAttributes a=File.GetAttributes(path);
            if((a&FileAttributes.ReparsePoint)!=0 || (a&FileAttributes.Directory)==0) throw new InvalidOperationException("Unsafe directory");
            var h=CreateFileW(path,0x80,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero); // no FILE_SHARE_DELETE
            if(h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            Locks.Add(h);
            var final=new StringBuilder(32768);
            uint n=GetFinalPathNameByHandle(h,final,(uint)final.Capacity,0);
            if(n==0 || n>=final.Capacity || !String.Equals(final.ToString().Replace("\\\\?\\",""),path,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Directory identity changed");
            if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new InvalidOperationException("Directory changed to reparse");
        }
        static void LockParents(string path) {
            var list=new List<string>(); var d=new DirectoryInfo(path);
            while(d!=null) { list.Add(d.FullName);d=d.Parent; }
            list.Reverse(); foreach(var p in list) LockDirectory(p);
        }
        static DirectorySecurity Security(string sid) {
            var d=new DirectorySecurity();
            // OWNER RIGHTS removes the implicit low user's WRITE_DAC on newly
            // inherited child objects before their owner is set to Administrators.
            d.SetSecurityDescriptorSddlForm("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;"+sid+")(A;OICI;RC;;;OW)");
            return d;
        }
        static void CheckProtectedDirectory(string path,string sid) {
            LockDirectory(path);
            var actual=Directory.GetAccessControl(path,AccessControlSections.Owner|AccessControlSections.Access);
            var wanted=Security(sid);
            if(!actual.GetOwner(typeof(SecurityIdentifier)).Equals(Admins) || !actual.AreAccessRulesProtected ||
               actual.GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access)!=wanted.GetSecurityDescriptorSddlForm(AccessControlSections.Owner|AccessControlSections.Access))
                throw new InvalidOperationException("Untrusted protected-directory ACL/owner");
        }
        static void CreateProtectedDirectory(string path,string sid,bool existing) {
            if(Directory.Exists(path)) { if(!existing) throw new InvalidOperationException("Stale session directory"); CheckProtectedDirectory(path,sid); return; }
            var bytes=Security(sid).GetSecurityDescriptorBinaryForm();IntPtr descriptor=Marshal.AllocHGlobal(bytes.Length);
            try {
                Marshal.Copy(bytes,0,descriptor,bytes.Length);
                var sa=new SA { Size=Marshal.SizeOf(typeof(SA)),Descriptor=descriptor,Inherit=0 };
                if(!CreateDirectoryW(path,ref sa)) throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally { Marshal.FreeHGlobal(descriptor); }
            CheckProtectedDirectory(path,sid);
        }
        static void CreateTree(string path,string boundary,string sid) {
            if(String.Equals(path,boundary,StringComparison.OrdinalIgnoreCase)) return;
            if(!Under(path,boundary)) throw new InvalidOperationException("Escaped protected tree");
            CreateTree(Path.GetDirectoryName(path),boundary,sid);
            CreateProtectedDirectory(path,sid,true);
        }
        static void WriteNew(string path,byte[] bytes) {
            using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {f.Write(bytes,0,bytes.Length);f.Flush(true);}
            var security=File.GetAccessControl(path);security.SetOwner(Admins);File.SetAccessControl(path,security);
        }
        static FileStream OpenLocked(string path) {
            LockParents(Path.GetDirectoryName(path));
            if((File.GetAttributes(path)&(FileAttributes.Directory|FileAttributes.ReparsePoint))!=0) throw new InvalidOperationException("Unsafe file type");
            var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
            var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(f.SafeFileHandle,final,(uint)final.Capacity,0);
            if(n==0 || n>=final.Capacity || !String.Equals(final.ToString().Replace("\\\\?\\",""),path,StringComparison.OrdinalIgnoreCase)) {f.Dispose();throw new InvalidOperationException("Changed file identity");}
            return f;
        }
        static void InstallScripts(string session,bool prepare) {
            string code=Path.Combine(session,"code");
            foreach(string name in Scripts) {
                string p=Path.Combine(code,name);byte[] bytes=Resource(name);
                if(prepare) WriteNew(p,bytes);
                var f=OpenLocked(p);Locks.Add(f);
                if(Hash(f)!=Hash(bytes)) throw new InvalidOperationException("Modified embedded worker");
            }
        }
        static Dictionary<string,object> Manifest(string path) {
            // Treat a caller manifest as untrusted until the FULL canonical row
            // inventory matches the independently acquired, compiled SHA256 pin.
            Dictionary<string,object> manifest;
            using(var f=OpenLocked(path)) {
                if(f.Length<1 || f.Length>131072) throw new InvalidOperationException("Invalid inventory size");
                using(var r=new StreamReader(f,Encoding.UTF8)) manifest=Json.Deserialize<Dictionary<string,object>>(r.ReadToEnd());
            }
            var rows=new List<string>();long bytes=0;
            foreach(Dictionary<string,object> row in (System.Collections.IEnumerable)manifest["files"]) {
                string file=(string)row["path"],hash=(string)row["sha256"];
                long size=Convert.ToInt64(row["size"],CultureInfo.InvariantCulture);
                if(file.IndexOfAny(new[]{'\t','\r','\n'})>=0 || size<0 || hash.Length!=64) throw new InvalidOperationException("Invalid inventory row");
                rows.Add(file+"\t"+size.ToString(CultureInfo.InvariantCulture)+"\t"+hash.ToLowerInvariant()+"\n");bytes+=size;
            }
            rows.Sort(StringComparer.Ordinal);
            string CanonicalInventorySha256=Hash(Encoding.UTF8.GetBytes(String.Concat(rows)));
            if(rows.Count!=185 || bytes!=247834716 || CanonicalInventorySha256!=PinnedBuild.InventorySha256) throw new InvalidOperationException("Forged or changed Oracle inventory");
            return manifest;
        }
        static void ValidateAndStage(string input,string output,string sid,bool prepare) {
            string report=Path.Combine(output,".prepared.json");
            var manifest=Manifest(prepare?Path.Combine(input,".prepared.json"):report);
            if(Convert.ToInt32(manifest["file_count"])!=185 || Convert.ToInt64(manifest["total_bytes"])!=247834716) throw new InvalidOperationException("Unexpected compiled inventory");
            var files=(System.Collections.IEnumerable)manifest["files"];int count=0;
            foreach(Dictionary<string,object> row in files) {
                string relative=((string)row["path"]).Replace('/','\\');
                if(Path.IsPathRooted(relative) || relative.Contains("..") || relative.IndexOfAny(new[]{':','"','\r','\n'})>=0) throw new InvalidOperationException("Bad compiled inventory path");
                string target=Full(Path.Combine(output,relative)),source=Full(Path.Combine(input,relative));
                if(!Under(target,output) || !Under(source,input)) throw new InvalidOperationException("Inventory traversal");
                if(prepare) CreateTree(Path.GetDirectoryName(target),output,sid);
                using(var f=OpenLocked(prepare?source:target)) {
                    if(f.Length!=Convert.ToInt64(row["size"]) || Hash(f)!=(string)row["sha256"]) throw new InvalidOperationException("Oracle file hash mismatch: "+relative);
                    if(prepare) {
                        f.Position=0;
                        using(var t=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {f.CopyTo(t);t.Flush(true);}
                        var a=File.GetAccessControl(target);a.SetOwner(Admins);File.SetAccessControl(target,a);
                    }
                }
                // Keep elevated executable/DLL inputs immutable for the whole action.
                var locked=OpenLocked(target);Locks.Add(locked);
                if(Hash(locked)!=(string)row["sha256"]) throw new InvalidOperationException("Protected copy differs");
                ++count;
            }
            if(count!=185) throw new InvalidOperationException("Incomplete compiled inventory");
            if(prepare) WriteNew(report,Encoding.UTF8.GetBytes(Json.Serialize(manifest)));
            var reportLock=OpenLocked(report);Locks.Add(reportLock);
        }
        static void RemoveVerifiedPayload(string session) {
            // Only after verified system teardown. The protected parent denies
            // low-user creation, rename, write and ownership/ACL changes.
            string app=Path.Combine(session,"app64");
            var manifest=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(app,".prepared.json"),Encoding.UTF8));
            var directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach(Dictionary<string,object> row in (System.Collections.IEnumerable)manifest["files"]) {
                string file=Full(Path.Combine(app,((string)row["path"]).Replace('/','\\')));
                if(!Under(file,app) || (File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0) throw new InvalidOperationException("Unexpected protected cleanup path");
                File.Delete(file);
                string dir=Path.GetDirectoryName(file);
                while(!String.Equals(dir,app,StringComparison.OrdinalIgnoreCase)) {directories.Add(dir);dir=Path.GetDirectoryName(dir);}
            }
            File.Delete(Path.Combine(app,".prepared.json"));
            var ordered=new List<string>(directories);ordered.Sort((a,b)=>b.Length.CompareTo(a.Length));
            foreach(string dir in ordered) Directory.Delete(dir,false);
            Directory.Delete(app,false);
            foreach(string name in Scripts) File.Delete(Path.Combine(session,"code",name));
            Directory.Delete(Path.Combine(session,"code"),false);
            WriteNew(Path.Combine(session,"payload-removed.json"),Encoding.UTF8.GetBytes("{\"protected_payload_removed\":true}"));
        }
    }
}
