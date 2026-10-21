// CI-only token fixture. Creates an explicitly restricted medium process from
// the elevated disposable runner. No UAC policy change, service or scheduled task.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
using PortableVBox;
public static class MediumProcess {
    [StructLayout(LayoutKind.Sequential)] struct SidAttr {public IntPtr Sid;public uint Attr;}
    [StructLayout(LayoutKind.Sequential)] struct SA {public int Size;public IntPtr Descriptor;public int Inherit;}
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {
        public int Size;public string Reserved,Desktop,Title;public int X,Y,CX,CY,XChars,YChars,Fill,Flags;
        public short Show,Reserved2;public IntPtr Reserved3,Input,Output,Error;
    }
    [StructLayout(LayoutKind.Sequential)] struct Pi {public IntPtr Process,Thread;public int Pid,Tid;}
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr old,uint flags,uint count,ref SidAttr disable,uint del,IntPtr priv,uint restrict,IntPtr sids,out IntPtr token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetTokenInformation(IntPtr token,int c,IntPtr p,int n);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSidToSid(string s,out IntPtr sid);
    [DllImport("advapi32.dll")] static extern uint GetLengthSid(IntPtr sid);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string name,uint access,uint share,ref SA sa,uint create,uint flags,IntPtr template);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessAsUser(IntPtr token,string exe,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Startup si,out Pi pi);
    public static TokenFacts LastFacts;
    public static Process Start(string exe,string arguments,string cwd,string stdout,string stderr) {
        IntPtr old=IntPtr.Zero,token=IntPtr.Zero,admin=IntPtr.Zero,medium=IntPtr.Zero,label=IntPtr.Zero;
        Pi pi=new Pi();
        try {
            if(!TokenFacts.OpenProcessToken(GetCurrentProcess(),0x000B,out old)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if(!ConvertStringSidToSid("S-1-5-32-544",out admin)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var deny=new SidAttr {Sid=admin,Attr=0};
            if(!CreateRestrictedToken(old,5,1,ref deny,0,IntPtr.Zero,0,IntPtr.Zero,out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if(!ConvertStringSidToSid("S-1-16-8192",out medium)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var ml=new SidAttr {Sid=medium,Attr=0x20};
            label=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SidAttr)));Marshal.StructureToPtr(ml,label,false);
            if(!SetTokenInformation(token,25,label,Marshal.SizeOf(typeof(SidAttr))+(int)GetLengthSid(medium))) throw new Win32Exception(Marshal.GetLastWin32Error());
            var sa=new SA {Size=Marshal.SizeOf(typeof(SA)),Inherit=1};
            using(var o=CreateFile(stdout,0x40000000,1,ref sa,1,0x80,IntPtr.Zero))
            using(var e=CreateFile(stderr,0x40000000,1,ref sa,1,0x80,IntPtr.Zero))
            using(var input=CreateFile("NUL",0x80000000,3,ref sa,3,0,IntPtr.Zero)) {
                if(o.IsInvalid || e.IsInvalid || input.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                var si=new Startup {Size=Marshal.SizeOf(typeof(Startup)),Flags=0x101,Show=1,Input=input.DangerousGetHandle(),Output=o.DangerousGetHandle(),Error=e.DangerousGetHandle()};
                var command=new StringBuilder("\""+exe+"\" "+arguments);
                // Suspended only long enough to independently measure the child token.
                if(!CreateProcessAsUser(token,exe,command,IntPtr.Zero,IntPtr.Zero,true,0x08000004,IntPtr.Zero,cwd,ref si,out pi)) throw new Win32Exception(Marshal.GetLastWin32Error());
                LastFacts=TokenFacts.ReadHandle(pi.Process,pi.Pid);
                if(LastFacts.Administrator || LastFacts.Integrity!=8192) throw new InvalidOperationException("Restricted fixture is not medium/non-admin");
                var process=Process.GetProcessById(pi.Pid);var retained=process.Handle;
                if(ResumeThread(pi.Thread)!=1) throw new Win32Exception(Marshal.GetLastWin32Error());
                return process;
            }
        } finally {
            if(pi.Thread!=IntPtr.Zero) TokenFacts.CloseHandle(pi.Thread);
            if(pi.Process!=IntPtr.Zero) TokenFacts.CloseHandle(pi.Process);
            if(label!=IntPtr.Zero) Marshal.FreeHGlobal(label);
            if(medium!=IntPtr.Zero) LocalFree(medium);
            if(admin!=IntPtr.Zero) LocalFree(admin);
            if(token!=IntPtr.Zero) TokenFacts.CloseHandle(token);
            if(old!=IntPtr.Zero) TokenFacts.CloseHandle(old);
        }
    }
}
