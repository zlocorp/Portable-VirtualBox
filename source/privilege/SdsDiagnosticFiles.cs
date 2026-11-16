using System;
using System.IO;
using System.Text;
using System.Runtime.ExceptionServices;
using System.Threading.Tasks;
namespace PortableVBox {
 // Content is diagnostic; file EXISTENCE conservatively blocks ambiguous recovery.
 // Never remove, replace or truncate these files, including on partial acquisition.
 internal sealed class SdsDiagnosticFiles : IDisposable {
  FileStream stdout,stderr;
  bool written;
  internal SdsDiagnosticFiles(string directory,string label) {
   if(label!="sds-register"&&label!="sds-unregister"&&label!="pnputil"&&label!="driver-start"&&label!="sup-stop"&&label!="sup-package-remove"&&label!="sup-service-delete")throw new InvalidOperationException("Unknown SDS evidence label");
   try {
    stdout=new FileStream(Path.Combine(directory,label+".stdout.txt"),FileMode.CreateNew,FileAccess.Write,FileShare.Read);
    stdout.Flush(true);
    stderr=new FileStream(Path.Combine(directory,label+".stderr.txt"),FileMode.CreateNew,FileAccess.Write,FileShare.Read);
    stderr.Flush(true);
   }catch(Exception error){SdsEvidenceCompletion.Close(error,this);throw;}
  }
  internal void WriteCompleted(string output,string errors) { WriteAvailable(output,true,errors,true); }
  internal void WriteAvailable(string output,bool outputReady,string errors,bool errorsReady) {
   if(written||stdout==null||stderr==null)throw new InvalidOperationException("SDS diagnostics already consumed");
   written=true;
   // Each complete decoded stream is independent. A failed encoding/write/flush
   // never prevents the other available stream being attempted. No reopening.
   Exception failure=null;
   if(outputReady)try{Write(stdout,output);}catch(Exception error){failure=error;}
   if(errorsReady)try{Write(stderr,errors);}catch(Exception error){if(failure==null)failure=error;}
   if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
  }
  static void Write(Stream stream,string value){
   byte[] bytes=new UTF8Encoding(false,true).GetBytes(value);
   stream.Write(bytes,0,bytes.Length);((FileStream)stream).Flush(true);
  }
  public void Dispose(){
   // Consume references before close: even a failed close cannot be retried by
   // an enclosing cleanup path or overwrite the original completion exception.
   var output=stdout;var errors=stderr;stdout=null;stderr=null;
   SdsEvidenceCompletion.Close(null,output,errors);
  }
 }
 // Internal fixed call sites only. Evidence never authorizes another effect.
 internal static class SdsEvidenceCompletion {
  internal static void Capture(Task<string> stdout,Task<string> stderr,Action verifyImage,
   Action<string,bool,string,bool> persist){
   Exception failure=null;string output=null,errors=null;bool outputReady=false,errorsReady=false;
   try{output=stdout.GetAwaiter().GetResult();outputReady=true;}catch(Exception error){failure=error;}
   try{errors=stderr.GetAwaiter().GetResult();errorsReady=true;}catch(Exception error){if(failure==null)failure=error;}
   try{verifyImage();}catch(Exception error){if(failure==null)failure=error;}
   try{persist(output,outputReady,errors,errorsReady);}catch(Exception error){if(failure==null)failure=error;}
   if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
  }
  internal static void Close(Exception failure,params IDisposable[] owners){
   foreach(var owner in owners)if(owner!=null)try{owner.Dispose();}catch(Exception error){if(failure==null)failure=error;}
   if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
  }
 }
}
