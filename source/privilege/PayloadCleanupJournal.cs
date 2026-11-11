// Bounded evidence for a fixed private-payload plan only. NOT service/driver
// retry authority. Caller independently verifies protected ACL/owner, fixed
// plan, non-reparse paths and live-state safety before any effect. Hashes detect
// damage, not an untrusted producer. Never repair, truncate or rewrite evidence.
using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
namespace PortableVBox {
 internal sealed class PayloadJournalState {
  public int StepCount {get; private set;}
  public int Completed {get; private set;}
  public bool Pending {get; private set;}
  public bool Complete {get; private set;}
  public string LastHash {get; private set;}
  internal PayloadJournalState(int steps,int completed,bool pending,bool complete,string hash) {
   StepCount=steps;Completed=completed;Pending=pending;Complete=complete;LastHash=hash;
  }
 }
 internal sealed class PayloadCleanupJournal : IDisposable {
  const int MaxFile=262144;
  static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
  readonly FileStream file;
  readonly string header;
  readonly int steps;
  PayloadJournalState state;
  bool disposed,uncertain;
  public PayloadJournalState State {get {return state;}}
  // Private disk-handle constructor: no alternate public writer or repair path.
  PayloadCleanupJournal(FileStream file,string header,int steps) {
   this.file=file;this.header=header;this.steps=steps;
   // A prior failed flush can leave a complete frame in cache. Re-establish
   // durability on this retained handle before publishing resumable authority.
   PayloadJournalState before=ReadState(file,header,steps);
   file.Flush(true);
   PayloadJournalState after=ReadState(file,header,steps);
   if(before.StepCount!=after.StepCount || before.Completed!=after.Completed ||
      before.Pending!=after.Pending || before.Complete!=after.Complete || before.LastHash!=after.LastHash)
    throw new InvalidDataException("Resume durability verification mismatch");
   state=after;
  }
  static string Number(int n) {return n.ToString(CultureInfo.InvariantCulture);}
  static string Header(string binding,int steps) {
   if(steps<1 || steps>512) throw new ArgumentOutOfRangeException("steps");
   if(String.IsNullOrEmpty(binding) || binding.Length>4096) throw new ArgumentException("Invalid binding");
   byte[] bytes=Utf8.GetBytes(binding);
   if(bytes.Length>4096) throw new ArgumentException("Binding exceeds UTF-8 bound");
   return "PVBC1\t"+Number(steps)+"\t"+Convert.ToBase64String(bytes)+"\n";
  }
  static string Digest(byte[] bytes) {
   using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
  }
  static string Record(int sequence,int steps,string previous,out string digest) {
   string kind=sequence==steps*2?"COMPLETE":sequence%2==0?"BEGIN":"DONE";
   string prefix=Number(sequence)+"\t"+kind+"\t"+Number(sequence/2)+"\t"+previous;
   digest=Digest(Utf8.GetBytes(prefix));return prefix+"\t"+digest+"\n";
  }
  static PayloadJournalState ReadState(FileStream file,string header,int steps) {
   long length=file.Length;
   if(length<1 || length>MaxFile) throw new InvalidDataException("Journal size bound");
   file.Position=0;byte[] bytes=new byte[(int)length];int offset=0;
   while(offset<bytes.Length) {
    int got=file.Read(bytes,offset,bytes.Length-offset);
    if(got==0) throw new InvalidDataException("Truncated journal read");offset+=got;
   }
   if(file.Length!=length || file.ReadByte()!=-1) throw new InvalidDataException("Journal changed during read");
   string text;
   try {text=Utf8.GetString(bytes);} catch(DecoderFallbackException) {throw new InvalidDataException("Malformed UTF-8 journal");}
   if(!text.StartsWith(header,StringComparison.Ordinal) || !text.EndsWith("\n",StringComparison.Ordinal))
    throw new InvalidDataException("Header binding/count/version or partial tail mismatch");
   string[] lines=text.Substring(header.Length).Split('\n');
   int events=lines.Length-1;
   if(events>steps*2+1 || lines[events]!="") throw new InvalidDataException("Journal event bound");
   string previous=Digest(Utf8.GetBytes(header));
   for(int i=0;i<events;i++) {
    string next;
    if(lines[i]+"\n"!=Record(i,steps,previous,out next)) throw new InvalidDataException("Noncanonical journal event, sequence or chain");
    previous=next;
   }
   return new PayloadJournalState(steps,Math.Min(events/2,steps),events<steps*2 && events%2==1,events==steps*2+1,previous);
  }
  internal static PayloadCleanupJournal CreateNew(string path,string binding,int steps) {
   string header=Header(binding,steps);
   var file=new FileStream(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.Read);
   try {
    byte[] bytes=Utf8.GetBytes(header);file.Write(bytes,0,bytes.Length);file.Flush(true);
    return new PayloadCleanupJournal(file,header,steps);
   } catch {file.Dispose();throw;}
  }
  internal static PayloadCleanupJournal OpenResume(string path,string binding,int steps) {
   string header=Header(binding,steps);
   var file=new FileStream(path,FileMode.Open,FileAccess.ReadWrite,FileShare.Read);
   try {return new PayloadCleanupJournal(file,header,steps);} catch {file.Dispose();throw;}
  }
  internal static PayloadJournalState Inspect(string path,string binding,int steps) {
   string header=Header(binding,steps);
   // Inspect is a snapshot, not retained write authority. ShareWrite allows
   // observing the retained writer; an incomplete append fails closed.
   using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) return ReadState(file,header,steps);
  }
  void EnsureWriter() {
   if(disposed || uncertain) throw new InvalidOperationException("Closed or uncertain journal writer");
  }
  internal void Begin(int index) {
   EnsureWriter();
   if(state.Complete || state.Pending || index!=state.Completed || index>=steps) throw new InvalidOperationException("Out-of-order BEGIN");
   Append(index*2);
  }
  internal void Done(int index) {
   EnsureWriter();
   if(state.Complete || !state.Pending || index!=state.Completed) throw new InvalidOperationException("Out-of-order DONE");
   Append(index*2+1);
  }
  internal void Complete() {
   EnsureWriter();
   if(state.Complete || state.Pending || state.Completed!=steps) throw new InvalidOperationException("Out-of-order COMPLETE");
   Append(steps*2);
  }
  void Append(int sequence) {
   // Set before ANY disk operation: a failed read/write/flush/verification
   // permanently disables this writer. Only a fully verified append publishes
   // the next immutable snapshot. No same-instance retries after uncertainty.
   uncertain=true;
   PayloadJournalState before=ReadState(file,header,steps);
   if(before.LastHash!=state.LastHash) throw new InvalidDataException("Journal changed since validation");
   string next;byte[] bytes=Utf8.GetBytes(Record(sequence,steps,state.LastHash,out next));
   if(file.Length+bytes.Length>MaxFile) throw new InvalidDataException("Journal size bound");
   file.Position=file.Length;file.Write(bytes,0,bytes.Length);file.Flush(true);
   PayloadJournalState after=ReadState(file,header,steps);
   if(after.LastHash!=next) throw new InvalidDataException("Persisted append mismatch");
   state=after;uncertain=false;
  }
  public void Dispose() {
   if(disposed) return;disposed=true;file.Dispose();
  }
 }
}
