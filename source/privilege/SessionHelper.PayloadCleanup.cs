// Narrow continuation after committed teardown only. Never calls an OS effect
// worker, reconstructs acquisition ownership, or grants service/package retry.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;
namespace PortableVBox {
 public static partial class SessionHelper {
  public sealed class PayloadCheckpoint {
   public int Schema;
   public string OwnerBinding;
   public int InitiatorPid;
   public string InitiatorCreated;
   public string ManifestBase64;
   public string PlanSha256;
   public string[] ObjectIdentities;
   public string PublishedInf;
   public string StageSha256;
   public string CleanupSha256;
   public string WorkerJournalName;
   public string WorkerJournalBinding;
   public string WorkerJournalSha256;
  }
  static readonly UTF8Encoding PayloadUtf8=new UTF8Encoding(false,true);
  static byte[] PayloadRead(string path,int bound) {
   using(var stream=OpenLocked(path)) {
    if(stream.Length<1 || stream.Length>bound) throw new InvalidOperationException("Payload evidence size bound");
    byte[] bytes=new byte[(int)stream.Length];int at=0;
    while(at<bytes.Length) {int n=stream.Read(bytes,at,bytes.Length-at);if(n==0) throw new EndOfStreamException();at+=n;}
    if(stream.ReadByte()!=-1 || stream.Length!=bytes.Length) throw new InvalidOperationException("Payload evidence changed");
    return bytes;
   }
  }
  static byte[] PayloadReadWorkerJournal(string path) {
   // The original writer is deliberately retained until payload completion.
   // A read-only sharing mode would deny that existing write handle on Windows.
   using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
    if(stream.Length<1 || stream.Length>65536) throw new InvalidOperationException("Teardown journal size bound");
    byte[] bytes=new byte[(int)stream.Length];int at=0;
    while(at<bytes.Length) {int n=stream.Read(bytes,at,bytes.Length-at);if(n==0) throw new EndOfStreamException();at+=n;}
    if(stream.ReadByte()!=-1 || stream.Length!=bytes.Length) throw new InvalidOperationException("Teardown journal changed");
    return bytes;
   }
  }
  static string VerifyPayloadOwner(string session,string root,TokenFacts caller,int originalPid,int cycle,bool recovery,string helperHash) {
   var owner=ProtectedJson(Path.Combine(session,"controller.json"));
   var intent=ProtectedJson(Path.Combine(session,"prepare-intent.json"));
   string created=ReadProtectedField(owner,"created");long generation;
   if(!long.TryParse(created,NumberStyles.None,CultureInfo.InvariantCulture,out generation) || generation<1 ||
      ReadProtectedField(owner,"pid")!=originalPid.ToString(CultureInfo.InvariantCulture) ||
      ReadProtectedField(owner,"cycle")!=cycle.ToString(CultureInfo.InvariantCulture) ||
      ReadProtectedField(owner,"sid")!=caller.Sid || ReadProtectedField(owner,"root")!=root ||
      ReadProtectedField(owner,"image")!=Path.Combine(root,PinnedBuild.FrontendName) ||
      ReadProtectedField(intent,"schema")!="1" || ReadProtectedField(intent,"phase")!="pre-system-effects" ||
      ReadProtectedField(intent,"payload_protocol")!="1" || ReadProtectedField(intent,"helper_sha256")!=helperHash ||
      ReadProtectedField(intent,"frontend_sha256")!=PinnedBuild.FrontendSha256 ||
      ReadProtectedField(intent,"controller_pid")!=originalPid.ToString(CultureInfo.InvariantCulture) ||
      ReadProtectedField(intent,"controller_created_filetime")!=created || ReadProtectedField(intent,"cycle")!=cycle.ToString(CultureInfo.InvariantCulture) ||
      ReadProtectedField(intent,"sid")!=caller.Sid || ReadProtectedField(intent,"portable_root")!=root ||
      ReadProtectedField(intent,"protected_app")!=Path.Combine(session,"app64"))
    throw new InvalidOperationException("Foreign or legacy payload owner/build");
   if(recovery) {if(!OrphanControllerAbsent(originalPid)) throw new InvalidOperationException("Original payload owner still present or unknown");}
   else if(originalPid!=caller.Pid || generation!=caller.Created) throw new InvalidOperationException("Stale payload owner generation");
   return Json.Serialize(new {protocol=1,helper_sha256=helperHash,frontend_sha256=PinnedBuild.FrontendSha256,mode=PinnedBuild.Mode,
    protected_session=session,portable_root=root,sid=caller.Sid,original_pid=originalPid,original_created=created,cycle=cycle});
  }
  static PayloadCleanupPlan PayloadPlan(byte[] manifestBytes) {
   if(manifestBytes.Length<1 || manifestBytes.Length>131072) throw new InvalidOperationException("Payload inventory bound");
   var manifest=ValidateManifest(Json.Deserialize<Dictionary<string,object>>(PayloadUtf8.GetString(manifestBytes)));
   var entries=new List<PayloadCleanupEntry>();
   foreach(Dictionary<string,object> row in (IEnumerable)manifest["files"])
    entries.Add(new PayloadCleanupEntry("app64/"+(string)row["path"],Convert.ToInt64(row["size"],CultureInfo.InvariantCulture),(string)row["sha256"]));
   entries.Add(new PayloadCleanupEntry("app64/.prepared.json",manifestBytes.Length,Hash(manifestBytes)));
   foreach(string script in Scripts) {byte[] bytes=Resource(script);entries.Add(new PayloadCleanupEntry("code/"+script,bytes.Length,Hash(bytes)));}
   return new PayloadCleanupPlan(entries);
  }
  static string PayloadPath(string session,string relative) {
   string path=Full(Path.Combine(session,relative.Replace('/','\\')));
   if(!Under(path,session)) throw new InvalidOperationException("Payload plan escaped session");return path;
  }
  static bool VBoxName(string name) {return name.StartsWith("VBox",StringComparison.OrdinalIgnoreCase);}
  static void AssertNoVBoxResources(string published) {
   if(!Regex.IsMatch(published??"",@"\Aoem[0-9]+\.inf\z",RegexOptions.CultureInvariant)) throw new InvalidOperationException("Invalid exact package identity");
   using(var lm=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,RegistryView.Registry64)) {
    foreach(string key in new[]{@"SOFTWARE\Oracle\VirtualBox",@"SOFTWARE\WOW6432Node\Oracle\VirtualBox"})
     using(var installed=lm.OpenSubKey(key,false)) if(installed!=null) throw new InvalidOperationException("A VirtualBox installation is present");
    using(var services=lm.OpenSubKey(@"SYSTEM\CurrentControlSet\Services",false)) {
     if(services==null) throw new InvalidOperationException("Service registry unavailable");
     foreach(string name in services.GetSubKeyNames()) if(VBoxName(name)) throw new InvalidOperationException("VBox service registry remains");
    }
   }
   foreach(bool devices in new[]{false,true}) {
    var services=devices?ServiceController.GetDevices():ServiceController.GetServices();
    try {foreach(var service in services) if(VBoxName(service.ServiceName)) throw new InvalidOperationException("VBox SCM resource remains");}
    finally {foreach(var service in services) service.Dispose();}
   }
   var processes=Process.GetProcesses();
   try {foreach(var process in processes) {
    string name=process.ProcessName;
    if(VBoxName(name) || name.StartsWith("VirtualBox",StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("VBox process remains");
   }} finally {foreach(var process in processes) process.Dispose();}
   string drivers=Path.Combine(Environment.SystemDirectory,"drivers");
   string inf=Path.Combine(Directory.GetParent(Environment.SystemDirectory).FullName,"INF");
   LockParents(drivers);LockParents(inf);
   if(PayloadExists(Path.Combine(drivers,"VBoxSup.sys")) || PayloadExists(Path.Combine(inf,published)))
    throw new InvalidOperationException("Driver or exact published INF remains");
  }
  static void RequirePayloadController(IntPtr controller,int initiatingPid,string initiatingCreated,TokenFacts caller) {
   if(TokenFacts.WaitForSingleObject(controller,0)!=258) throw new InvalidOperationException("Payload controller exited or is unknown");
   long created;
   if(initiatingPid<1 || !long.TryParse(initiatingCreated,NumberStyles.None,CultureInfo.InvariantCulture,out created) || created<1)
    throw new InvalidOperationException("Invalid initiating cleanup generation");
   if(initiatingPid==caller.Pid) {if(created!=caller.Created) throw new InvalidOperationException("Recycled cleanup controller");}
   else if(!OrphanControllerAbsent(initiatingPid)) throw new InvalidOperationException("Another cleanup owner remains or is unknown");
  }
  static void VerifyPayloadWorker(string session,PayloadCheckpoint checkpoint) {
   if(!Regex.IsMatch(checkpoint.WorkerJournalName??"",@"\Ahelper-(Finish|Recover)-[a-f0-9]{32}\.journal\z",RegexOptions.CultureInvariant))
    throw new InvalidOperationException("Foreign teardown journal path");
   string path=Path.Combine(session,checkpoint.WorkerJournalName);
   using(var guard=OpenPayloadEvidenceGuard(path,ReadProtectedField(Json.Deserialize<Dictionary<string,object>>(checkpoint.OwnerBinding),"sid"))) {
   if(Hash(PayloadReadWorkerJournal(path))!=checkpoint.WorkerJournalSha256) throw new InvalidOperationException("Teardown journal changed");
   var state=DurableJournal.Inspect(path,checkpoint.WorkerJournalBinding);
   var binding=Json.Deserialize<Dictionary<string,object>>(checkpoint.WorkerJournalBinding);
   var owner=Json.Deserialize<Dictionary<string,object>>(checkpoint.OwnerBinding);
   string action=ReadProtectedField(binding,"action");
   if(state.Count!=2 || state.Intent!=action || (action!="Finish" && action!="Recover") ||
      !checkpoint.WorkerJournalName.StartsWith("helper-"+action+"-",StringComparison.Ordinal) ||
      ReadProtectedField(binding,"schema")!="1" || ReadProtectedField(binding,"mode")!=PinnedBuild.Mode ||
      ReadProtectedField(binding,"protected_session")!=session ||
      ReadProtectedField(binding,"portable_root")!=ReadProtectedField(owner,"portable_root") ||
      ReadProtectedField(binding,"sid")!=ReadProtectedField(owner,"sid") ||
      ReadProtectedField(binding,"cycle")!=ReadProtectedField(owner,"cycle") ||
      ReadProtectedField(binding,"frontend_sha256")!=PinnedBuild.FrontendSha256 ||
      ReadProtectedField(binding,"controller_pid")!=checkpoint.InitiatorPid.ToString(CultureInfo.InvariantCulture) ||
      ReadProtectedField(binding,"controller_created_filetime")!=checkpoint.InitiatorCreated)
    throw new InvalidOperationException("Teardown journal owner or outcome mismatch");
   var exit=Json.Deserialize<Dictionary<string,object>>(state.LastPayload);object code,deadline;
   if(!exit.TryGetValue("child_exit",out code) || !(code is int) || (int)code!=0 ||
      !exit.TryGetValue("within_deadline",out deadline) || !(deadline is bool) || !(bool)deadline)
    throw new InvalidOperationException("Teardown child did not commit successful exit");
   }
  }
  static string VerifyPayloadReceipts(string session,PayloadCleanupPlan plan,out string stageHash,out string cleanupHash) {
   byte[] stageBytes=PayloadRead(Path.Combine(session,@"stage\sup-standalone.json"),65536);
   byte[] cleanBytes=PayloadRead(Path.Combine(session,@"cleanup\cleanup-results.json"),65536);
   var stage=Json.Deserialize<Dictionary<string,object>>(PayloadUtf8.GetString(stageBytes).TrimStart('\ufeff'));
   var clean=Json.Deserialize<Dictionary<string,object>>(PayloadUtf8.GetString(cleanBytes).TrimStart('\ufeff'));
   string published=ReadProtectedField(stage,"published_inf");object value;
   foreach(string field in new[]{"cleanup_verified","driver_package_removed"})
    if(!clean.TryGetValue(field,out value) || !(value is bool) || !(bool)value) throw new InvalidOperationException("Teardown receipt not confirmed");
   if(!clean.TryGetValue("errors",out value) || (!(value is ArrayList) && !(value is object[])) || ((ICollection)value).Count!=0 ||
      ReadProtectedField(clean,"published_inf")!=published || ReadProtectedField(stage,"published_inf_schema")!="1" ||
      !stage.TryGetValue("published_inf_was_absent",out value) || !(value is bool) || !(bool)value)
    throw new InvalidOperationException("Teardown acquisition evidence mismatch");
   int found=0;foreach(var entry in plan.Items) if(!entry.Directory && entry.Relative.EndsWith("/VBoxSup.inf",StringComparison.Ordinal)) {
    if(ReadProtectedField(stage,"published_inf_sha256")!=entry.Sha256) throw new InvalidOperationException("Foreign acquired INF hash");found++;
   }
   if(found!=1) throw new InvalidOperationException("Pinned INF identity is not unique");
   stageHash=Hash(stageBytes);cleanupHash=Hash(cleanBytes);return published;
  }
  static void CheckPayloadTree(string session,PayloadCleanupPlan plan) {
   var allowed=new HashSet<string>(StringComparer.Ordinal);
   foreach(var entry in plan.Items) allowed.Add(entry.Relative);
   int count=0;
   foreach(string root in new[]{"app64","code"}) {
    string path=PayloadPath(session,root);if(!PayloadExists(path)) continue;
    CheckPayloadTreeDirectory(session,root,allowed,ref count);
   }
  }
  static void CheckPayloadTreeDirectory(string session,string relative,HashSet<string> allowed,ref int count) {
   string path=PayloadPath(session,relative);
   // Capture verifies directory identity/type/ACL before enumeration in Observe.
   // Here no link is followed, and unknown entries fail before any effect.
   if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new InvalidOperationException("Reparse payload directory");
   foreach(string child in Directory.EnumerateFileSystemEntries(path)) {
    if(++count>512) throw new InvalidOperationException("Unexpected payload tree size");
    string item=relative+"/"+Path.GetFileName(child);
    if(!allowed.Contains(item)) throw new InvalidOperationException("Unexpected payload entry");
    var attributes=File.GetAttributes(child);
    if((attributes&FileAttributes.ReparsePoint)!=0) throw new InvalidOperationException("Reparse payload entry");
    if((attributes&FileAttributes.Directory)!=0) CheckPayloadTreeDirectory(session,item,allowed,ref count);
   }
  }
  static bool[] ObservePayload(string session,string sid,PayloadCleanupPlan plan,string[] identities) {
   if(identities==null || identities.Length!=plan.Items.Count) throw new InvalidOperationException("Payload identity count mismatch");
   var present=new bool[plan.Items.Count];
   // Directories first: retain their ancestry before walking any surviving child.
   for(int pass=0;pass<2;pass++) for(int i=0;i<plan.Items.Count;i++) {
    var entry=plan.Items[i];if(entry.Directory!=(pass==0)) continue;
    string path=PayloadPath(session,entry.Relative);present[i]=PayloadExists(path);
    if(present[i] && CapturePayloadObject(path,sid,entry.Directory,entry.Length,entry.Sha256)!=identities[i])
     throw new InvalidOperationException("Original payload object was replaced");
   }
   CheckPayloadTree(session,plan);return present;
  }
  static void CreatePayloadCheckpoint(string session,string root,TokenFacts caller,int originalPid,int cycle,bool recovery,string helperHash,string workerPath,string workerBinding) {
   string owner=VerifyPayloadOwner(session,root,caller,originalPid,cycle,recovery,helperHash);
   byte[] manifest=PayloadRead(Path.Combine(session,@"app64\.prepared.json"),131072);
   var plan=PayloadPlan(manifest);string stageHash,cleanupHash;
   string published=VerifyPayloadReceipts(session,plan,out stageHash,out cleanupHash);
   AssertNoVBoxResources(published);
   if(PayloadExists(Path.Combine(session,"payload-cleanup.journal")) || PayloadExists(Path.Combine(session,"payload-removed.json")))
    throw new InvalidOperationException("Stale payload cleanup evidence");
   var identities=new string[plan.Items.Count];
   for(int i=0;i<identities.Length;i++) {var entry=plan.Items[i];identities[i]=CapturePayloadObject(PayloadPath(session,entry.Relative),caller.Sid,entry.Directory,entry.Length,entry.Sha256);}
   CheckPayloadTree(session,plan);
   var checkpoint=new PayloadCheckpoint {Schema=1,OwnerBinding=owner,InitiatorPid=caller.Pid,InitiatorCreated=caller.Created.ToString(CultureInfo.InvariantCulture),
    ManifestBase64=Convert.ToBase64String(manifest),PlanSha256=plan.Digest,ObjectIdentities=identities,PublishedInf=published,
    StageSha256=stageHash,CleanupSha256=cleanupHash,WorkerJournalName=Path.GetFileName(workerPath),WorkerJournalBinding=workerBinding,
    WorkerJournalSha256=Hash(PayloadReadWorkerJournal(workerPath))};
   VerifyPayloadWorker(session,checkpoint);
   byte[] bytes=PayloadUtf8.GetBytes(Json.Serialize(checkpoint));
   if(bytes.Length>262144) throw new InvalidOperationException("Payload checkpoint size bound");
   string path=Path.Combine(session,"payload-cleanup.json");WriteNew(path,bytes);
   if(Hash(PayloadRead(path,262144))!=Hash(bytes)) throw new InvalidOperationException("Checkpoint durable readback mismatch");
  }
  static void PayloadBreak(string name) {
   if(PinnedBuild.Mode=="CI" && Environment.GetEnvironmentVariable("PVBOX_TEST_PAYLOAD_BREAK_AT")==name)
    throw new InvalidOperationException("Controlled private payload interruption: "+name);
  }
  static void ContinuePayloadRemoval(string session,string root,TokenFacts caller,IntPtr controller,int originalPid,int cycle,bool recovery,string helperHash) {
   string owner=VerifyPayloadOwner(session,root,caller,originalPid,cycle,recovery,helperHash);
   if(PayloadExists(Path.Combine(session,"payload-removed.json"))) throw new InvalidOperationException("Completed payload removal cannot replay");
   string checkpointPath=Path.Combine(session,"payload-cleanup.json");
   using(var checkpointGuard=OpenPayloadEvidenceGuard(checkpointPath,caller.Sid)) {
    byte[] bytes=PayloadRead(checkpointPath,262144);string text=PayloadUtf8.GetString(bytes);
    var checkpoint=Json.Deserialize<PayloadCheckpoint>(text);
    if(checkpoint==null || checkpoint.Schema!=1 || checkpoint.OwnerBinding!=owner || Json.Serialize(checkpoint)!=text)
     throw new InvalidOperationException("Foreign or noncanonical payload checkpoint");
    RequirePayloadController(controller,checkpoint.InitiatorPid,checkpoint.InitiatorCreated,caller);
    byte[] manifest=Convert.FromBase64String(checkpoint.ManifestBase64);
    if(Convert.ToBase64String(manifest)!=checkpoint.ManifestBase64) throw new InvalidOperationException("Noncanonical manifest preservation");
    var plan=PayloadPlan(manifest);
    if(plan.Digest!=checkpoint.PlanSha256) throw new InvalidOperationException("Payload plan changed");
    string stageHash,cleanupHash;string published=VerifyPayloadReceipts(session,plan,out stageHash,out cleanupHash);
    if(published!=checkpoint.PublishedInf || stageHash!=checkpoint.StageSha256 || cleanupHash!=checkpoint.CleanupSha256)
     throw new InvalidOperationException("Original teardown evidence changed");
    VerifyPayloadWorker(session,checkpoint);AssertNoVBoxResources(published);
    string binding=owner+"\n"+Hash(bytes)+"\n"+plan.Digest;
    string path=Path.Combine(session,"payload-cleanup.journal");
    bool exists=PayloadExists(path);
    bool[] present=ObservePayload(session,caller.Sid,plan,checkpoint.ObjectIdentities);
    if(!exists) {
     foreach(bool entry in present) if(!entry) throw new InvalidOperationException("Missing payload journal cannot reconstruct progress");
     using(var fresh=PayloadCleanupJournal.CreateNew(path,binding,plan.Items.Count)) { }
     var acl=File.GetAccessControl(path);acl.SetOwner(Admins);File.SetAccessControl(path,acl);
    }
    using(var guard=OpenPayloadEvidenceGuard(path,caller.Sid))
    using(var journal=PayloadCleanupJournal.OpenResume(path,binding,plan.Items.Count)) {
     plan.ValidatePresence(journal.State,present);PayloadBreak("BeforeFirst");
     for(int i=journal.State.Completed;i<plan.Items.Count;i++) {
      RequirePayloadController(controller,checkpoint.InitiatorPid,checkpoint.InitiatorCreated,caller);AssertNoVBoxResources(published);
      var entry=plan.Items[i];string target=PayloadPath(session,entry.Relative);
      bool pending=journal.State.Pending;
      if(!PayloadExists(target) && !pending) throw new InvalidOperationException("Unstarted payload object disappeared");
      if(!pending) journal.Begin(i);
      if(i==0) PayloadBreak("AfterFirstIntent");
      if(PayloadExists(target)) {
       ReleasePayloadLock(target);
       DeletePayloadObject(target,caller.Sid,entry.Directory,entry.Length,entry.Sha256,checkpoint.ObjectIdentities[i]);
      }
      // Native disposition is only a request. Closed handle + explicit NOT_FOUND
      // is required; access denied/delete pending/unknown cannot become DONE.
      if(PayloadExists(target)) throw new InvalidOperationException("Payload deletion not observed absent");
      if(i==0) PayloadBreak("AfterFirstDelete");
      journal.Done(i);if(i==0) PayloadBreak("AfterFirstDone");
      if(i+1<plan.Items.Count && !entry.Directory && plan.Items[i+1].Directory) PayloadBreak("AfterFiles");
     }
     plan.ValidatePresence(journal.State,ObservePayload(session,caller.Sid,plan,checkpoint.ObjectIdentities));
     RequirePayloadController(controller,checkpoint.InitiatorPid,checkpoint.InitiatorCreated,caller);AssertNoVBoxResources(published);
     if(!journal.State.Complete) journal.Complete();PayloadBreak("BeforeMarker");
     WriteNew(Path.Combine(session,"payload-removed.json"),PayloadUtf8.GetBytes("{\"protected_payload_removed\":true}"));
    }
   }
  }
 }
}
