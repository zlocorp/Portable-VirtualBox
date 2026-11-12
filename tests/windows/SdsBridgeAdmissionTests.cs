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
   Console.WriteLine("SDS_BRIDGE_ADMISSION_PASS assertions="+count);return 0;
  }
 }
}
