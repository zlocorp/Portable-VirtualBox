// TEST ONLY. Owned in-process byte transport; no child, privilege or VBox work.
using System;
using System.IO;
using System.Reflection;
using System.Text;

namespace PortableVBox {
 internal static class NativePipeTransportNativeTests {
  static int checks,cases;
  // Roots are preallocated before any native submission. Never clear a retained owner.
  static readonly PipeFixture[] Roots=new PipeFixture[24];
  static int registered;
  static void Check(bool value,string name) {
   ++checks;
   if(!value) throw new InvalidOperationException(name);
  }
  static bool AllReleased() {
   for(int i=0;i<registered;i++) if(Roots[i]==null || !Roots[i].Released) return false;
   return true;
  }
  static void Case(PipeCase scenario) {
   var fixture=new PipeFixture(scenario);
   if(registered>=Roots.Length) throw new InvalidOperationException("Fixture owner bound");
   Roots[registered++]=fixture;
   bool pass=false;
   try {
    fixture.Prepare();
    fixture.Run();
    Check(fixture.SetupComplete,"Positive case requires actual native setup");
    Check(fixture.NativeCalls>0,"Positive case cannot silently skip native calls");
    Check(fixture.AclVerified==2,"Both local fixture pipe DACLs must be inspected");
    Check(fixture.MainCompleted,"Bounded owner loop must actually complete");
    Check(fixture.StorageReleaseEligible,"All exact native operations must be terminal");
    Check(fixture.Rounds>0,"Owner loop must execute");
    for(int i=0;i<2;i++) {
     PipeChannel channel=fixture.Channels[i];
     Check(channel.Connect.Proof.Issued==1 && channel.Connect.Proof.Terminal==1,"Exact connect terminal fact");
     Check(channel.Connect.ResultQueries>0,"Actual connect result must be queried");
     Check(channel.Read.Proof.Issued>0,"Every positive channel must issue native reads");
     Check(channel.Read.Proof.Issued==channel.Read.Proof.Terminal,"Every read generation must terminate");
     Check(channel.Write.Proof.Issued==channel.Write.Proof.Terminal,"Every producer generation must terminate");
     Check(channel.ProducerFinished,"Finite producer final completion is required");
     Check(channel.Produced==channel.Target,"Actual write completion byte count");
     Check(channel.Target==0 || channel.Write.Proof.Terminal>0,"Nonempty producer requires real native write completion");
     Check(channel.ReadVisits==fixture.Rounds && channel.WriteVisits==fixture.Rounds,"Both channels are visited every round");
     Check(channel.MaxReadGap<=1 && channel.MaxWriteGap<=1,"Hot channel cannot monopolize owner loop");
     Check(channel.Capture.RetainedCount<=65536,"64 KiB per-stream retention bound");
     bool cancelled=i==0 && (scenario==PipeCase.CancelBefore || scenario==PipeCase.OneStreamFailure ||
      (scenario==PipeCase.CancelRace && fixture.CancelTerminalError==995));
     if(!cancelled) {
      Check(channel.Capture.Total==channel.Target,"Drained byte count must match producer");
      Check(channel.Capture.Hash==NativePipeTransportTests.PatternHash(channel.Target,channel.Seed),"Raw binary stream FNV-1a mismatch");
      Check(channel.Capture.Eof,"Producer completion alone is not EOF");
     }
     Check(channel.Capture.Discarded==channel.Capture.Total-channel.Capture.RetainedCount,"Exact truncation count");
     for(int n=0;n<channel.Capture.RetainedCount;n++)
      if(channel.Capture.Retained[n]!=NativePipeTransportTests.Pattern(n,channel.Seed))
       throw new InvalidOperationException("Retained binary prefix mismatch");
    }
    if(scenario==PipeCase.Short || scenario==PipeCase.Exact4KiB)
     Check(fixture.Channels[0].Read.ImmediateReturns>0,"Prefilled pipe must exercise immediate native read");
    if(scenario==PipeCase.Large || scenario==PipeCase.HotMarker) {
     Check(fixture.Channels[0].Read.PendingReturns>0 && fixture.Channels[1].Read.PendingReturns>0,"Empty reads must genuinely pend before producers");
     Check(fixture.Channels[0].Capture.Discarded>0,"Large stdout exceeds retention");
     if(scenario==PipeCase.Large) Check(fixture.Channels[1].Capture.Discarded>0,"Large stderr exceeds retention");
    }
    if(scenario==PipeCase.Backpressure) {
     Check(fixture.PendingWritesBeforeReads==2,"Both fixed producers must encounter native backpressure before any read");
     Check(fixture.BackpressureChecks>=4 && fixture.BackpressureMilliseconds>=10,
      "Both exact writes must remain IO_INCOMPLETE across a bounded no-reader observation");
     Check(fixture.Channels[0].Write.PendingReturns>0 && fixture.Channels[1].Write.PendingReturns>0,"Both channels must genuinely return ERROR_IO_PENDING for writes");
     Check(fixture.Channels[0].Capture.Discarded>0 && fixture.Channels[1].Capture.Discarded>0,"Both pressured streams exceed retention and still drain");
    }
    if(scenario==PipeCase.HotMarker)
     Check(fixture.Channels[1].FirstReadRound>0 && fixture.Channels[1].FirstReadRound<fixture.Channels[0].LastReadRound,
      "Small stderr marker must be observed while hot stdout still drains");
    if(scenario==PipeCase.AfterFirstReadFault || scenario==PipeCase.EvidenceFault) {
     Check(fixture.FaultReached==(scenario==PipeCase.AfterFirstReadFault?1:2),"Requested fault site must really be reached");
     Check(fixture.Unknown && fixture.Channels[0].Capture.Unknown,"Diagnostic fault leaves sticky UNKNOWN");
     Check(fixture.Channels[0].Capture.RetainedCount>0 && fixture.Channels[0].Capture.RetainedCount<=4096,"Fault preserves only first chunk then discards");
     Check(fixture.Channels[0].Capture.Total>65536 && fixture.Channels[1].Capture.Total>65536,"Both streams continue after fault");
     if(scenario==PipeCase.EvidenceFault) Check(fixture.DiagnosticBytesWritten==16,"Evidence fault must follow actual bounded write");
    }
    if(scenario==PipeCase.WithheldEof) {
     Check(fixture.EofBudgetExpired && fixture.HeldWriterPreventedEof,"Held duplicate must actually withhold EOF");
     Check(fixture.DuplicateClosed,"Duplicate writer must be separately closed before actual EOF");
     Check(fixture.Unknown && fixture.Channels[0].Capture.Eof,"Later actual EOF must retain timeout UNKNOWN");
    }
    if(scenario==PipeCase.CancelBefore || scenario==PipeCase.OneStreamFailure)
     Check(fixture.CancelError==0 && fixture.CancelTerminalError==995,"Pending cancellation must obtain actual ERROR_OPERATION_ABORTED");
    if(scenario==PipeCase.CancelAfter)
     Check(fixture.CancelError==1168 && fixture.CancelWasAlreadyTerminal,"Native not-found after completion is not new completion evidence");
    if(scenario==PipeCase.CancelRace) {
     Check(fixture.CancelError==0 || fixture.CancelError==1168,"Race cancellation has a documented outcome");
     Check(fixture.CancelTerminalError==0 || fixture.CancelTerminalError==995,"Race must resolve through actual terminal I/O result");
    }
    if(scenario==PipeCase.OneStreamFailure)
     Check(fixture.Channels[0].ReadStopped && fixture.Channels[1].Capture.Total==196731 && fixture.Channels[1].Capture.Eof,
      "One aborted stream cannot stop the other stream draining");
    bool expectedUnknown=scenario==PipeCase.AfterFirstReadFault || scenario==PipeCase.EvidenceFault || scenario==PipeCase.WithheldEof ||
     scenario==PipeCase.CancelBefore || scenario==PipeCase.OneStreamFailure || (scenario==PipeCase.CancelRace && fixture.CancelTerminalError==995);
    Check(fixture.Unknown==expectedUnknown,"Unexpected UNKNOWN cannot be hidden by later native completion");
    int calls=fixture.NativeCalls;
    bool refused=false;
    try { fixture.Run(); } catch(InvalidOperationException) { refused=true; }
    Check(refused && calls==fixture.NativeCalls,"Consumed fixture cannot restart");
    pass=true;
   } catch { fixture.MarkFailure(); throw; }
   finally {
    // Even assertion/reporting failures use the rooted owners, not an unresolved counter.
    fixture.DrainCancellation();
    fixture.ReleaseFixture();
    Console.WriteLine(fixture.Report(pass));
    ++cases;
   }
   Check(fixture.Released,"Every native owner, duplicated writer, event and buffer must be explicitly released");
  }
  public static int Main(string[] arguments) {
   if(arguments.Length!=0) { Console.Error.WriteLine("No command, pipe name or evidence inputs accepted"); return 2; }
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT) { Console.WriteLine("SKIP native pipe transport: Windows required"); return 0; }
   int exit=1;
   try {
    Check(IntPtr.Size==8,"x64 test process required");
    Check(NativePipeTransportTests.RunManaged()==0,"Managed decisions must pass before native I/O");
    foreach(PipeCase scenario in (PipeCase[])Enum.GetValues(typeof(PipeCase))) Case(scenario);
    Check(AllReleased(),"All actual rooted fixtures must be released");
    exit=0;
   } catch(Exception error) {
    Console.WriteLine("{\"kind\":\"native_pipe_failure\",\"status\":\"FAIL\",\"message\":"+QuoteFailure(error.Message)+",\"mutation_authorized\":false}");
   }
   finally {
    bool released=AllReleased();
    Console.WriteLine("{\"kind\":\"native_pipe_summary\",\"status\":\""+(exit==0?"PASS":"FAIL")+"\",\"cases\":"+cases+
     ",\"checks\":"+checks+",\"all_owners_released\":"+(released?"true":"false")+",\"mutation_authorized\":false}");
    if(released) {
     // Generated location only. Receipt is not an input and authorizes no future attempt.
     string root=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
     File.WriteAllText(Path.Combine(root,"pipe-fixture-released"),"all rooted native fixture resources explicitly released\n");
    }
   }
   return exit;
  }
  static string QuoteFailure(string message) {
   // Bounded before escaping/allocation. Failure evidence remains strict JSON.
   int length=Math.Min(message==null?0:message.Length,384);
   var output=new StringBuilder(2306);
   output.Append('"');
   for(int i=0;i<length;i++) {
    char value=message[i];
    if(value=='"' || value=='\\') { output.Append('\\'); output.Append(value); }
    else if(value<32 || Char.IsSurrogate(value)) { output.Append("\\u"); output.Append(((int)value).ToString("x4")); }
    else output.Append(value);
   }
   output.Append('"');
   return output.ToString();
  }
 }
}
