// TEST ONLY: exact production owner, closed harmless fixtures, no CLI command selector.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
namespace PortableVBox {
 public static class FixedEffectWorkerNativeTests {
  static int assertions;
  const string RawFixtureProgress="$ProgressPreference='SilentlyContinue';";
  static void Assert(bool ok,string message){assertions++;if(!ok)throw new Exception(message);}
  static ProcessStartInfo Fixture(string script) {
   // Measured baseline/native output both contained identical CLIXML module
   // preparation progress. This fixture tests raw stdout/stderr, not host
   // progress serialization. Suppress progress only, before the first cmdlet;
   // do not filter captured bytes or silence errors.
   script=RawFixtureProgress+script;
   string image=Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe");
   var info=new ProcessStartInfo(image,"-NoLogo -NoProfile -NonInteractive -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
   info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
   info.WorkingDirectory=Environment.SystemDirectory;info.EnvironmentVariables.Clear();
   info.EnvironmentVariables["SystemRoot"]=Environment.GetEnvironmentVariable("SystemRoot");
   info.EnvironmentVariables["WINDIR"]=Environment.GetEnvironmentVariable("WINDIR");
   info.EnvironmentVariables["TEMP"]=Path.GetTempPath();info.EnvironmentVariables["TMP"]=Path.GetTempPath();
   return info;
  }
  // Bounded diagnostics of generated fixture output only, not caller data.
  static string Units(string text,int start,int count) {
   var result=new StringBuilder();
   for(int i=start;i<Math.Min(text.Length,start+count);i++)result.Append(((int)text[i]).ToString("X4")).Append(' ');
   return result.ToString();
  }
  static void Describe(string label,string text,string expected) {
   int mismatch=0;while(mismatch<text.Length&&mismatch<expected.Length&&text[mismatch]==expected[mismatch])mismatch++;
   Console.WriteLine(label+" length="+text.Length+" expected="+expected.Length+" firstDifference="+mismatch);
   Console.WriteLine(label+" firstUnits="+Units(text,0,128));
   Console.WriteLine(label+" lastUnits="+Units(text,Math.Max(0,text.Length-128),128));
  }
  public static int Main() {
   Assert(Environment.OSVersion.Platform==PlatformID.Win32NT&&IntPtr.Size==8,"Windows x64 required");
   Console.OutputEncoding=new UTF8Encoding(false);
   string trustedCommon=Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
   Assert(!String.IsNullOrEmpty(trustedCommon)&&Path.IsPathRooted(trustedCommon),"Parent known-folder resolution unavailable");
   const string knownFolderProbe="$p=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData);[Console]::Out.Write([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($p)));exit 0";
   var baselineEnvironment=Fixture(knownFolderProbe);baselineEnvironment.EnvironmentVariables["ProgramData"]=trustedCommon;
   string baselineCommon;
   using(var probe=FixedEffectWorker.Run(baselineEnvironment)){
    probe.VerifyImageObservation();Assert(probe.WithinDeadline&&probe.ExitCodeKnown&&probe.ExitCode==0,"Known-folder baseline did not complete");
    baselineCommon=Encoding.Unicode.GetString(Convert.FromBase64String(probe.StandardOutput.Result));
    Assert(probe.StandardError.Result=="","Known-folder baseline stderr changed");
   }
   Console.WriteLine("KNOWN_FOLDER baseline_empty="+(baselineCommon.Length==0)+" baseline_matches_parent="+String.Equals(baselineCommon,trustedCommon,StringComparison.OrdinalIgnoreCase)+" baseline_length="+baselineCommon.Length);
   // Child shell lookup remains unresolved. The protected worker instead uses
   // the explicit store validated by the parent; this is transport proof only,
   // not authority or a claim that known-folder resolution has been repaired.
   string trustedStore=Path.Combine(trustedCommon,"PortableVirtualBox.Experiment");
   const string storeProbe="[Console]::Out.Write([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($env:RUNNER_TEMP)));exit 0";
   var explicitEnvironment=Fixture(storeProbe);explicitEnvironment.EnvironmentVariables["RUNNER_TEMP"]=trustedStore;
   using(var probe=FixedEffectWorker.Run(explicitEnvironment)){
    probe.VerifyImageObservation();Assert(probe.WithinDeadline&&probe.ExitCodeKnown&&probe.ExitCode==0,"Explicit store probe did not complete");
    string observedStore=Encoding.Unicode.GetString(Convert.FromBase64String(probe.StandardOutput.Result));
    Assert(String.Equals(observedStore,trustedStore,StringComparison.Ordinal),"Explicit store differs from trusted parent");
    Assert(probe.StandardError.Result=="","Explicit store probe stderr changed");
   }
   Console.WriteLine("NATIVE explicit trusted parent store transport PASS");
   const string encoding="[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);";
   const string large=encoding+"[Console]::Out.Write(('a'*180000)+'Привет 世界');[Console]::Error.Write(('b'*190000)+'Ошибка 世界');exit 259";
   string expectedOut=new string('a',180000)+"Привет 世界",expectedError=new string('b',190000)+"Ошибка 世界";
   string baselineOut,baselineError;
   // Comparison only: former managed launch transport with the identical closed
   // harmless command/environment. It does not decide whether native is accepted.
   using(var baseline=new Process {StartInfo=Fixture(large)}) {
    baseline.Start();var output=baseline.StandardOutput.ReadToEndAsync();var errors=baseline.StandardError.ReadToEndAsync();
    baseline.WaitForExit();baselineOut=output.GetAwaiter().GetResult();baselineError=errors.GetAwaiter().GetResult();
    Console.WriteLine("BASELINE exit="+baseline.ExitCode+" readerEncoding="+Console.OutputEncoding.CodePage);
   }
   Describe("BASELINE stdout",baselineOut,expectedOut);Describe("BASELINE stderr",baselineError,expectedError);
   using(var owner=FixedEffectWorker.Run(Fixture(large))) {
    Assert(owner.WithinDeadline&&owner.ExitCodeKnown&&owner.ExitCode==259,"Measured exit 259 is not STILL_ACTIVE");owner.VerifyImageObservation();
    string output=owner.StandardOutput.GetAwaiter().GetResult(),errors=owner.StandardError.GetAwaiter().GetResult();
    Describe("NATIVE stdout",output,expectedOut);Describe("NATIVE stderr",errors,expectedError);
    Console.WriteLine("BASELINE_NATIVE exact stdout="+(baselineOut==output)+" stderr="+(baselineError==errors));
    Assert(output==expectedOut,"Full stdout/Unicode changed");
    Assert(errors==expectedError,"Full stderr/Unicode changed");
   }
   Console.WriteLine("NATIVE full-output Unicode both-streams exit-259 PASS");
   var invalid=Fixture("exit 0");invalid.WorkingDirectory=Path.Combine(Path.GetTempPath(),"pvbox-missing-"+Guid.NewGuid().ToString("N"));
   bool refused=false;try{using(var owner=FixedEffectWorker.Run(invalid)) { }}catch(System.ComponentModel.Win32Exception error){refused=error.NativeErrorCode==267||error.NativeErrorCode==3;}
   Assert(refused,"Invalid native working directory not refused");
   using(var owner=FixedEffectWorker.Run(Fixture("[Console]::Out.Write('after-false');exit 0"))) {
    owner.VerifyImageObservation();Assert(owner.ExitCodeKnown&&owner.ExitCode==0&&owner.StandardOutput.Result=="after-false","Create FALSE poisoned next independent owner");
   }
   Console.WriteLine("NATIVE normal-CreateProcess-FALSE and subsequent independent owner PASS");
   string gate=Path.Combine(Path.GetTempPath(),"pvbox-eof-gate-"+Guid.NewGuid().ToString("N"));
   string child=Convert.ToBase64String(Encoding.Unicode.GetBytes(RawFixtureProgress+encoding+"while(-not [IO.File]::Exists('"+gate.Replace("'","''")+"')){Start-Sleep -Milliseconds 50};[Console]::Out.Write('descendant-eof');[Console]::Error.Write('descendant-error');exit 0"));
   string parent="$p=Start-Process -FilePath ([IO.Path]::Combine([Environment]::SystemDirectory,'WindowsPowerShell','v1.0','powershell.exe')) -ArgumentList '-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand','"+child+"' -NoNewWindow -PassThru;[Console]::Out.Write('parent-exit;');exit 0";
   FixedEffectWorker inherited=null;Thread disposer=null;Exception disposeError=null;
   var disposed=new ManualResetEvent(false);var disposeEntered=new ManualResetEvent(false);
   try {
    inherited=FixedEffectWorker.Run(Fixture(parent));
    Assert(inherited.ExitCodeKnown&&inherited.ExitCode==0,"Parent exit not measured");inherited.VerifyImageObservation();
    Assert(!inherited.StandardOutput.IsCompleted,"Inherited output reached EOF before gate");
    disposer=new Thread(()=>{disposeEntered.Set();try{inherited.Dispose();}catch(Exception e){disposeError=e;}finally{disposed.Set();}});
    disposer.Start();
    Assert(disposeEntered.WaitOne(10000),"Disposer did not enter");
    Assert(!disposed.WaitOne(250),"Dispose released while descendant gate closed");
   } finally {
    File.WriteAllText(gate,"release");
    if(disposer!=null)disposer.Join();
    else if(inherited!=null)inherited.Dispose();
   }
   Assert(disposeError==null,"Dispose failed after real descendant EOF");
   Assert(inherited.StandardOutput.Result=="parent-exit;descendant-eof","Descendant stdout lost");
   Assert(inherited.StandardError.Result=="descendant-error","Descendant stderr lost");
   File.Delete(gate);
   Console.WriteLine("NATIVE exit-before-descendant-EOF and disposal-retention PASS");
   var timer=Stopwatch.StartNew();
   timer.Restart();
   using(var owner=FixedEffectWorker.Run(Fixture("[Console]::Out.Write('before;');Start-Sleep -Seconds 153;[Console]::Out.Write('after');[Console]::Error.Write('alive-after-deadline');exit 0"))) {
    Assert(!owner.WithinDeadline&&owner.ExitCodeKnown&&owner.ExitCode==0,"Deadline did not retain exact child to exit");owner.VerifyImageObservation();
    Assert(timer.Elapsed.TotalSeconds>=152,"Owner returned before fixed child completion");
    Assert(owner.StandardOutput.Result=="before;after"&&owner.StandardError.Result=="alive-after-deadline","Deadline lost output or killed worker");
   }
   Console.WriteLine("NATIVE real-150s-deadline-retention PASS");
   Console.WriteLine("FIXED_EFFECT_NATIVE_PASS assertions="+assertions);return 0;
  }
 }
}
