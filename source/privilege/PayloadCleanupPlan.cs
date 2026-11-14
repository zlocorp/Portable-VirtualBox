// Pure fixed-plan model only: no filesystem access or mutation authority.
// Presence is supplied only AFTER the caller independently verifies exact
// object identity, type, ACL, non-reparse ancestry, size and hash. A digest
// detects plan changes; it neither authenticates its producer nor grants ownership.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
namespace PortableVBox {
 internal sealed class PayloadCleanupEntry {
  public string Relative {get; private set;}
  public bool Directory {get; private set;}
  public long Length {get; private set;}
  public string Sha256 {get; private set;}
  public PayloadCleanupEntry(string relative,long length,string sha256) {
   Relative=relative;Length=length;Sha256=sha256;
  }
  private PayloadCleanupEntry(string relative) {Relative=relative;Directory=true;Length=0;Sha256=null;}
  internal static PayloadCleanupEntry Parent(string relative) {return new PayloadCleanupEntry(relative);}
 }
 internal sealed class PayloadCleanupPlan {
  const int MaxObjects=512;
  static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
  readonly IList<PayloadCleanupEntry> items;
  readonly string digest;
  public IList<PayloadCleanupEntry> Items {get {return items;}}
  public string Digest {get {return digest;}}
  internal PayloadCleanupPlan(IEnumerable<PayloadCleanupEntry> files) {
   if(files==null) throw new ArgumentNullException("files");
   var ordered=new List<PayloadCleanupEntry>();
   var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   var parents=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   bool app=false,code=false;
   foreach(var entry in files) {
    if(entry==null || entry.Directory) throw new ArgumentException("Only files may seed a plan");
    ValidatePath(entry.Relative);
    if(entry.Length<0 || entry.Length>536870912L || !IsHash(entry.Sha256)) throw new ArgumentException("Invalid file identity");
    if(!names.Add(entry.Relative)) throw new ArgumentException("Duplicate file path");
    ordered.Add(entry);
    if(ordered.Count>MaxObjects) throw new ArgumentException("Plan object bound");
    app|=entry.Relative.StartsWith("app64/",StringComparison.Ordinal);
    code|=entry.Relative.StartsWith("code/",StringComparison.Ordinal);
    string path=entry.Relative;
    int slash;
    while((slash=path.LastIndexOf('/'))>=0) {
     path=path.Substring(0,slash);string prior;
     if(parents.TryGetValue(path,out prior)) {
      // A Windows directory must have a single canonical spelling, independent
      // of input enumeration order; reject ambiguous case aliases.
      if(prior!=path) throw new ArgumentException("Directory case alias");
     } else parents.Add(path,path);
     if(parents.Count+ordered.Count>MaxObjects) throw new ArgumentException("Plan object bound");
    }
   }
   if(!app || !code) throw new ArgumentException("Both payload roots are required");
   foreach(string parent in parents.Keys) if(names.Contains(parent)) throw new ArgumentException("File and directory collision");
   ordered.Sort((a,b)=>StringComparer.Ordinal.Compare(a.Relative,b.Relative));
   var dirs=new List<string>(parents.Keys);
   dirs.Sort((a,b)=>{int depth=Depth(b).CompareTo(Depth(a));return depth!=0?depth:StringComparer.Ordinal.Compare(a,b);});
   foreach(string dir in dirs) ordered.Add(PayloadCleanupEntry.Parent(dir));
   items=ordered.AsReadOnly();
   var canonical=new StringBuilder();
   foreach(var entry in items) {
    canonical.Append(entry.Directory?"D\t":"F\t").Append(entry.Relative);
    if(!entry.Directory) canonical.Append('\t').Append(entry.Length.ToString(CultureInfo.InvariantCulture)).Append('\t').Append(entry.Sha256);
    canonical.Append('\n');
   }
   using(var hash=SHA256.Create()) digest=BitConverter.ToString(hash.ComputeHash(Utf8.GetBytes(canonical.ToString()))).Replace("-","").ToLowerInvariant();
  }
  static int Depth(string path) {int depth=0;foreach(char c in path) if(c=='/') depth++;return depth;}
  static bool IsHash(string hash) {
   if(hash==null || hash.Length!=64) return false;
   foreach(char c in hash) if(!((c>='0' && c<='9') || (c>='a' && c<='f'))) return false;
   return true;
  }
  static void ValidatePath(string path) {
   if(String.IsNullOrEmpty(path) || path.Length>240 || !(path.StartsWith("app64/",StringComparison.Ordinal) || path.StartsWith("code/",StringComparison.Ordinal))) throw new ArgumentException("Invalid payload path");
   foreach(char c in path) if(Char.IsControl(c) || c=='\\' || c==':' || c=='*' || c=='?' || c=='"' || c=='<' || c=='>' || c=='|') throw new ArgumentException("Invalid path character");
   try {Utf8.GetByteCount(path);} catch(EncoderFallbackException) {throw new ArgumentException("Malformed Unicode path");}
   foreach(string part in path.Split('/')) {
    if(part.Length==0 || part=="." || part==".." || part.EndsWith(".",StringComparison.Ordinal) || part.EndsWith(" ",StringComparison.Ordinal)) throw new ArgumentException("Invalid path segment");
    string stem=part.Split('.')[0].ToUpperInvariant();
    if(stem=="CON" || stem=="PRN" || stem=="AUX" || stem=="NUL" || (stem.Length==4 && (stem.StartsWith("COM",StringComparison.Ordinal) || stem.StartsWith("LPT",StringComparison.Ordinal)) && ((stem[3]>='1' && stem[3]<='9') || stem[3]=='\u00b9' || stem[3]=='\u00b2' || stem[3]=='\u00b3'))) throw new ArgumentException("Reserved Windows path");
   }
  }
  internal void ValidatePresence(PayloadJournalState state,IList<bool> present) {
   if(state==null || present==null) throw new ArgumentNullException("state/present");
   if(state.StepCount!=items.Count || present.Count!=items.Count || state.Completed<0 || state.Completed>items.Count || !IsHash(state.LastHash) || (state.Pending && state.Completed==items.Count) || (state.Complete && (state.Pending || state.Completed!=items.Count))) throw new InvalidDataException("Invalid plan progress snapshot");
   // No inference of progress from missing objects. Only the journal's current
   // pending item may be absent without a durable DONE record.
   for(int i=0;i<items.Count;i++) {
    if(i<state.Completed) {if(present[i]) throw new InvalidDataException("Completed object reappeared");}
    else if(!(state.Pending && i==state.Completed) && !present[i]) throw new InvalidDataException("Unstarted object is missing");
   }
  }
 }
}
