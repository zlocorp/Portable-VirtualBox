// Test fixture only; all targets must remain in the dedicated experiment cache.
using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
public static class ProtectedWriteProbe {
    public static int Main(string[] args) {
        if(args.Length!=1) return 64;
        string root=Path.GetFullPath(args[0]);
        string store=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"PortableVirtualBox.Experiment")+"\\";
        if(!root.StartsWith(store,StringComparison.OrdinalIgnoreCase)) return 64;
        int refused=0;
        foreach(string relative in new[]{"app64\\VBoxSDS.exe","app64\\.prepared.json","code\\privileged_session_worker.ps1","controller.json"}) {
            string p=Path.Combine(root,relative);
            try {using(var f=new FileStream(p,FileMode.Open,FileAccess.Write)) {} return 1;} catch(UnauthorizedAccessException) {refused++;}
        }
        try {File.WriteAllText(Path.Combine(root,"code\\injected.ps1"),"unexpected");return 2;} catch(UnauthorizedAccessException) {refused++;}
        try {
            string p=Path.Combine(root,"controller.json");var sd=File.GetAccessControl(p);
            sd.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,FileSystemRights.FullControl,AccessControlType.Allow));
            File.SetAccessControl(p,sd);return 3;
        } catch(UnauthorizedAccessException) {refused++;}
        try {Directory.Move(root,root+"-hijack");return 4;} catch(UnauthorizedAccessException) {refused++;} catch(IOException) {refused++;}
        Console.WriteLine("PROTECTED_CACHE_DENIALS="+refused);
        return refused==7?0:5;
    }
}
