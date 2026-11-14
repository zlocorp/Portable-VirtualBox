// TEST ONLY: bounded DOS spelling, no filesystem canonicalization or native calls.
using System;
namespace PortableVBox {
 internal static class FixedImagePath {
  internal static string Validate(string raw) {
   if(String.IsNullOrEmpty(raw) || raw.Length>=32768)throw new ArgumentException("Path bound");
   for(int i=0;i<raw.Length;i++) {
    char c=raw[i];
    if(c<=0x1f || (c>=0x7f && c<=0x9f))throw new ArgumentException("Path control character");
    if(Char.IsHighSurrogate(c)) {
     if(i+1>=raw.Length || !Char.IsLowSurrogate(raw[++i]))throw new ArgumentException("Path UTF16");
    } else if(Char.IsLowSurrogate(c))throw new ArgumentException("Path UTF16");
   }
   int start=raw.StartsWith(@"\\?\",StringComparison.Ordinal)?4:0;
   if(raw.Length-start<3 || !((raw[start]>='A' && raw[start]<='Z') || (raw[start]>='a' && raw[start]<='z')) || raw[start+1]!=':' || raw[start+2]!='\\')throw new ArgumentException("Non-local-DOS path");
   return raw;
  }
  internal static string Comparable(string raw) {
   Validate(raw);
   return raw.StartsWith(@"\\?\",StringComparison.Ordinal)?raw.Substring(4):raw;
  }
  internal static bool Agree(string held,string process) {
   return String.Equals(Comparable(held),Comparable(process),StringComparison.OrdinalIgnoreCase);
  }
 }
}
