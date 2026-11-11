// Owner-bound private payload cleanup. All authority checks use one retained
// native handle; no path-based deletion or permissive existence inference.
using System;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
 public static partial class SessionHelper {
  [StructLayout(LayoutKind.Sequential)] struct PayloadFileInfo {
   public uint Attributes,CreationLow,CreationHigh,AccessLow,AccessHigh,WriteLow,WriteHigh,Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFileAttributesW(string path);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle,out PayloadFileInfo info);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,IntPtr buffer,uint size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFileInformationByHandle(SafeFileHandle handle,int kind,IntPtr buffer,uint size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetFileType(SafeFileHandle handle);
  [DllImport("advapi32.dll",SetLastError=true)] static extern uint GetSecurityInfo(SafeFileHandle handle,int type,uint requested,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
  [DllImport("advapi32.dll")] static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);

  static bool PayloadExists(string path) {
   uint attributes=GetFileAttributesW(Full(path));
   if(attributes!=UInt32.MaxValue) return true;
   int error=Marshal.GetLastWin32Error();
   if(error==2 || error==3) return false;
   // Access denied, delete pending, sharing violations and unsupported queries
   // are UNKNOWN, never evidence that an object was removed.
   throw new Win32Exception(error,"Cannot establish payload presence");
  }
  static SafeFileHandle OpenPayloadObject(string path,bool directory,bool deleting) {
   path=Full(path);LockParents(Path.GetDirectoryName(path));
   uint access=0x20080U | (directory?0U:0x80000000U) | (deleting?0x10000U:0U);
   // OPEN_REPARSE_POINT + BACKUP_SEMANTICS; FILE_SHARE_READ only prevents
   // competing write/delete handles for the entire validation and disposition.
   SafeFileHandle handle=CreateFileW(path,access,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
   if(handle.IsInvalid) {int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
   return handle;
  }
  static void VerifyPayloadAcl(SafeFileHandle handle,string sid,bool directory) {
   IntPtr owner,group,dacl,sacl,descriptor;
   uint error=GetSecurityInfo(handle,1,5,out owner,out group,out dacl,out sacl,out descriptor);
   if(error!=0) throw new Win32Exception((int)error,"Cannot read payload ACL");
   try {
    if(descriptor==IntPtr.Zero || owner==IntPtr.Zero || dacl==IntPtr.Zero) throw new InvalidDataException("Missing payload owner/DACL");
    uint size=GetSecurityDescriptorLength(descriptor);
    if(size<20 || size>65536) throw new InvalidDataException("Unbounded payload descriptor");
    var bytes=new byte[(int)size];Marshal.Copy(descriptor,bytes,0,bytes.Length);
    var actual=new RawSecurityDescriptor(bytes,0);
    if(actual.Owner==null || !actual.Owner.Equals(Admins) || actual.DiscretionaryAcl==null || (actual.ControlFlags&ControlFlags.DiscretionaryAclPresent)==0) throw new InvalidDataException("Untrusted payload owner/DACL");
    if(directory) {
     var expected=new RawSecurityDescriptor(Security(sid).GetSecurityDescriptorBinaryForm(),0);
     if((actual.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0 || actual.GetSddlForm(AccessControlSections.Owner|AccessControlSections.Access)!=expected.GetSddlForm(AccessControlSections.Owner|AccessControlSections.Access)) throw new InvalidDataException("Untrusted payload directory ACL");
    } else {
     // Native Windows removes inherited OWNER_RIGHTS when SetOwner normalizes
     // the file to Administrators. Require that exact post-normalization ACL,
     // not an optional 3/4-ACE fallback. The mandatory BA owner check above is
     // essential: the medium caller must not gain implicit owner WRITE_DAC.
     // Parent directories retain OWNER_RIGHTS throughout the creation window.
     if((actual.ControlFlags&ControlFlags.DiscretionaryAclProtected)!=0 || actual.DiscretionaryAcl.Count!=3) throw new InvalidDataException("Untrusted payload file ACL");
     var identities=new[]{SystemSid,Admins,new SecurityIdentifier(sid)};
     var masks=new[]{0x1f01ff,0x1f01ff,0x1200a9};
     for(int i=0;i<identities.Length;i++) {
      var ace=actual.DiscretionaryAcl[i] as CommonAce;
      if(ace==null || ace.IsCallback || ace.AceQualifier!=AceQualifier.AccessAllowed || ace.AceFlags!=AceFlags.Inherited || !ace.SecurityIdentifier.Equals(identities[i]) || ace.AccessMask!=masks[i]) throw new InvalidDataException("Unexpected inherited payload ACE");
     }
    }
   } finally {if(descriptor!=IntPtr.Zero) LocalFree(descriptor);}
  }
  static string VerifyPayloadObject(SafeFileHandle handle,string path,string sid,bool directory,long length,string sha256,bool verifyContent=true) {
   if(GetFileType(handle)!=1) throw new InvalidDataException("Payload is not a disk object");
   PayloadFileInfo info;
   if(!GetFileInformationByHandle(handle,out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
   if((info.Attributes&0x400)!=0 || ((info.Attributes&0x10)!=0)!=directory || (!directory && info.Links!=1)) throw new InvalidDataException("Unsafe payload object type or link count");
   var final=new StringBuilder(32768);uint count=GetFinalPathNameByHandle(handle,final,(uint)final.Capacity,0);
   if(count==0) throw new Win32Exception(Marshal.GetLastWin32Error());
   string resolved=final.ToString();if(resolved.StartsWith("\\\\?\\",StringComparison.Ordinal)) resolved=resolved.Substring(4);
   if(count>=final.Capacity || !String.Equals(resolved,Full(path),StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Payload path identity changed");
   VerifyPayloadAcl(handle,sid,directory);
   string identity;
   IntPtr buffer=Marshal.AllocHGlobal(24);
   try {
    // FILE_ID_INFO: 64-bit volume serial followed by opaque 128-bit file ID.
    // Unsupported filesystems/OS versions fail closed; no weaker fallback.
    if(!GetFileInformationByHandleEx(handle,18,buffer,24)) throw new Win32Exception(Marshal.GetLastWin32Error());
    var id=new byte[24];Marshal.Copy(buffer,id,0,id.Length);
    identity=BitConverter.ToString(id).Replace("-","").ToLowerInvariant()+":"+info.CreationHigh.ToString("x8",CultureInfo.InvariantCulture)+info.CreationLow.ToString("x8",CultureInfo.InvariantCulture)+(directory?":D":":F");
   } finally {Marshal.FreeHGlobal(buffer);}
   if(!verifyContent) return identity;
   if(!directory) {
    ulong size=((ulong)info.SizeHigh<<32)|info.SizeLow;
    if(length<0 || length>536870912L || size!=(ulong)length || sha256==null || sha256.Length!=64) throw new InvalidDataException("Payload size mismatch");
    // The non-owning view lets FileStream hash the already verified object
    // without reopening its path or closing the disposition handle early.
    using(var view=new SafeFileHandle(handle.DangerousGetHandle(),false))
    using(var stream=new FileStream(view,FileAccess.Read,65536,false)) {
     if(stream.Length!=length || !String.Equals(Hash(stream),sha256,StringComparison.Ordinal)) throw new InvalidDataException("Payload hash mismatch");
    }
   } else if(length!=0 || sha256!=null) throw new InvalidDataException("Invalid directory expectation");
   return identity;
  }
  static IDisposable OpenPayloadEvidenceGuard(string path,string sid) {
   path=Full(path);LockParents(Path.GetDirectoryName(path));
   // Metadata-only access is compatible with the journal's read/write stream.
   // Denying FILE_SHARE_DELETE pins this exact evidence object for its lifetime.
   var handle=CreateFileW(path,0x20080,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
   if(handle.IsInvalid) {int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
   try {VerifyPayloadObject(handle,path,sid,false,0,null,false);return handle;}
   catch {handle.Dispose();throw;}
  }
  static string CapturePayloadObject(string path,string sid,bool directory,long length,string sha256) {
   using(var handle=OpenPayloadObject(path,directory,false)) return VerifyPayloadObject(handle,path,sid,directory,length,sha256);
  }
  static void DeletePayloadObject(string path,string sid,bool directory,long length,string sha256,string expectedIdentity) {
   if(String.IsNullOrEmpty(expectedIdentity)) throw new InvalidDataException("Missing payload object identity");
   using(var handle=OpenPayloadObject(path,directory,true)) {
    string actual=VerifyPayloadObject(handle,path,sid,directory,length,sha256);
    if(!String.Equals(actual,expectedIdentity,StringComparison.Ordinal)) throw new InvalidDataException("Payload object was replaced");
    IntPtr disposition=Marshal.AllocHGlobal(1);
    try {
     Marshal.WriteByte(disposition,1); // FILE_DISPOSITION_INFO.DeleteFile (BOOLEAN)
     if(!SetFileInformationByHandle(handle,4,disposition,1)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Payload disposition failed");
    } finally {Marshal.FreeHGlobal(disposition);}
   }
   if(PayloadExists(path)) throw new IOException("Payload deletion did not establish absence");
  }
 }
}
