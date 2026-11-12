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
   Assert(methods.Length==1&&methods[0].Name=="Open","Facade exposes extra entry points");
   var parameters=methods[0].GetParameters();Assert(parameters.Length==1&&parameters[0].ParameterType==typeof(EffectPurpose),"Facade has execution selector");
   Assert(typeof(FixedEffectContext).GetConstructors(BindingFlags.Public|BindingFlags.Instance).Length==0,"Public context constructor");
   var contextMethods=typeof(FixedEffectContext).GetMethods(BindingFlags.Public|BindingFlags.Instance|BindingFlags.DeclaredOnly);
   Assert(contextMethods.Length==2,"Unexpected context operation surface");
   var driverGate=typeof(SdsBridge).GetMethod("ValidateDriver",Hidden);
   Assert(driverGate!=null,"Missing purpose-bound driver policy");
   foreach(EffectPurpose purpose in Enum.GetValues(typeof(EffectPurpose)))
    foreach(DriverOperation operation in Enum.GetValues(typeof(DriverOperation)))
     foreach(int seconds in new[]{4,5,9,10,14,15,30,60,61,75,76,90,91,120,121}){
      bool expected=purpose==EffectPurpose.Preparation?
       (operation==DriverOperation.AddSupPackage&&seconds>=15&&seconds<=120)||(operation==DriverOperation.StartSup&&seconds>=5&&seconds<=60):
       ((operation==DriverOperation.StopSup||operation==DriverOperation.RemoveSupPackage||operation==DriverOperation.DeleteSupService)&&seconds>=(purpose==EffectPurpose.FullCleanup?5:10)&&seconds<=(purpose==EffectPurpose.FullCleanup?90:75));
      bool accepted=true;try{driverGate.Invoke(null,new object[]{purpose,operation,seconds});}catch(TargetInvocationException e){if(!(e.InnerException is InvalidOperationException))throw;accepted=false;}
      Assert(accepted==expected,"Driver purpose/deadline matrix changed");
     }
   var ledger=new SdsBridge.AttemptLedger();
   ledger.Begin(0);var measuredFailure=new SdsResult(true,true,5,123);ledger.Observe(measuredFailure);
   Assert(measuredFailure.WithinDeadline&&measuredFailure.ExitCodeKnown&&measuredFailure.ExitCode==5&&measuredFailure.ElapsedMs==123,"Measured EXITED/nonzero result changed");
   bool nonzero=false;try{ledger.Begin(1);}catch(InvalidOperationException){nonzero=true;}
   Assert(nonzero,"Measured nonzero did not latch a subsequent distinct operation");
   // A later separately authorized recovery context has independent attempt state.
   var recovery=new SdsBridge.AttemptLedger();bool recoveryAllowed=true;
   try{recovery.Begin(2);recovery.Observe(new SdsResult(true,true,0,0));recovery.Begin(3);}catch(InvalidOperationException){recoveryAllowed=false;}
   Assert(recoveryAllowed,"Failed context contaminated separate recovery ledger");
   ledger=new SdsBridge.AttemptLedger();ledger.Begin(0);ledger.Observe(new SdsResult(true,true,0,0));ledger.Begin(1);
   bool repeated=false;try{ledger.Begin(0);}catch(InvalidOperationException){repeated=true;}
   Assert(repeated,"Operation retry allowed");
   ledger=new SdsBridge.AttemptLedger();ledger.Begin(0);ledger.Observe(new SdsResult(false,true,0,1));
   bool late=false;try{ledger.Begin(1);}catch(InvalidOperationException){late=true;}Assert(late,"Late child did not latch context");
   ledger=new SdsBridge.AttemptLedger();ledger.Fail();
   bool fault=false;try{ledger.Begin(0);}catch(InvalidOperationException){fault=true;}Assert(fault,"Exception did not latch context");
   ledger=new SdsBridge.AttemptLedger();ledger.Begin(2);ledger.Observe(new SdsResult(true,false,0,0));
   bool unknown=false;try{ledger.Begin(3);}catch(InvalidOperationException){unknown=true;}Assert(unknown,"Unknown exit did not latch context");
   foreach(object[] values in new[]{new object[]{(EffectPurpose)99,DriverOperation.StopSup,30},new object[]{EffectPurpose.FullCleanup,(DriverOperation)99,30}}){
    bool invalid=false;try{driverGate.Invoke(null,values);}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Unknown driver purpose/operation allowed");
   }
   var sdsGate=typeof(SdsBridge).GetMethod("ValidateSds",Hidden);
   foreach(EffectPurpose purpose in Enum.GetValues(typeof(EffectPurpose)))
    foreach(SdsOperation operation in Enum.GetValues(typeof(SdsOperation))){
     bool expected=(purpose==EffectPurpose.Preparation&&operation==SdsOperation.Register)||(purpose==EffectPurpose.FullCleanup&&operation==SdsOperation.UnregisterFull)||(purpose==EffectPurpose.PartialCleanup&&operation==SdsOperation.UnregisterPartial);
     bool accepted=true;try{sdsGate.Invoke(null,new object[]{purpose,operation,30});}catch(TargetInvocationException e){if(!(e.InnerException is InvalidOperationException))throw;accepted=false;}
     Assert(accepted==expected,"SDS purpose mismatch accepted");
    }
   var receiptGate=typeof(SdsBridge).GetMethod("ValidatePublishedReceipt",Hidden);
   string infHash=new string('a',64);
   Func<Dictionary<string,object>> receipt=()=>new Dictionary<string,object>{{"published_inf_schema",1},{"published_inf","oem123.inf"},{"published_inf_was_absent",true},{"published_inf_sha256",infHash}};
   Assert((string)receiptGate.Invoke(null,new object[]{receipt(),infHash})=="oem123.inf","Valid fixed receipt rejected");
   foreach(string field in new[]{"published_inf_schema","published_inf","published_inf_was_absent","published_inf_sha256"}){
    var bad=receipt();bad.Remove(field);bool invalid=false;try{receiptGate.Invoke(null,new object[]{bad,infHash});}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Incomplete receipt accepted");
   }
   foreach(object value in new object[]{"../oem123.inf","oem123.inf /force","oem1234567.inf","oem.inf","OEM123.inf","C:\\oem123.inf",null}){
    var bad=receipt();bad["published_inf"]=value;bool invalid=false;try{receiptGate.Invoke(null,new object[]{bad,infHash});}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Unbounded INF selector accepted");
   }
   foreach(object value in new object[]{"1",true,0,2,null}){
    var bad=receipt();bad["published_inf_schema"]=value;bool invalid=false;try{receiptGate.Invoke(null,new object[]{bad,infHash});}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Coerced receipt schema accepted");
   }
   foreach(object value in new object[]{"true",1,false,null}){
    var bad=receipt();bad["published_inf_was_absent"]=value;bool invalid=false;try{receiptGate.Invoke(null,new object[]{bad,infHash});}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Unproven absence accepted");
   }
   {var bad=receipt();bad["published_inf_sha256"]=new string('b',64);bool invalid=false;try{receiptGate.Invoke(null,new object[]{bad,infHash});}catch(TargetInvocationException e){invalid=e.InnerException is InvalidOperationException;}Assert(invalid,"Changed INF digest accepted");}
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
