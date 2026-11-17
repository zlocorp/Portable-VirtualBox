// TEST ONLY. Fixed finite modes; no shell, arbitrary command, system or VBox work.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;

namespace PortableVBox {
 internal static class NativeLaunchFixtureChild {
  static void Marker(string root,string name,string token) {
   byte[] bytes=Encoding.ASCII.GetBytes(token+"\n");
   using(var stream=new FileStream(Path.Combine(root,name),FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
    stream.Write(bytes,0,bytes.Length);stream.Flush(true);
   }
  }
  public static int Main(string[] args) {
   if(args.Length!=3) return 81;
   Guid token;
   if(!Guid.TryParseExact(args[1],"N",out token)) return 82;
   string root=Path.GetFullPath(args[0]);
   string own=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
   if(!String.Equals(root,own,StringComparison.OrdinalIgnoreCase) ||
      !Path.GetFileName(root).StartsWith("pvbox-native-launch-",StringComparison.Ordinal) ||
      File.ReadAllText(Path.Combine(root,"fixture.owner"))!=args[1]) return 83;
   if(args[2]!="Immediate" && args[2]!="Delayed" && args[2]!="Nonzero" && args[2]!="Exit259") return 84;
   Marker(root,"started.marker",args[1]);
   if(args[2]=="Delayed") {
    // Test fixture orchestration only, never admission or mutation authority.
    // A finite fallback prevents an abandoned parent from keeping this child alive.
    var deadline=Stopwatch.StartNew();
    while(!File.Exists(Path.Combine(root,"release.marker")) && deadline.ElapsedMilliseconds<10000) Thread.Sleep(10);
   }
   Marker(root,"exited.marker",args[1]); // Marker is not proof of actual process exit.
   return args[2]=="Nonzero"?70:args[2]=="Exit259"?259:0;
  }
 }
}
