// Durable evidence for the fixed helper, NOT permission to replay an effect.
// The caller must establish a protected, non-reparse directory and verified
// owner binding first. Hashes detect damaged framing; they do not authenticate
// an untrusted producer. There is deliberately no repair or resume-write API.
using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
namespace PortableVBox {
    internal sealed class JournalInspection {
        public int Count { get; private set; }
        public bool Complete { get { return Count==3; } }
        public string Intent { get; private set; }
        public string LastPayload { get; private set; }
        internal JournalInspection(int count,string intent,string last) {Count=count;Intent=intent;LastPayload=last;}
    }
    internal sealed class DurableJournal : IDisposable {
        const int MaxBinding=4096,MaxPayload=8192,MaxFile=65536;
        static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
        static readonly string[] Kinds={"INTENT","WORKER_EXIT","HELPER_COMPLETE"};
        readonly FileStream file;
        string previous;
        int count;
        bool disposed,uncertain;
        DurableJournal(FileStream file,string previous) {this.file=file;this.previous=previous;}
        static byte[] Text(string value,int limit) {
            if(String.IsNullOrEmpty(value)) throw new ArgumentException("Empty journal field");
            // Bound before allocation as well as after UTF-8 encoding.
            if(value.Length>limit) throw new ArgumentException("Journal field too large");
            byte[] bytes=Utf8.GetBytes(value);
            if(bytes.Length>limit) throw new ArgumentException("Journal field too large");
            return bytes;
        }
        static string Digest(byte[] bytes) {
            using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
        }
        static bool IntentAllowed(string intent) {return intent=="Prepare" || intent=="Finish" || intent=="Recover";}
        static string Header(string binding) {return "PVBJ1\t"+Convert.ToBase64String(Text(binding,MaxBinding))+"\n";}
        static string Decode(string encoded,int bound) {
            byte[] bytes;
            try {bytes=Convert.FromBase64String(encoded);}
            catch(FormatException) {throw new InvalidDataException("Malformed journal base64");}
            if(bytes.Length==0 || bytes.Length>bound || Convert.ToBase64String(bytes)!=encoded)
                throw new InvalidDataException("Noncanonical journal field");
            try {return Utf8.GetString(bytes);}
            catch(DecoderFallbackException) {throw new InvalidDataException("Malformed journal UTF-8");}
        }
        internal static DurableJournal CreateNew(string path,string binding,string intent) {
            if(!IntentAllowed(intent)) throw new ArgumentException("Unknown fixed helper action");
            string header=Header(binding);
            // CreateNew refuses an existing file, including a link. The caller
            // retains its protected parent handles; this primitive accepts no
            // user-selected path from the helper command line.
            var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read);
            var journal=new DurableJournal(file,Digest(Utf8.GetBytes(header)));
            try {
                byte[] bytes=Utf8.GetBytes(header);file.Write(bytes,0,bytes.Length);
                journal.Append(0,intent); // flushes header + intent before return
                return journal;
            } catch {journal.Dispose();throw;}
        }
        void Append(int expected,string payload) {
            if(disposed || uncertain) throw new InvalidOperationException("Closed or uncertain journal writer");
            if(count!=expected || count>=Kinds.Length) throw new InvalidOperationException("Out-of-order journal event");
            string prefix=count.ToString(CultureInfo.InvariantCulture)+"\t"+Kinds[count]+"\t"+
                Convert.ToBase64String(Text(payload,MaxPayload))+"\t"+previous;
            string digest=Digest(Utf8.GetBytes(prefix));
            byte[] bytes=Utf8.GetBytes(prefix+"\t"+digest+"\n");
            if(file.Length+bytes.Length>MaxFile) throw new InvalidOperationException("Journal size bound");
            // A partial write or failed flush makes this instance unusable.
            // Preserve bytes for inspection; never infer success or truncate.
            uncertain=true;
            file.Write(bytes,0,bytes.Length);
            file.Flush(true);
            previous=digest;++count;uncertain=false;
        }
        internal void WorkerExited(string evidence) {Append(1,evidence);}
        internal void Complete(string evidence) {Append(2,evidence);}
        internal static JournalInspection Inspect(string path,string expectedBinding) {
            string expectedHeader=Header(expectedBinding);
            byte[] bytes;
            // ShareWrite permits inspection while the original exclusive writer
            // is retained. That writer still denies OTHER writers/deletion. A
            // concurrent incomplete append can only fail closed, never resume.
            using(var reader=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
                long length=reader.Length;
                if(length<1 || length>MaxFile) throw new InvalidDataException("Journal size bound");
                bytes=new byte[(int)length];int offset=0;
                while(offset<bytes.Length) {
                    int got=reader.Read(bytes,offset,bytes.Length-offset);
                    if(got==0) throw new InvalidDataException("Journal truncated during read");
                    offset+=got;
                }
                if(reader.Length!=length || reader.ReadByte()!=-1) throw new InvalidDataException("Journal changed during read");
            }
            string text;
            try {text=Utf8.GetString(bytes);}
            catch(DecoderFallbackException) {throw new InvalidDataException("Malformed journal UTF-8");}
            if(!text.EndsWith("\n",StringComparison.Ordinal)) throw new InvalidDataException("Uncommitted journal tail");
            string[] lines=text.Split('\n');
            if(lines.Length<3 || lines.Length>5 || lines[lines.Length-1]!="" || lines[0]+"\n"!=expectedHeader)
                throw new InvalidDataException("Journal framing or owner binding mismatch");
            string previous=Digest(Utf8.GetBytes(expectedHeader)),intent="",last="";
            int count=lines.Length-2;
            for(int i=0;i<count;i++) {
                string[] fields=lines[i+1].Split('\t');
                if(fields.Length!=5 || fields[0]!=i.ToString(CultureInfo.InvariantCulture) ||
                   fields[1]!=Kinds[i] || fields[3]!=previous)
                    throw new InvalidDataException("Journal sequence or chain mismatch");
                string prefix=String.Join("\t",fields,0,4);
                if(fields[4]!=Digest(Utf8.GetBytes(prefix))) throw new InvalidDataException("Journal digest mismatch");
                last=Decode(fields[2],MaxPayload);previous=fields[4];
                if(i==0) {intent=last;if(!IntentAllowed(intent)) throw new InvalidDataException("Unknown fixed helper intent");}
            }
            return new JournalInspection(count,intent,last);
        }
        public void Dispose() {
            if(disposed) return;
            disposed=true;file.Dispose();
        }
    }
}
