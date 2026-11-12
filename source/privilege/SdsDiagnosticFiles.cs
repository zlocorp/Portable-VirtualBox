using System;
using System.IO;
using System.Text;
namespace PortableVBox {
 // Content is diagnostic; file EXISTENCE conservatively blocks ambiguous recovery.
 // Never remove, replace or truncate these files, including on partial acquisition.
 internal sealed class SdsDiagnosticFiles : IDisposable {
  FileStream stdout,stderr;
  bool written;
  internal SdsDiagnosticFiles(string directory,string label) {
   if(label!="sds-register"&&label!="sds-unregister")throw new InvalidOperationException("Unknown SDS evidence label");
   try {
    stdout=new FileStream(Path.Combine(directory,label+".stdout.txt"),FileMode.CreateNew,FileAccess.Write,FileShare.Read);
    stdout.Flush(true);
    stderr=new FileStream(Path.Combine(directory,label+".stderr.txt"),FileMode.CreateNew,FileAccess.Write,FileShare.Read);
    stderr.Flush(true);
   }catch{Dispose();throw;}
  }
  internal void WriteCompleted(string output,string errors) {
   if(written||stdout==null||stderr==null)throw new InvalidOperationException("SDS diagnostics already consumed");
   written=true;
   // Deliberate migration from Start-Process's line writer: complete decoded
   // strings in UTF-8, no newline normalization. No byte-equivalence claim.
   // Interrupted workers retain empty intent files, not partial streamed output.
   byte[] outBytes=new UTF8Encoding(false,true).GetBytes(output);
   byte[] errBytes=new UTF8Encoding(false,true).GetBytes(errors);
   stdout.Write(outBytes,0,outBytes.Length);stdout.Flush(true);
   stderr.Write(errBytes,0,errBytes.Length);stderr.Flush(true);
  }
  public void Dispose(){
   try{if(stdout!=null){stdout.Dispose();stdout=null;}}
   finally{if(stderr!=null){stderr.Dispose();stderr=null;}}
  }
 }
}
