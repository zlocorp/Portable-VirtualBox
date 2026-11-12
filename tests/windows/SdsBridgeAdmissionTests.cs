// Managed validation of the actual closed facade. No Windows effects are invoked.
using System;
using System.Collections.Generic;
using System.Reflection;
namespace PortableVBox {
 public static class SdsBridgeAdmissionTests {
  static int count;
  static void Assert(bool ok,string message){count++;if(!ok)throw new Exception(message);}
  static readonly BindingFlags Hidden=BindingFlags.NonPublic|BindingFlags.Static;
  static void Deadline(SdsOperation operation,int seconds,bool accepted){
   bool result=true;try{typeof(SdsBridge).GetMethod("ValidateDeadline",Hidden).Invoke(null,new object[]{operation,seconds});}
   catch(TargetInvocationException e){if(!(e.InnerException is InvalidOperationException))throw;result=false;}
   Assert(result==accepted,"Deadline gate "+operation+"/"+seconds);
  }
  public static int Main(){
   Deadline(SdsOperation.Register,30,true);Deadline(SdsOperation.Register,29,false);Deadline(SdsOperation.Register,31,false);
   Deadline(SdsOperation.UnregisterFull,5,true);Deadline(SdsOperation.UnregisterFull,90,true);Deadline(SdsOperation.UnregisterFull,4,false);Deadline(SdsOperation.UnregisterFull,91,false);
   Deadline(SdsOperation.UnregisterPartial,10,true);Deadline(SdsOperation.UnregisterPartial,75,true);Deadline(SdsOperation.UnregisterPartial,9,false);Deadline(SdsOperation.UnregisterPartial,76,false);Deadline((SdsOperation)99,30,false);
   var methods=typeof(SdsBridge).GetMethods(BindingFlags.Public|BindingFlags.Static|BindingFlags.DeclaredOnly);
   Assert(methods.Length==1&&methods[0].Name=="Run","Facade exposes extra entry points");
   var parameters=methods[0].GetParameters();Assert(parameters.Length==2&&parameters[0].ParameterType==typeof(SdsOperation)&&parameters[1].ParameterType==typeof(int),"Facade has execution selector");
   var properties=typeof(SdsResult).GetProperties(BindingFlags.Public|BindingFlags.Instance);
   foreach(var property in properties)Assert(property.GetSetMethod()==null,"Mutable public result");
   var manifest=new Dictionary<string,object>{{"files",new object[0]},{"file_count",185},{"total_bytes",247834716}};
   bool rejected=false;try{typeof(SdsBridge).GetMethod("ValidateManifest",Hidden).Invoke(null,new object[]{manifest});}catch(TargetInvocationException e){rejected=e.InnerException is InvalidOperationException;}
   Assert(rejected,"Empty forged manifest accepted");
   var locator=typeof(SdsBridge).GetMethod("ValidateStoreLocator",Hidden);
   Assert(locator!=null,"Parent store locator validator is absent");
   Func<string,string,string> validate=(path,mode)=>(string)locator.Invoke(null,new object[]{path,mode});
   Assert(validate(@"C:\ProgramData\PortableVirtualBox.Experiment","CI")==@"C:\ProgramData\PortableVirtualBox.Experiment","CI store locator changed");
   Assert(validate(@"D:\Program Data\PortableVirtualBox.Alpha","ALPHA")==@"D:\Program Data\PortableVirtualBox.Alpha","ALPHA store locator changed");
   Assert(validate(@"C:\Данные 世界\PortableVirtualBox.Experiment","CI")==@"C:\Данные 世界\PortableVirtualBox.Experiment","Unicode canonical spelling rejected");
   foreach(string path in new string[]{@"C:\COM¹\PortableVirtualBox.Experiment",@"C:\LPT².txt\PortableVirtualBox.Experiment",@"C:\CONIN$\PortableVirtualBox.Experiment",@"C:\CONOUT$.txt\PortableVirtualBox.Experiment",
    "C:\\bad"+'\u0080'+"name\\PortableVirtualBox.Experiment","C:\\bad"+'\u007f'+"name\\PortableVirtualBox.Experiment","C:\\"+'\u00a0'+"ProgramData\\PortableVirtualBox.Experiment",
    @"C:\PROGRA~3\PortableVirtualBox.Experiment",@"C:\ ProgramData\PortableVirtualBox.Experiment",@"C:\ProgramData\bad"+'\t'+@"name\PortableVirtualBox.Experiment",null,""," ",@"PortableVirtualBox.Experiment",@"C:PortableVirtualBox.Experiment",@"/C:/ProgramData/PortableVirtualBox.Experiment",
    @"\\server\share\PortableVirtualBox.Experiment",@"\\?\C:\ProgramData\PortableVirtualBox.Experiment",@"\\.\C:\ProgramData\PortableVirtualBox.Experiment",
    @"C:/ProgramData/PortableVirtualBox.Experiment",@"C:\ProgramData\\PortableVirtualBox.Experiment",@"C:\ProgramData\.\PortableVirtualBox.Experiment",
    @"C:\ProgramData\..\PortableVirtualBox.Experiment",@"C:\ProgramData\PortableVirtualBox.Experiment\",@"C:\ProgramData\PortableVirtualBox.Experiment.",
    @"C:\ProgramData\PortableVirtualBox.Experiment ",@"C:\ProgramData.\PortableVirtualBox.Experiment",@"C:\ProgramData \PortableVirtualBox.Experiment",
    @"C:\ProgramData\PortableVirtualBox.Experiment:stream",@"C:\ProgramData:stream\PortableVirtualBox.Experiment",@"C:\CON\PortableVirtualBox.Experiment",
    @"C:\NUL.txt\PortableVirtualBox.Experiment",@"C:\COM1\PortableVirtualBox.Experiment",@"C:\LPT9.txt\PortableVirtualBox.Experiment",
    @"C:\ProgramData\PortableVirtualBox.Alpha",@"C:\ProgramData\Other", "C:\\ProgramData\\bad\nname\\PortableVirtualBox.Experiment"}){
    bool refused=false;try{validate(path,"CI");}catch(TargetInvocationException e){refused=e.InnerException is InvalidOperationException;}
    Assert(refused,"Malformed or wrong-mode parent store locator accepted");
   }
   foreach(string mode in new string[]{null,"","ci","unknown"}){
    bool refused=false;try{validate(@"C:\ProgramData\PortableVirtualBox.Experiment",mode);}catch(TargetInvocationException e){refused=e.InnerException is InvalidOperationException;}
    Assert(refused,"Unknown locator build mode accepted");
   }
   var origin=typeof(SdsBridge).GetMethod("OriginFailure",Hidden);
   Assert(origin!=null,"Actual pure origin gate is absent");
   Func<string,string,string,string,string,string,string,string> check=(leaf,code,parent,name,store,expected,current)=>(string)origin.Invoke(null,new object[]{leaf,code,parent,name,store,expected,current});
   string hiddenStore="private-location-not-for-logs";
   Assert(check("PortableVBox.SdsBridge.dll","code",hiddenStore,"pvbox-manager-5276-41",hiddenStore,"CI","CI")==null,"Valid measured session layout refused");
   Assert(check("portablevbox.sdsbridge.DLL","CODE",hiddenStore.ToUpperInvariant(),"pvbox-manager-1-1",hiddenStore,"ALPHA","ALPHA")==null,"Existing case-insensitive comparisons changed");
   string[] failures={
    check("secret-wrong-image.dll","code",hiddenStore,"pvbox-manager-5276-41",hiddenStore,"CI","CI"),
    check("PortableVBox.SdsBridge.dll","secret-wrong-directory",hiddenStore,"pvbox-manager-5276-41",hiddenStore,"CI","CI"),
    check("PortableVBox.SdsBridge.dll","code","other-private-location","pvbox-manager-5276-41",hiddenStore,"CI","CI"),
    check("PortableVBox.SdsBridge.dll","code",hiddenStore,"private-invalid-session",hiddenStore,"CI","CI")};
   string[] predicates={"leaf_match=false","code_match=false","store_parent_match=false","session_name_match=false"};
   for(int i=0;i<failures.Length;i++){
    Assert(failures[i]!=null&&failures[i].Contains(predicates[i]),"Wrong origin rejection predicate");
    Assert(!failures[i].Contains("private")&&!failures[i].Contains("secret")&&!failures[i].Contains("5276"),"Origin diagnostic leaked input text");
    Assert(failures[i].Contains("expected_mode=CI;current_mode=CI"),"Bounded mode tokens missing");
   }
   foreach(string invalid in new[]{"pvbox-manager-0-41","pvbox-manager-5276-0","pvbox-manager-01-1","prefix-pvbox-manager-5276-41","pvbox-manager-5276-41-tail","pvbox-manager-5276-41\\n"})
    Assert(check("PortableVBox.SdsBridge.dll","code",hiddenStore,invalid,hiddenStore,"CI","CI")!=null,"Session-name regex literal changed");
   string tokens=check("invalid","code",hiddenStore,"pvbox-manager-5276-41",hiddenStore,"secret-mode",null);
   Assert(tokens.Contains("expected_mode=unknown;current_mode=missing")&&!tokens.Contains("secret"),"Unbounded mode diagnostic");
   Console.WriteLine("SDS_BRIDGE_ADMISSION_PASS assertions="+count);return 0;
  }
 }
}
