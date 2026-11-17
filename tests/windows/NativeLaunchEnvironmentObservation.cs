// TEST ONLY: bounded observations of the harmless fixed child's environment.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
namespace PortableVBox {
 internal static class EnvironmentObservationApi {
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] internal static extern IntPtr GetEnvironmentStringsW();
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool FreeEnvironmentStringsW(IntPtr block);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool SetEnvironmentVariableW(string name,string value);
 }
 internal sealed class EnvironmentObservation {
  internal const int MaxRecordBytes=16384;
  internal const string SentinelName="PVBOX_FIXTURE_AMBIENT_SENTINEL";
  static readonly string[] Names={SentinelName,"PVBOX_FIXTURE_TEXT","PVBOX_FIXTURE_EMPTY","SystemRoot","WINDIR"};
  static readonly Encoding Unicode=new UnicodeEncoding(false,false,true);
  readonly string[] values;
  EnvironmentObservation(string[] actual) { values=(string[])actual.Clone(); }
  internal string Sentinel { get { return values[0]; } }
  internal string Text { get { return values[1]; } }
  internal string Empty { get { return values[2]; } }
  internal string WindowsDirectory { get { return values[3]; } }
  internal string Windir { get { return values[4]; } }
  internal bool EmptyPresent { get { return values[2]!=null; } }
  internal bool SentinelPresent { get { return values[0]!=null; } }
  static ArgumentException Bad() { return new ArgumentException("Invalid bounded environment observation"); }
  static void ValidText(string value) {
   if(value.IndexOf('\0')>=0) throw Bad();
   try { Unicode.GetByteCount(value); } catch(EncoderFallbackException) { throw Bad(); }
  }
  internal static EnvironmentObservation FromBlock(Func<int,char> read) {
   if(read==null) throw Bad();
   string[] found=new string[5];var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   int cursor=0,entries=0;
   while(cursor<32768) {
    char first=read(cursor++);
    if(first=='\0') {
     // For nonempty blocks the preceding entry terminator was the first NUL.
     if(entries==0 && (cursor>=32768 || read(cursor++)!='\0')) throw Bad();
     return new EnvironmentObservation(found);
    }
    if(++entries>512) throw Bad();
    var entry=new StringBuilder();entry.Append(first);bool terminated=false;
    while(entry.Length<8192 && cursor<32768) {
     char c=read(cursor++);
     if(c=='\0') { terminated=true;break; }
     entry.Append(c);
    }
    if(!terminated || entry.Length+1>8192) throw Bad();
    string text=entry.ToString();ValidText(text);
    int split=text.IndexOf('=');
    if(split==0) {
     if(text.Length<4 || !((text[1]>='A' && text[1]<='Z') || (text[1]>='a' && text[1]<='z')) || text[2]!=':' || text[3]!='=') throw Bad();
     split=3;
    }
    if(split<=0) throw Bad();
    string name=text.Substring(0,split),value=text.Substring(split+1);
    if(!names.Add(name)) throw Bad();
    for(int i=0;i<Names.Length;i++) if(String.Equals(name,Names[i],StringComparison.OrdinalIgnoreCase)) {
     if(value.Length>4096) throw Bad();found[i]=value;
    }
   }
   throw Bad();
  }
  internal static EnvironmentObservation ReadOwnedBlock(IntPtr original,Func<int,char> read,Func<IntPtr,bool> free) {
   if(original==IntPtr.Zero) throw Bad();
   if(free==null) throw Bad();
   try { return FromBlock(read); }
   finally { if(!free(original)) throw new InvalidOperationException("Environment observation free failed; no retry"); }
  }
  internal static EnvironmentObservation ReadCurrent() {
   IntPtr original=IntPtr.Zero;
   // Prepare both callbacks before obtaining ownership of the native block.
   Func<int,char> read=delegate(int index) { return (char)(ushort)Marshal.ReadInt16(original,checked(index*2)); };
   Func<IntPtr,bool> free=EnvironmentObservationApi.FreeEnvironmentStringsW;
   original=EnvironmentObservationApi.GetEnvironmentStringsW();
   return ReadOwnedBlock(original,read,free);
  }
  internal byte[] Encode() {
   int total=12;ushort flags=0;
   for(int i=0;i<5;i++) {
    if(values[i]!=null) { ValidText(values[i]);if(values[i].Length>4096) throw Bad();flags|=(ushort)(1<<i); }
    total=checked(total+4+(values[i]==null?0:values[i].Length*2));
   }
   if(total>MaxRecordBytes) throw Bad();
   using(var stream=new MemoryStream(total)) using(var writer=new BinaryWriter(stream)) {
    writer.Write(new byte[]{80,86,69,49});writer.Write((ushort)1);writer.Write(flags);writer.Write((uint)total);
    for(int i=0;i<5;i++) { byte[] bytes=values[i]==null?new byte[0]:Unicode.GetBytes(values[i]);writer.Write((uint)bytes.Length);writer.Write(bytes); }
    return stream.ToArray();
   }
  }
  static uint U32(byte[] bytes,int position) { return (uint)(bytes[position]|bytes[position+1]<<8|bytes[position+2]<<16|bytes[position+3]<<24); }
  internal static EnvironmentObservation Parse(byte[] bytes) {
   if(bytes==null || bytes.Length<32 || bytes.Length>MaxRecordBytes) throw Bad();
   if(bytes[0]!=80 || bytes[1]!=86 || bytes[2]!=69 || bytes[3]!=49 || bytes[4]!=1 || bytes[5]!=0 || bytes[7]!=0 || (bytes[6]&224)!=0 || U32(bytes,8)!=(uint)bytes.Length) throw Bad();
   int at=12;string[] found=new string[5];
   for(int i=0;i<5;i++) {
    if(at>bytes.Length-4) throw Bad();uint count=U32(bytes,at);at+=4;
    bool present=(bytes[6]&(1<<i))!=0;
    if(count>8192 || (count&1)!=0 || count>(uint)(bytes.Length-at) || (!present && count!=0)) throw Bad();
    if(present) {
     try { found[i]=Unicode.GetString(bytes,at,(int)count); } catch(DecoderFallbackException) { throw Bad(); }
     ValidText(found[i]);
    }
    at+=(int)count;
   }
   if(at!=bytes.Length) throw Bad();return new EnvironmentObservation(found);
  }
 }
 internal sealed class NativeEnvironmentSentinel : IDisposable {
  readonly string prior;
  bool restoreEntered;
  internal bool Restored { get; private set; }
  internal bool ParentPresent { get; private set; }
  internal NativeEnvironmentSentinel() {
   prior=EnvironmentObservation.ReadCurrent().Sentinel;
   try {
    Set("ambient-only");
    ParentPresent=EnvironmentObservation.ReadCurrent().Sentinel=="ambient-only";
    if(!ParentPresent) throw new InvalidOperationException("Parent sentinel verification failed");
   } catch { Dispose();throw; }
  }
  internal static void Set(string value) {
   // Null deletes, non-null empty establishes an entry with an empty native value.
   if(!EnvironmentObservationApi.SetEnvironmentVariableW(EnvironmentObservation.SentinelName,value)) throw new InvalidOperationException("Native sentinel update failed");
  }
  public void Dispose() {
   if(restoreEntered) { if(!Restored) throw new InvalidOperationException("Sentinel restore unresolved; no retry");return; }
   restoreEntered=true;
   Set(prior);
   Restored=String.Equals(EnvironmentObservation.ReadCurrent().Sentinel,prior,StringComparison.Ordinal);
   if(!Restored) throw new InvalidOperationException("Exact sentinel restoration failed");
  }
 }
}
