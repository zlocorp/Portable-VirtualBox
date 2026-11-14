// Fixed cleanup completion order only. All operations are private, compiled Main
// call sites, never supplied by a controller, receipt, environment or command.
using System;
using System.Runtime.ExceptionServices;
using System.Threading.Tasks;
namespace PortableVBox {
 public static partial class SessionHelper {
  static void CompleteCleanupWorker(bool withinDeadline,int childExit,Action persistExit,
   Task<string> stdout,Task<string> stderr,Action verifyController,Action createCheckpoint,
   Action<string> writeStdout,Action<string> writeStderr,Action writeFacts) {
   Exception failure=null;
   if(!withinDeadline) failure=new InvalidOperationException("Fixed effect exceeded deadline (child completed); inspect protected receipts");
   else if(childExit!=0) failure=new InvalidOperationException("Fixed effect worker rejected operation");
   try {persistExit();} catch(Exception error) {if(failure==null) failure=error;}
   string output=null,errors=null;bool outputReady=false,errorsReady=false;
   // Drain both retained-child streams independently, even if one capture faults.
   try {output=stdout.GetAwaiter().GetResult();outputReady=true;} catch(Exception error) {if(failure==null) failure=error;}
   try {errors=stderr.GetAwaiter().GetResult();errorsReady=true;} catch(Exception error) {if(failure==null) failure=error;}
   if(failure==null) {
    try {verifyController();createCheckpoint();} catch(Exception error) {failure=error;}
   }
   // Available failure evidence is still attempted, but no failure is converted
   // into success and diagnostics never replace the original worker rejection.
   // In the eligible case the existing fully verified checkpoint is already durable.
   if(outputReady) try {writeStdout(output);} catch(Exception error) {if(failure==null) failure=error;}
   if(errorsReady) try {writeStderr(errors);} catch(Exception error) {if(failure==null) failure=error;}
   try {writeFacts();} catch(Exception error) {if(failure==null) failure=error;}
   if(failure!=null) ExceptionDispatchInfo.Capture(failure).Throw();
  }
 }
}
