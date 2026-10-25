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
            if(!String.Equals(user.Image,Path.Combine(root,PinnedBuild.FrontendName),StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Unexpected controller image");
            using(var f=OpenLocked(user.Image)) if(Hash(f)!=PinnedBuild.FrontendSha256) throw new InvalidOperationException("Controller build hash rejected");
            return user;
        }
        // A recovery target is ALWAYS a previously protected session, never a
        // user-selected path. The old owner must be absent; PID reuse, access
        // denial and every ambiguous state refuse recovery rather than guessing.
        static bool OrphanControllerAbsent(int oldPid) {
            if(oldPid<1) return false;
            try { using(var old=Process.GetProcessById(oldPid)) return false; }
            catch(ArgumentException) { return true; }
        }
        static string ReadProtectedField(Dictionary<string,object> row,string field) {
            object value;
            if(!row.TryGetValue(field,out value) || value==null) throw new InvalidOperationException("Missing protected recovery evidence");
            return Convert.ToString(value,CultureInfo.InvariantCulture);
        }
        static Dictionary<string,object> ProtectedJson(string path) {
            using(var f=OpenLocked(path)) {
                if(f.Length<1 || f.Length>16384) throw new InvalidOperationException("Untrusted or ambiguous recovery target");
                using(var r=new StreamReader(f,Encoding.UTF8)) return Json.Deserialize<Dictionary<string,object>>(r.ReadToEnd());
            }
        }
        static long VerifyOriginalSession(string session,string root,string sid,int oldPid,int cycle) {
            if(!OrphanControllerAbsent(oldPid) || oldPid<1) throw new InvalidOperationException("Untrusted or ambiguous recovery target");
            var original=ProtectedJson(Path.Combine(session,"controller.json"));
            var receipt=ProtectedJson(Path.Combine(session,"session.json"));
            string formerImage=Path.Combine(root,PinnedBuild.FrontendName);
            string created=ReadProtectedField(original,"created");
            if(ReadProtectedField(original,"pid")!=oldPid.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(original,"cycle")!=cycle.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(original,"sid")!=sid ||
               !String.Equals(ReadProtectedField(original,"root"),root,StringComparison.OrdinalIgnoreCase) ||
               !String.Equals(ReadProtectedField(original,"image"),formerImage,StringComparison.OrdinalIgnoreCase) ||
               ReadProtectedField(receipt,"schema")!="1" || ReadProtectedField(receipt,"prepared")!="True" ||
               ReadProtectedField(receipt,"controller_pid")!=oldPid.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(receipt,"controller_created_filetime")!=created ||
               !String.Equals(ReadProtectedField(receipt,"portable_root"),root,StringComparison.OrdinalIgnoreCase) ||
               !String.Equals(ReadProtectedField(receipt,"protected_app"),Path.Combine(session,"app64"),StringComparison.OrdinalIgnoreCase) ||
               !String.Equals(ReadProtectedField(receipt,"controller_image"),formerImage,StringComparison.OrdinalIgnoreCase) ||
               File.Exists(Path.Combine(session,"recovery-quiescent.json")) ||
               Directory.Exists(Path.Combine(session,"cleanup")) ||
               File.Exists(Path.Combine(session,"payload-removed.json")) ||
               !OrphanControllerAbsent(oldPid))
                throw new InvalidOperationException("Untrusted or ambiguous recovery target");
            long filetime;
            if(!long.TryParse(created,NumberStyles.None,CultureInfo.InvariantCulture,out filetime) || filetime<=0)
                throw new InvalidOperationException("Invalid former owner generation");
            return filetime;
        }
        // A durable intent created BEFORE the first effect enables recovery
        // of a *verified* incomplete preparation, not arbitrary service rescue.
        // Missing original owner, missing report or changed SID/root always deny.
        static long VerifyInterruptedSession(string session,string root,string sid,int oldPid,int cycle) {
            if(!OrphanControllerAbsent(oldPid)) throw new InvalidOperationException("Original controller still present");
            if(File.Exists(Path.Combine(session,"session.json")) ||
               File.Exists(Path.Combine(session,"partial-recovery-quiescent.json")) ||
               File.Exists(Path.Combine(session,"recovery-quiescent.json")) ||
               File.Exists(Path.Combine(session,"quiescent-session.json")) ||
               Directory.Exists(Path.Combine(session,"cleanup")) ||
               File.Exists(Path.Combine(session,"payload-removed.json")))
                throw new InvalidOperationException("Untrusted or replayed incomplete session");
            var original=ProtectedJson(Path.Combine(session,"controller.json"));
            var intent=ProtectedJson(Path.Combine(session,"prepare-intent.json"));
            string formerImage=Path.Combine(root,PinnedBuild.FrontendName);
            string created=ReadProtectedField(original,"created");
            if(ReadProtectedField(original,"pid")!=oldPid.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(original,"cycle")!=cycle.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(original,"sid")!=sid ||
               !String.Equals(ReadProtectedField(original,"root"),root,StringComparison.OrdinalIgnoreCase) ||
               !String.Equals(ReadProtectedField(original,"image"),formerImage,StringComparison.OrdinalIgnoreCase) ||
               ReadProtectedField(intent,"schema")!="1" ||
               ReadProtectedField(intent,"phase")!="pre-system-effects" ||
               ReadProtectedField(intent,"controller_pid")!=oldPid.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(intent,"controller_created_filetime")!=created ||
               ReadProtectedField(intent,"cycle")!=cycle.ToString(CultureInfo.InvariantCulture) ||
               ReadProtectedField(intent,"sid")!=sid ||
               ReadProtectedField(intent,"frontend_sha256")!=PinnedBuild.FrontendSha256 ||
               !String.Equals(ReadProtectedField(intent,"portable_root"),root,StringComparison.OrdinalIgnoreCase) ||
               !String.Equals(ReadProtectedField(intent,"protected_app"),Path.Combine(session,"app64"),StringComparison.OrdinalIgnoreCase) ||
               !OrphanControllerAbsent(oldPid))
                throw new InvalidOperationException("Untrusted or ambiguous interrupted preparation");
            long filetime;
            if(!long.TryParse(created,NumberStyles.None,CultureInfo.InvariantCulture,out filetime) || filetime<=0)
                throw new InvalidOperationException("Invalid interrupted owner generation");
            return filetime;
        }
        static string Quote(string s) { if(s.IndexOfAny(new[]{'"','\r','\n','\0'})>=0) throw new InvalidOperationException("Invalid argument");return "\""+s+"\""; }
        [STAThread]
        public static int Main(string[] args) {
            string evidenceId=Guid.NewGuid().ToString("N");
            string session=null,safeSession=null;IntPtr controller=IntPtr.Zero;int result=70;System.Threading.Mutex effectMutex=null;bool held=false;
            try {
                int pid,cycle,oldPid=0;
                bool recovery=args.Length==4 && args[0]=="Recover";
                if(recovery) {
                    if(!int.TryParse(args[1],out pid) || pid<1 ||
                       !int.TryParse(args[2],out oldPid) || oldPid<1 || oldPid==pid ||
                       !int.TryParse(args[3],out cycle) || cycle<1 || cycle>999) return 64;
                } else if(args.Length!=3 || (args[0]!="Prepare" && args[0]!="Finish") ||
                          !int.TryParse(args[1],out pid) || pid<1 ||
                          !int.TryParse(args[2],out cycle) || cycle<1 || cycle>999) return 64;
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
                session=Path.Combine(store,"pvbox-manager-"+(recovery?oldPid:pid)+"-"+cycle);
                bool prepare=args[0]=="Prepare";
                if(recovery && (!Directory.Exists(session) || !Directory.Exists(Path.Combine(session,"app64")) ||
                                !Directory.Exists(Path.Combine(session,"code"))))
                    throw new InvalidOperationException("Untrusted or ambiguous recovery target");
                CreateProtectedDirectory(session,caller.Sid,!prepare);safeSession=session;
                string app=Path.Combine(session,"app64"),code=Path.Combine(session,"code");
                CreateProtectedDirectory(app,caller.Sid,!prepare);CreateProtectedDirectory(code,caller.Sid,!prepare);
                InstallScripts(session,prepare);
                ValidateAndStage(Path.Combine(root,"app64"),app,caller.Sid,prepare);
                string binding=Path.Combine(session,"controller.json");
                long originalCreated=0;
                bool incomplete=recovery && !File.Exists(Path.Combine(session,"session.json"));
                if(recovery) {
                    originalCreated=incomplete?
                        VerifyInterruptedSession(session,root,caller.Sid,oldPid,cycle):
                        VerifyOriginalSession(session,root,caller.Sid,oldPid,cycle);
                } else {
                    var current=new Dictionary<string,object>{{"pid",pid},{"created",caller.Created.ToString(CultureInfo.InvariantCulture)},{"image",caller.Image},{"sid",caller.Sid},{"cycle",cycle},{"root",root}};
                    if(prepare) WriteNew(binding,Encoding.UTF8.GetBytes(Json.Serialize(current)));
                    using(var f=OpenLocked(binding)) using(var reader=new StreamReader(f,Encoding.UTF8)) {
                        var original=Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());
                        foreach(var pair in current) if(!original.ContainsKey(pair.Key) || Convert.ToString(original[pair.Key],CultureInfo.InvariantCulture)!=Convert.ToString(pair.Value,CultureInfo.InvariantCulture)) throw new InvalidOperationException("Stale controller generation");
                    }
                }
                if(prepare) {
                    // Durable one-shot intent is committed before any driver,
                    // service or guest effect can start. Stale paths fail closed.
                    string intent=Path.Combine(session,"prepare-intent.json");
                    WriteNew(intent,Encoding.UTF8.GetBytes(Json.Serialize(new {
                        schema=1,phase="pre-system-effects",controller_pid=pid,
                        controller_created_filetime=caller.Created.ToString(CultureInfo.InvariantCulture),
                        cycle=cycle,sid=caller.Sid,portable_root=root,protected_app=app,
                        frontend_sha256=PinnedBuild.FrontendSha256
                    })));
                }
                string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe");
                LockParents(Path.GetDirectoryName(powershell));
                string working=Path.Combine(session,"code");
                string extra=recovery?" -OriginalControllerPid "+oldPid+" -OriginalControllerCreated "+originalCreated+(incomplete?" -IncompletePreparation":""):"";
                // These single-word injections are exclusively for the
                // GitHub-hosted disposable fixture. They never enable rescue,
                // change inputs, or disable any ownership/publisher checks.
                string testBreak=prepare?(Environment.GetEnvironmentVariable("PVBOX_TEST_BREAK_AT")??""):"";
                if(testBreak=="Stage" || testBreak=="Start" || testBreak=="Sds")
                    extra+=" -TestBreakAfter "+testBreak;
                else if(testBreak.Length>0) throw new InvalidOperationException("Unknown controlled test breakpoint");
                var info=new ProcessStartInfo(powershell,"-NoLogo -NoProfile -NonInteractive -File "+Quote(Path.Combine(working,"privileged_session_worker.ps1"))+" -Action "+args[0]+" -PortableRoot "+Quote(root)+" -SessionDir "+Quote(session)+" -ControllerPid "+pid+" -ControllerCreated "+caller.Created+" -FrontendName "+PinnedBuild.FrontendName+extra);
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
                if(args[0]=="Finish" || recovery) {
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
