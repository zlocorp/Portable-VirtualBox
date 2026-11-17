using System;
using System.IO;
using System.Text;
using System.Reflection;
using System.Threading.Tasks;
namespace PortableVBox {
 public static class SdsDiagnosticFilesTests {
  static void Require(bool ok,string message){if(!ok)throw new Exception(message);}
  // Windows readers must share the already-open writer's access. This is only
  // a read-only fixture observation; production CreateNew/FileShare.Read stays.
  static string ReadObserved(string path){
   using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
   using(var reader=new StreamReader(stream,Encoding.UTF8)){return reader.ReadToEnd();}
  }
  sealed class BadClose : IDisposable {
   internal bool Called;internal readonly Exception Error=new IOException("close");
   public void Dispose(){Called=true;throw Error;}
  }
  sealed class FaultStream : FileStream {
   internal static int CloseFinalizerDisposals;
   internal readonly Exception Fault=new IOException("injected stream fault");internal readonly string Site;internal bool Closed;
   internal FaultStream(string path,string site):base(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read){Site=site;}
   public override void Write(byte[] bytes,int offset,int count){if(Site=="write")throw Fault;base.Write(bytes,offset,count);}
   public override void Flush(bool durable){if(Site=="flush")throw Fault;base.Flush(durable);}
   protected override void Dispose(bool disposing){if(!disposing && Site=="close")System.Threading.Interlocked.Increment(ref CloseFinalizerDisposals);Closed=true;base.Dispose(disposing);if(disposing && Site=="close")throw Fault;}
  }
  static Task<string> Failed(Exception error){var task=new TaskCompletionSource<string>();task.SetException(error);return task.Task;}
  static Exception Caught(Action action){try{action();return null;}catch(Exception e){return e;}}
  static void CompletionCases(string root){
   for(int mode=0;mode<8;mode++){
    string directory=Path.Combine(root,"complete-"+mode);Directory.CreateDirectory(directory);
    var primary=new IOException("stdout capture");var secondary=new IOException("stderr capture");var image=new IOException("image");
    bool outFail=(mode&1)!=0,errFail=(mode&2)!=0,imageFail=(mode&4)!=0,verified=false;
    using(var files=new SdsDiagnosticFiles(directory,"sup-stop")){
     var failure=Caught(()=>SdsEvidenceCompletion.Capture(outFail?Failed(primary):Task.FromResult("out 世界"),errFail?Failed(secondary):Task.FromResult("err Привет"),()=>{verified=true;if(imageFail)throw image;},files.WriteAvailable));
     Require(Object.ReferenceEquals(failure,outFail?primary:errFail?secondary:imageFail?image:null),"first capture/image error preserved");
     Require(verified,"image observation suppressed by capture failure");
     Require(ReadObserved(Path.Combine(directory,"sup-stop.stdout.txt"))==(outFail?"":"out 世界"),"available stdout not preserved");
     Require(ReadObserved(Path.Combine(directory,"sup-stop.stderr.txt"))==(errFail?"":"err Привет"),"available stderr not preserved");
     Require(Caught(()=>files.WriteCompleted("overwrite","overwrite")) is InvalidOperationException,"second completion accepted");
    }
   }
   var original=new IOException("original");var a=new BadClose();var b=new BadClose();
   Require(Object.ReferenceEquals(Caught(()=>SdsEvidenceCompletion.Close(original,a,b)),original)&&a.Called&&b.Called,"cleanup masked original or skipped owner");
   a=new BadClose();b=new BadClose();Require(Object.ReferenceEquals(Caught(()=>SdsEvidenceCompletion.Close(null,a,b)),a.Error)&&b.Called,"first disposal error masked");
   foreach(string site in new[]{"write","flush","close"}){
    string directory=Path.Combine(root,"fault-"+site);Directory.CreateDirectory(directory);
    var files=new SdsDiagnosticFiles(directory,"sup-stop");
    var field=typeof(SdsDiagnosticFiles).GetField("stdout",BindingFlags.NonPublic|BindingFlags.Instance);
    ((FileStream)field.GetValue(files)).Dispose();var injected=new FaultStream(Path.Combine(directory,"injected.txt"),site);field.SetValue(files,injected);
    var failure=Caught(()=>files.WriteCompleted("out","err"));
    Require(site=="close"?failure==null:Object.ReferenceEquals(failure,injected.Fault),"writer fault must preserve exact primary");
    Require(ReadObserved(Path.Combine(directory,"sup-stop.stderr.txt"))=="err","fault suppressed stderr");
    var closeFailure=Caught(()=>files.Dispose());Require(injected.Closed,"injected stream not closed");
    Require(site=="close"?Object.ReferenceEquals(closeFailure,injected.Fault):closeFailure==null,"close result incorrect");
    Require(Caught(()=>files.Dispose())==null,"failed close retried");
    using(var exclusive=File.Open(Path.Combine(directory,"sup-stop.stderr.txt"),FileMode.Open,FileAccess.ReadWrite,FileShare.None)){Require(exclusive.Length==3,"other stream left unclosed");}
   }
   // Real writer, real FileStreams: close one underlying channel before writing.
   foreach(string field in new[]{"stdout","stderr"}){
    string directory=Path.Combine(root,"closed-"+field);Directory.CreateDirectory(directory);
    using(var files=new SdsDiagnosticFiles(directory,"sup-stop")){
     ((FileStream)typeof(SdsDiagnosticFiles).GetField(field,BindingFlags.NonPublic|BindingFlags.Instance).GetValue(files)).Dispose();
     Require(Caught(()=>files.WriteCompleted("out","err")) is ObjectDisposedException,"closed stream did not fail");
     string other=field=="stdout"?"stderr":"stdout";
     Require(ReadObserved(Path.Combine(directory,"sup-stop."+other+".txt"))==(other=="stdout"?"out":"err"),"one failed write suppressed other channel");
    }
   }
  }
  public static int CloseFaultFinalizerDisposals {get{return FaultStream.CloseFinalizerDisposals;}}
  static void CleanupDiagnostic(string message){try{Console.WriteLine(message);}catch{}}
  public static int Main(){
   string root=Path.Combine(Path.GetTempPath(),"pvbox-sds-files-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
   try {
    string stdout=Path.Combine(root,"sds-register.stdout.txt"),stderr=Path.Combine(root,"sds-register.stderr.txt");
    using(var files=new SdsDiagnosticFiles(root,"sds-register")){
     Require(File.Exists(stdout)&&File.Exists(stderr),"Both intent files must precede launch");
     Require(new FileInfo(stdout).Length==0&&new FileInfo(stderr).Length==0,"Intent files must begin empty");
     files.WriteCompleted("Привет 世界\r\nno-final-newline","Ошибка\n");
    }
    Require(ReadObserved(stdout)=="Привет 世界\r\nno-final-newline","Complete decoded stdout changed");
    Require(ReadObserved(stderr)=="Ошибка\n","Complete decoded stderr changed");
    bool refused=false;try{using(var files=new SdsDiagnosticFiles(root,"sds-register")){}}catch(IOException){refused=true;}
    Require(refused&&ReadObserved(stdout)=="Привет 世界\r\nno-final-newline","Existing evidence overwritten");
    File.Delete(stdout);
    refused=false;try{using(var files=new SdsDiagnosticFiles(root,"sds-register")){}}catch(IOException){refused=true;}
    Require(refused&&File.Exists(stdout)&&new FileInfo(stdout).Length==0,"Second create failure removed first intent");
    Require(ReadObserved(stderr)=="Ошибка\n","Second-create failure truncated old stderr");
    foreach(string label in new[]{"pnputil","driver-start","sup-stop","sup-package-remove","sup-service-delete"})
     using(var files=new SdsDiagnosticFiles(root,label)){files.WriteCompleted("full "+label,"error "+label);}
    foreach(string label in new[]{"../escape","arbitrary","pnputil/../bad"}){
     bool unknown=false;try{using(var files=new SdsDiagnosticFiles(root,label)){}}catch(InvalidOperationException){unknown=true;}
     Require(unknown,"Arbitrary evidence label accepted");
    }
    string faultDir=Path.Combine(root,"fault");Directory.CreateDirectory(faultDir);
    using(var files=new SdsDiagnosticFiles(faultDir,"sup-stop")){
     bool failed=false;try{files.WriteCompleted("\ud800","retained error");}catch(EncoderFallbackException){failed=true;}
     Require(failed,"Invalid stdout must fail strictly");
     Require(ReadObserved(Path.Combine(faultDir,"sup-stop.stderr.txt"))=="retained error","stdout failure suppressed valid stderr");
    }
    CompletionCases(root);
    Console.WriteLine("SDS_DIAGNOSTIC_FILES_PASS");return 0;
   }finally{
    CleanupDiagnostic("SDS_DIAGNOSTIC_FILES_CLEANUP_ENTERED");
    Directory.Delete(root,true);
    CleanupDiagnostic("SDS_DIAGNOSTIC_FILES_CLEANUP_COMPLETED");
   }
  }
 }
}
