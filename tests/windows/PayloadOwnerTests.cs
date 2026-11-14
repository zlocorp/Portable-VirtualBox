// File-only integration tests of the real helper gates. Never enter helper Main,
// query a controller, or invoke SCM/PnP/effect workers. Only own GUID temp tree.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
namespace PortableVBox {
 public static class PayloadOwnerTests {
  static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
  static readonly string Sid="S-1-5-21-111111111-222222222-333333333-1234";
  static string root,session,ownerBinding;static int checks;
  static readonly TokenFacts Caller=new TokenFacts {Pid=12345,Created=123456789,Sid=Sid};
  [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeFileHandle handle,int type,uint requested,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
  [DllImport("advapi32.dll")] static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetFileSecurityW(string path,uint information,byte[] descriptor);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr pointer);
  static RawSecurityDescriptor NativeFileAcl(string path) {
   using(var handle=(SafeFileHandle)Call("OpenPayloadObject",path,false,false)) {
    IntPtr owner,group,dacl,sacl,descriptor;
    uint error=GetSecurityInfo(handle,1,5,out owner,out group,out dacl,out sacl,out descriptor);
    if(error!=0) throw new System.ComponentModel.Win32Exception((int)error);
    try {var bytes=new byte[GetSecurityDescriptorLength(descriptor)];Marshal.Copy(descriptor,bytes,0,bytes.Length);return new RawSecurityDescriptor(bytes,0);}
    finally {LocalFree(descriptor);}
   }
  }
  static object Call(string name,params object[] args) {
   try {return typeof(SessionHelper).GetMethod(name,BindingFlags.NonPublic|BindingFlags.Static).Invoke(null,args);}
   catch(TargetInvocationException error) {throw error.InnerException;}
  }
  static string Digest(byte[] bytes) {using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
  static void Check(bool value,string label) {++checks;if(!value) throw new Exception("FAIL payload owner: "+label);}
  static void Refuses(Action action,string label) {
   bool refused=false;try {action();} catch(InvalidOperationException) {refused=true;} catch(InvalidDataException) {refused=true;}
   Check(refused,label);
  }
  static Dictionary<string,object> Owner() {return new Dictionary<string,object> {
   {"pid",Caller.Pid},{"created",Caller.Created.ToString()},{"cycle",7},{"sid",Sid},{"root",root},{"image",Path.Combine(root,PinnedBuild.FrontendName)}};}
  static Dictionary<string,object> Intent() {return new Dictionary<string,object> {
   {"schema",1},{"phase","pre-system-effects"},{"payload_protocol",1},{"helper_sha256","helper-test-hash"},
   {"frontend_sha256",PinnedBuild.FrontendSha256},{"controller_pid",Caller.Pid},{"controller_created_filetime",Caller.Created.ToString()},
   {"cycle",7},{"sid",Sid},{"portable_root",root},{"protected_app",Path.Combine(session,"app64")}};}
  static void Write(string name,Dictionary<string,object> value) {
   string path=Path.Combine(session,name);if(File.Exists(path)) File.Delete(path);
   Call("WriteNew",path,Encoding.UTF8.GetBytes(Json.Serialize(value)));
  }
  static string VerifyOwner() {return (string)Call("VerifyPayloadOwner",session,root,Caller,12345,7,false,"helper-test-hash");}
  static void OwnerContracts() {
   Write("controller.json",Owner());Write("prepare-intent.json",Intent());ownerBinding=VerifyOwner();
   Check(!String.IsNullOrEmpty(ownerBinding),"matching protected normal Finish owner accepted");
   foreach(bool owner in new[]{true,false}) {
    var baseline=owner?Owner():Intent();string file=owner?"controller.json":"prepare-intent.json";
    foreach(string key in new List<string>(baseline.Keys)) {
     var changed=new Dictionary<string,object>(baseline);changed[key]="foreign";Write(file,changed);
     Refuses(()=>VerifyOwner(),file+" rejects changed "+key);
     changed.Remove(key);Write(file,changed);Refuses(()=>VerifyOwner(),file+" rejects missing "+key);
     changed[key]=null;Write(file,changed);Refuses(()=>VerifyOwner(),file+" rejects null "+key);
     Write(file,baseline);
    }
   }
   foreach(string generation in new[]{"0","-1","9223372036854775808"," 123456789","123456790"}) {
    var owner=Owner();var intent=Intent();owner["created"]=generation;intent["controller_created_filetime"]=generation;
    Write("controller.json",owner);Write("prepare-intent.json",intent);Refuses(()=>VerifyOwner(),"invalid or stale generation "+generation);
   }
   Write("controller.json",Owner());Write("prepare-intent.json",Intent());
   Caller.Pid++;try {Refuses(()=>VerifyOwner(),"caller PID differs from original");} finally {Caller.Pid--;}
   Check(VerifyOwner()==ownerBinding,"owner baseline restored after mutations");
  }
  static Dictionary<string,object> Binding(string action) {return new Dictionary<string,object> {
   {"schema",1},{"mode",PinnedBuild.Mode},{"action",action},{"protected_session",session},{"portable_root",root},{"sid",Sid},
   {"cycle",7},{"frontend_sha256",PinnedBuild.FrontendSha256},{"controller_pid",12345},{"controller_created_filetime",Caller.Created.ToString()}};}
  static void JournalCase(Dictionary<string,object> binding,string intent,string outcome,int events,bool accept,string label) {
   string name="helper-"+(intent=="Recover"?"Recover":"Finish")+"-"+Guid.NewGuid().ToString("N")+".journal";
   string path=Path.Combine(session,name),serialized=Json.Serialize(binding);
   using(var writer=DurableJournal.CreateNew(path,serialized,intent)) {
    // Match production inherited ACL and administrator owner while retaining writer.
    var security=File.GetAccessControl(path);security.SetOwner(new SecurityIdentifier("S-1-5-32-544"));File.SetAccessControl(path,security);
    if(events>=2) writer.WorkerExited(outcome);if(events==3) writer.Complete("{} ");
    var checkpoint=new SessionHelper.PayloadCheckpoint {OwnerBinding=ownerBinding,InitiatorPid=12345,InitiatorCreated=Caller.Created.ToString(),
     WorkerJournalName=name,WorkerJournalBinding=serialized,WorkerJournalSha256=Digest((byte[])Call("PayloadReadWorkerJournal",path))};
    // Invoke the actual production gate, not merely journal/snapshot inspection.
    if(!accept) {Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),label);return;}
    Call("VerifyPayloadWorker",session,checkpoint);Check(true,label+" with original writer retained");
    string digest=checkpoint.WorkerJournalSha256;checkpoint.WorkerJournalSha256=new string('0',64);
    Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"changed checkpoint digest");checkpoint.WorkerJournalSha256=digest;
    checkpoint.WorkerJournalBinding=serialized+" ";Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"foreign checkpoint journal binding");checkpoint.WorkerJournalBinding=serialized;
    checkpoint.WorkerJournalName="../"+name;Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"journal path escape");checkpoint.WorkerJournalName=name;
    checkpoint.InitiatorPid++;Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"checkpoint initiator PID mismatch");checkpoint.InitiatorPid--;
    checkpoint.InitiatorCreated="987";Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"checkpoint initiator generation mismatch");checkpoint.InitiatorCreated=Caller.Created.ToString();
    writer.Complete("{}");Refuses(()=>Call("VerifyPayloadWorker",session,checkpoint),"journal changed after accepted snapshot");
   }
  }
  static void WorkerContracts() {
   const string success="{\"child_exit\":0,\"within_deadline\":true}";
   foreach(string action in new[]{"Finish","Recover"}) JournalCase(Binding(action),action,success,2,true,action+" accepted");
   foreach(string key in new List<string>(Binding("Finish").Keys)) {
    var changed=Binding("Finish");changed[key]="foreign";JournalCase(changed,"Finish",success,2,false,"foreign binding "+key);
    changed=Binding("Finish");changed.Remove(key);JournalCase(changed,"Finish",success,2,false,"missing binding "+key);
   }
   foreach(string outcome in new[]{"{\"child_exit\":1,\"within_deadline\":true}","{\"child_exit\":0,\"within_deadline\":false}",
    "{\"child_exit\":\"0\",\"within_deadline\":true}","{\"child_exit\":0,\"within_deadline\":\"true\"}","{\"child_exit\":0}","{\"within_deadline\":true}"})
    JournalCase(Binding("Finish"),"Finish",outcome,2,false,"unsuccessful or malformed exit "+outcome);
   JournalCase(Binding("Finish"),"Finish",success,1,false,"intent-only journal");
   JournalCase(Binding("Finish"),"Finish",success,3,false,"already completed journal");
   JournalCase(Binding("Recover"),"Finish",success,2,false,"action differs from journal intent and name");
   JournalCase(Binding("Prepare"),"Prepare",success,2,false,"Prepare cannot authorize cleanup");
  }
  static bool[] Observe(PayloadCleanupPlan plan,string[] identities) {return (bool[])Call("ObservePayload",session,Sid,plan,identities);}
  static void ObserveContracts() {
   byte[] bytes=new byte[]{1,2,3};string hash=Digest(bytes);
   var plan=new PayloadCleanupPlan(new[]{new PayloadCleanupEntry("app64/a",3,hash),new PayloadCleanupEntry("code/b",3,hash)});
   Call("CreateProtectedDirectory",Path.Combine(session,"app64"),Sid,false);
   Call("CreateProtectedDirectory",Path.Combine(session,"code"),Sid,false);
   string first=Path.Combine(session,"app64","a"),future=Path.Combine(session,"code","b");
   Call("WriteNew",first,bytes);Call("WriteNew",future,bytes);
   var identities=new string[plan.Items.Count];
   for(int i=0;i<identities.Length;i++) {
    var entry=plan.Items[i];string path=(string)Call("PayloadPath",session,entry.Relative);
    identities[i]=(string)Call("CapturePayloadObject",path,Sid,entry.Directory,entry.Length,entry.Sha256);
   }
   using(var journal=PayloadCleanupJournal.CreateNew(Path.Combine(session,"observe-test.journal"),ownerBinding+plan.Digest,plan.Items.Count)) {
    bool[] initial=Observe(plan,identities);foreach(bool present in initial) Check(present,"initial planned object present");
    plan.ValidatePresence(journal.State,initial);Check(true,"initial observed identity and presence accepted");
    string extra=Path.Combine(session,"app64","extra");Call("WriteNew",extra,bytes);
    Refuses(()=>Observe(plan,identities),"unplanned entry rejected by production ObservePayload");File.Delete(extra);
    string original=Path.Combine(session,"saved-original");File.Move(first,original);
    try {
     Call("WriteNew",first,bytes);Refuses(()=>Observe(plan,identities),"same-byte replacement rejected by real object identity");
    } finally {if(File.Exists(first)) File.Delete(first);File.Move(original,first);}
    string savedFuture=Path.Combine(session,"saved-future");File.Move(future,savedFuture);
    try {Refuses(()=>plan.ValidatePresence(journal.State,Observe(plan,identities)),"missing future object cannot infer progress");}
    finally {File.Move(savedFuture,future);}
    var savedRaw=NativeFileAcl(future);var savedAcl=new byte[savedRaw.BinaryLength];savedRaw.GetBinaryForm(savedAcl,0);
    string savedSddl=savedRaw.GetSddlForm(AccessControlSections.Owner|AccessControlSections.Access);
    try {
     var wrong=File.GetAccessControl(future);wrong.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier("S-1-1-0"),FileSystemRights.Read,AccessControlType.Allow));
     File.SetAccessControl(future,wrong);Refuses(()=>Observe(plan,identities),"wrong inherited file ACL rejected");
     Check(Digest(File.ReadAllBytes(future))==hash,"ACL rejection preserves original bytes");
    } finally {
     if(!SetFileSecurityW(future,0x80000005U,savedAcl)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
     Check(NativeFileAcl(future).GetSddlForm(AccessControlSections.Owner|AccessControlSections.Access)==savedSddl,
      "negative fixture restores exact raw ACL including IO OWNER_RIGHTS");
    }
    plan.ValidatePresence(journal.State,Observe(plan,identities));Check(true,"fixture restored after negative observations");
    for(int i=0;i<plan.Items.Count;i++) {
     var entry=plan.Items[i];string target=(string)Call("PayloadPath",session,entry.Relative);
     journal.Begin(i);Call("ReleasePayloadLock",target);
     bool blocked=false;
     try {Directory.Move(session,session+"-moved");} catch(IOException) {blocked=true;}
     Check(blocked,"retained real session parent lock blocks rename after exact-target release");
     if(entry.Directory) {
      string child=Path.Combine(target,"unplanned-child");Call("WriteNew",child,bytes);
      bool refused=false;
      try {Call("DeletePayloadObject",target,Sid,true,0L,null,identities[i]);} catch(System.ComponentModel.Win32Exception) {refused=true;}
      Check(refused,"nonempty directory native disposition refuses");
      Check(journal.State.Pending && journal.State.Completed==i,"nonempty directory refusal preserves BEGIN");
      Check(Digest(File.ReadAllBytes(child))==hash,"unknown child remains unchanged");
      Refuses(()=>Observe(plan,identities),"resume observation rejects unplanned child");
      File.Delete(child);Call("ReleasePayloadLock",target);
     }
     Call("DeletePayloadObject",target,Sid,entry.Directory,entry.Length,entry.Sha256,identities[i]);
     Check(!(bool)Call("PayloadExists",target),"real native deletion establishes absence");
     plan.ValidatePresence(journal.State,Observe(plan,identities));Check(true,"pending BEGIN accepts exact current absent object");
     journal.Done(i);plan.ValidatePresence(journal.State,Observe(plan,identities));Check(true,"DONE accepts observed absence");
     if(i==0) {
      Call("WriteNew",target,bytes);
      try {Refuses(()=>plan.ValidatePresence(journal.State,Observe(plan,identities)),"recreated completed object rejected by integrated observation");}
      finally {File.Delete(target);}
     }
    }
    journal.Complete();plan.ValidatePresence(journal.State,Observe(plan,identities));
    Check(journal.State.Complete,"real journal completes only after all files and directories absent");
   }
  }
  static void ReleaseLocks() {
   var locks=(IList)typeof(SessionHelper).GetField("Locks",BindingFlags.NonPublic|BindingFlags.Static).GetValue(null);
   foreach(IDisposable item in locks) item.Dispose();locks.Clear();
   foreach(string name in new[]{"LockedDirs","LockPaths"}) {
    object map=typeof(SessionHelper).GetField(name,BindingFlags.NonPublic|BindingFlags.Static).GetValue(null);map.GetType().GetMethod("Clear").Invoke(map,null);
   }
  }
  public static int Main() {
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT) {Console.WriteLine("SKIP payload owner native tests: Windows required");return 0;}
   if(!new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator)) throw new InvalidOperationException("Payload owner fixture requires elevated Windows for Administrators ownership");
   root=Path.Combine(Path.GetTempPath(),"pvbox-owner-"+Guid.NewGuid().ToString("N"));session=Path.Combine(root,"session");
   try {
    Call("CreateProtectedDirectory",root,Sid,false);Call("CreateProtectedDirectory",session,Sid,false);
    OwnerContracts();WorkerContracts();ObserveContracts();Console.WriteLine("PASS payload owner integrated gates: "+checks);return 0;
   } finally {ReleaseLocks();if(Directory.Exists(root)) Directory.Delete(root,true);}
  }
 }
}
