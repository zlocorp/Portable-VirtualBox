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
        // Owner normalization removes the inherited OWNER_RIGHTS ACE on Windows.
        // Strict Administrators ownership must still deny medium-token WRITE_DAC
        // for every executable/manifest/control-file class, not just file writes.
        foreach(string relative in new[]{"app64\\VBoxSDS.exe","app64\\.prepared.json","code\\privileged_session_worker.ps1","controller.json"}) {
            string p=Path.Combine(root,relative);var sd=File.GetAccessControl(p);
            if(!sd.GetOwner(typeof(SecurityIdentifier)).Equals(new SecurityIdentifier("S-1-5-32-544"))) return 8;
            sd.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,FileSystemRights.FullControl,AccessControlType.Allow));
            try {File.SetAccessControl(p,sd);return 3;}
            catch(UnauthorizedAccessException) {refused++;}
        }
        try {Directory.Move(root,root+"-hijack");return 4;} catch(UnauthorizedAccessException) {refused++;} catch(IOException) {refused++;}
        string[] journals=Directory.GetFiles(root,"*.journal",SearchOption.TopDirectoryOnly);
        if(journals.Length!=1) return 6; // exactly the completed Prepare attempt
        foreach(string journal in journals) {
            try {using(var f=new FileStream(journal,FileMode.Open,FileAccess.Write)) {} return 7;} catch(UnauthorizedAccessException) {refused++;}
            var sd=File.GetAccessControl(journal);
            if(!sd.GetOwner(typeof(SecurityIdentifier)).Equals(new SecurityIdentifier("S-1-5-32-544"))) return 8;
            sd.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,FileSystemRights.FullControl,AccessControlType.Allow));
            try {File.SetAccessControl(journal,sd);return 9;}
            catch(UnauthorizedAccessException) {refused++;}
        }
        Console.WriteLine("PROTECTED_CACHE_DENIALS="+refused);
        return refused==12?0:5;
    }
}
