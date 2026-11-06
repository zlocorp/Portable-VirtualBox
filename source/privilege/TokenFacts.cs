// Windows token/process observations shared by the fixed helper and CI probes.
// No token elevation, process creation or system mutation in this file.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace PortableVBox {
    public sealed class TokenFacts {
        public int Pid, Integrity, Session;
        public bool Administrator, Elevated;
        public string Sid, Image;
        public long Created;
        [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
        [DllImport("kernel32.dll",SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder b,ref int size);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long c,out long e,out long k,out long u);
        [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h,uint ms);
        [DllImport("advapi32.dll",SetLastError=true)] public static extern bool OpenProcessToken(IntPtr h,uint rights,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t,int c,IntPtr b,int n,out int needed);
        static byte[] Info(IntPtr token,int type) {
            int size; GetTokenInformation(token,type,IntPtr.Zero,0,out size);
            if(size<1 || size>65536) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr p=Marshal.AllocHGlobal(size);
            try {
                if(!GetTokenInformation(token,type,p,size,out size)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if(type==25) { // TOKEN_MANDATORY_LABEL contains a pointer into this buffer.
                    string sid=new SecurityIdentifier(Marshal.ReadIntPtr(p)).Value;
                    return BitConverter.GetBytes(int.Parse(sid.Substring(sid.LastIndexOf('-')+1)));
                }
                byte[] result=new byte[size]; Marshal.Copy(p,result,0,size); return result;
            } finally { Marshal.FreeHGlobal(p); }
        }
        public static TokenFacts Read(int pid) {
            IntPtr p=OpenProcess(0x101000,false,pid); // QUERY_LIMITED_INFORMATION | SYNCHRONIZE
            if(p==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try { return ReadHandle(p,pid); } finally { CloseHandle(p); }
        }
        public static TokenFacts ReadHandle(IntPtr p,int pid) {
            IntPtr t;
            // QUERY | DUPLICATE: WindowsPrincipal.IsInRole duplicates a primary
            // token to query membership. No ADJUST_* or IMPERSONATE is requested.
            if(!OpenProcessToken(p,0x000A,out t)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                var f=new TokenFacts(); f.Pid=pid;
                using(var id=new WindowsIdentity(t)) {
                    f.Sid=id.User.Value;
                    f.Administrator=new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
                }
                f.Integrity=BitConverter.ToInt32(Info(t,25),0);
                f.Elevated=BitConverter.ToInt32(Info(t,20),0)!=0;
                f.Session=BitConverter.ToInt32(Info(t,12),0);
                var image=new StringBuilder(32768);int n=image.Capacity;
                if(!QueryFullProcessImageName(p,0,image,ref n)) throw new Win32Exception(Marshal.GetLastWin32Error());
                f.Image=image.ToString();long e,k,u;
                if(!GetProcessTimes(p,out f.Created,out e,out k,out u)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if(WaitForSingleObject(p,0)!=258) throw new InvalidOperationException("Process is not live");
                return f;
            } finally { CloseHandle(t); }
        }
    }
}
