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
        static TokenFacts VerifyController(IntPtr handle,int pid,string root) {
            var user=TokenFacts.ReadHandle(handle,pid);
            var self=TokenFacts.Read(Process.GetCurrentProcess().Id);
            if(!self.Administrator || self.Integrity<12288 || user.Administrator || user.Integrity<8192 || user.Integrity>=12288 || user.Sid!=self.Sid || user.Session!=self.Session)
                throw new InvalidOperationException("Privilege/user/session boundary rejected");
            if(!String.Equals(user.Image,Path.Combine(root,"Portable-VirtualBox-Session-Test.exe"),StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Unexpected controller image");
            using(var f=OpenLocked(user.Image)) if(Hash(f)!=PinnedBuild.FrontendSha256) throw new InvalidOperationException("Controller build hash rejected");
            return user;
        }
        static string Quote(string s) { if(s.IndexOfAny(new[]{'"','\r','\n','\0'})>=0) throw new InvalidOperationException("Invalid argument");return "\""+s+"\""; }
        [STAThread]
        public static int Main(string[] args) {
            string evidenceId=Guid.NewGuid().ToString("N");
            string session=null,safeSession=null;IntPtr controller=IntPtr.Zero;int result=70;System.Threading.Mutex effectMutex=null;bool held=false;
            try {
                int pid,cycle;
                if(args.Length!=3 || (args[0]!="Prepare" && args[0]!="Finish") || !int.TryParse(args[1],out pid) || pid<1 || !int.TryParse(args[2],out cycle) || cycle<1 || cycle>999) return 64;
                // Not a production distribution. These markers do not authenticate anything.
                if(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true" || Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted" || Environment.GetEnvironmentVariable("GITHUB_REPOSITORY")!="zlocorp/Portable-VirtualBox" || Environment.GetEnvironmentVariable("RUNNER_OS")!="Windows") return 9;
                string root=Full(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location));
                string runner=Full(Environment.GetEnvironmentVariable("RUNNER_TEMP"));
                if(!Under(root,runner)) return 9;
                LockParents(root);LockParents(runner);
                controller=TokenFacts.OpenProcess(0x101000,false,pid);
                if(controller==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                TokenFacts caller=VerifyController(controller,pid,root);
                var ms=new MutexSecurity();ms.SetAccessRuleProtection(true,false);
                ms.AddAccessRule(new MutexAccessRule(Admins,MutexRights.FullControl,AccessControlType.Allow));
                ms.AddAccessRule(new MutexAccessRule(SystemSid,MutexRights.FullControl,AccessControlType.Allow));
                bool created;effectMutex=new System.Threading.Mutex(false,"Global\\PortableVirtualBox.PrivilegedEffect",out created,ms);
                try { held=effectMutex.WaitOne(0); } catch(System.Threading.AbandonedMutexException) { throw new InvalidOperationException("Abandoned privileged effect; manual inspection required"); }
                if(!held) throw new InvalidOperationException("Another privileged operation is active");
                string store=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"PortableVirtualBox.Experiment");
                LockParents(Path.GetDirectoryName(store));CreateProtectedDirectory(store,caller.Sid,true);
                session=Path.Combine(store,"pvbox-manager-"+pid+"-"+cycle);
                bool prepare=args[0]=="Prepare";
                CreateProtectedDirectory(session,caller.Sid,!prepare);safeSession=session;
                string app=Path.Combine(session,"app64"),code=Path.Combine(session,"code");
                CreateProtectedDirectory(app,caller.Sid,!prepare);CreateProtectedDirectory(code,caller.Sid,!prepare);
                InstallScripts(session,prepare);
                ValidateAndStage(Path.Combine(root,"app64"),app,caller.Sid,prepare);
                string binding=Path.Combine(session,"controller.json");
                var current=new Dictionary<string,object>{{"pid",pid},{"created",caller.Created.ToString(CultureInfo.InvariantCulture)},{"image",caller.Image},{"sid",caller.Sid},{"cycle",cycle},{"root",root}};
                if(prepare) WriteNew(binding,Encoding.UTF8.GetBytes(Json.Serialize(current)));
                using(var f=OpenLocked(binding)) using(var reader=new StreamReader(f,Encoding.UTF8)) {
                    var original=Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());
                    foreach(var pair in current) if(!original.ContainsKey(pair.Key) || Convert.ToString(original[pair.Key],CultureInfo.InvariantCulture)!=Convert.ToString(pair.Value,CultureInfo.InvariantCulture)) throw new InvalidOperationException("Stale controller generation");
                }
                string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe");
                LockParents(Path.GetDirectoryName(powershell));
                string working=Path.Combine(session,"code");
                var info=new ProcessStartInfo(powershell,"-NoLogo -NoProfile -NonInteractive -File "+Quote(Path.Combine(working,"privileged_session_worker.ps1"))+" -Action "+args[0]+" -PortableRoot "+Quote(root)+" -SessionDir "+Quote(session)+" -ControllerPid "+pid+" -ControllerCreated "+caller.Created);
                info.UseShellExecute=false;info.CreateNoWindow=true;info.WorkingDirectory=working;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
                // Never inherit low-user module search paths, PS profiles, PATH,
                // temp dirs or .NET startup/profiler variables into elevated effects.
                info.EnvironmentVariables.Clear();
                string windows=Directory.GetParent(Environment.SystemDirectory).FullName;
                info.EnvironmentVariables["SystemRoot"]=windows;info.EnvironmentVariables["WINDIR"]=windows;
                info.EnvironmentVariables["PATH"]=Environment.SystemDirectory+";"+Path.GetDirectoryName(powershell);
                info.EnvironmentVariables["ProgramFiles"]=Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                info.EnvironmentVariables["ProgramData"]=Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                info.EnvironmentVariables["TEMP"]=session;info.EnvironmentVariables["TMP"]=session;
                info.EnvironmentVariables["PSModulePath"]=Path.Combine(Path.GetDirectoryName(powershell),"Modules")+";"+Path.Combine(windows,"System32","WindowsPowerShell","v1.0","Modules");
                foreach(string key in new[]{"GITHUB_ACTIONS","GITHUB_REPOSITORY","RUNNER_ENVIRONMENT","RUNNER_OS","GITHUB_SHA"}) info.EnvironmentVariables[key]=Environment.GetEnvironmentVariable(key)??"";
                info.EnvironmentVariables["RUNNER_TEMP"]=store; // fixed protected effect boundary, not an input from the low caller
                using(var process=new Process {StartInfo=info}) {
                    process.Start();var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();
                    if(!process.WaitForExit(150000)) throw new InvalidOperationException("Elevated effect timeout; no speculative cleanup");
                    WriteNew(Path.Combine(session,"helper-"+args[0]+"-"+evidenceId+".stdout.txt"),Encoding.UTF8.GetBytes(stdout.GetAwaiter().GetResult()));
                    WriteNew(Path.Combine(session,"helper-"+args[0]+"-"+evidenceId+".stderr.txt"),Encoding.UTF8.GetBytes(stderr.GetAwaiter().GetResult()));
                    var helper=TokenFacts.Read(Process.GetCurrentProcess().Id);
                    WriteNew(Path.Combine(session,"helper-"+args[0]+"-"+evidenceId+".json"),Encoding.UTF8.GetBytes(Json.Serialize(new{action=args[0],helper=helper,controller=caller,childExit=process.ExitCode})));
                    if(process.ExitCode!=0) throw new InvalidOperationException("Fixed effect worker rejected operation");
                }
                if(TokenFacts.WaitForSingleObject(controller,0)!=258) throw new InvalidOperationException("Controller exited during privileged operation");
                if(args[0]=="Finish") {
                    foreach(var item in Locks) item.Dispose();Locks.Clear();LockedDirs.Clear();
                    RemoveVerifiedPayload(session);
                }
                result=0;
            } catch(Exception e) {
                // Only an already validated protected session can hold failure evidence.
                try { if(safeSession!=null) WriteNew(Path.Combine(safeSession,"helper-error-"+Guid.NewGuid().ToString("N")+".txt"),Encoding.UTF8.GetBytes(e.GetType().Name+": "+e.Message)); } catch { }
                result=70;
            } finally {
                foreach(var item in Locks) item.Dispose();
                if(controller!=IntPtr.Zero) TokenFacts.CloseHandle(controller);
                if(effectMutex!=null) {if(held) effectMutex.ReleaseMutex();effectMutex.Dispose();}
            }
            return result;
        }
    }
}
