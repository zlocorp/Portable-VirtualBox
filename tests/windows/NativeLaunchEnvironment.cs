// Test-only pure environment serializer. No process-launch surface.
using System;
using System.Collections.Generic;
using System.Text;
namespace PortableVBox {
 internal static class EnvironmentBlockCodec {
  internal const int MaximumEntries=16,MaximumNameUnits=64,MaximumValueUnits=4096,MaximumBlockUnits=16384;
  internal static byte[] Encode(KeyValuePair<string,string>[] entries) {
   if(entries==null || entries.Length>MaximumEntries) throw new ArgumentException("Environment entry count");
   // Work only on our own snapshot; sorting must not modify the caller's array.
   var snapshot=(KeyValuePair<string,string>[])entries.Clone();
   var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   int units=snapshot.Length==0?2:1;
   foreach(var entry in snapshot) {
    string name=entry.Key,value=entry.Value;
    if(name==null || name.Length==0 || name.Length>MaximumNameUnits) throw new ArgumentException("Environment name length");
    foreach(char c in name) if(!((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') || c=='_'))
     throw new ArgumentException("Environment name alphabet");
    if(!names.Add(name)) throw new ArgumentException("Duplicate environment name");
    if(value==null || value.Length>MaximumValueUnits) throw new ArgumentException("Environment value length");
    for(int i=0;i<value.Length;i++) {
     char c=value[i];
     if(c=='\0' || char.IsLowSurrogate(c)) throw new ArgumentException("Invalid environment value UTF16");
     if(char.IsHighSurrogate(c)) {
      if(i+1>=value.Length || !char.IsLowSurrogate(value[i+1])) throw new ArgumentException("Invalid environment value UTF16");
      ++i;
     }
    }
    units=checked(units+name.Length+1+value.Length+1);
    if(units>MaximumBlockUnits) throw new ArgumentException("Environment block length");
   }
   Array.Sort(snapshot,delegate(KeyValuePair<string,string> a,KeyValuePair<string,string> b) {
    return StringComparer.OrdinalIgnoreCase.Compare(a.Key,b.Key);
   });
   var block=new StringBuilder(units);
   foreach(var entry in snapshot) block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
   block.Append('\0');if(snapshot.Length==0) block.Append('\0');
   return new UnicodeEncoding(false,false,true).GetBytes(block.ToString());
  }
 }
}
