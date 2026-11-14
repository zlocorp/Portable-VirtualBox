using System;
using System.IO;
using System.Text;
namespace PortableVBox {
 public static class SdsDiagnosticFilesTests {
  static void Require(bool ok,string message){if(!ok)throw new Exception(message);}
  public static int Main(){
   string root=Path.Combine(Path.GetTempPath(),"pvbox-sds-files-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
   try {
    string stdout=Path.Combine(root,"sds-register.stdout.txt"),stderr=Path.Combine(root,"sds-register.stderr.txt");
    using(var files=new SdsDiagnosticFiles(root,"sds-register")){
     Require(File.Exists(stdout)&&File.Exists(stderr),"Both intent files must precede launch");
     Require(new FileInfo(stdout).Length==0&&new FileInfo(stderr).Length==0,"Intent files must begin empty");
     files.WriteCompleted("Привет 世界\r\nno-final-newline","Ошибка\n");
    }
    Require(File.ReadAllText(stdout,Encoding.UTF8)=="Привет 世界\r\nno-final-newline","Complete decoded stdout changed");
    Require(File.ReadAllText(stderr,Encoding.UTF8)=="Ошибка\n","Complete decoded stderr changed");
    bool refused=false;try{using(var files=new SdsDiagnosticFiles(root,"sds-register")){}}catch(IOException){refused=true;}
    Require(refused&&File.ReadAllText(stdout,Encoding.UTF8)=="Привет 世界\r\nno-final-newline","Existing evidence overwritten");
    File.Delete(stdout);
    refused=false;try{using(var files=new SdsDiagnosticFiles(root,"sds-register")){}}catch(IOException){refused=true;}
    Require(refused&&File.Exists(stdout)&&new FileInfo(stdout).Length==0,"Second create failure removed first intent");
    Require(File.ReadAllText(stderr,Encoding.UTF8)=="Ошибка\n","Second-create failure truncated old stderr");
    foreach(string label in new[]{"pnputil","driver-start","sup-stop","sup-package-remove","sup-service-delete"})
     using(var files=new SdsDiagnosticFiles(root,label)){files.WriteCompleted("full "+label,"error "+label);}
    foreach(string label in new[]{"../escape","arbitrary","pnputil/../bad"}){
     bool unknown=false;try{using(var files=new SdsDiagnosticFiles(root,label)){}}catch(InvalidOperationException){unknown=true;}
     Require(unknown,"Arbitrary evidence label accepted");
    }
    Console.WriteLine("SDS_DIAGNOSTIC_FILES_PASS");return 0;
   }finally{Directory.Delete(root,true);}
  }
 }
}
