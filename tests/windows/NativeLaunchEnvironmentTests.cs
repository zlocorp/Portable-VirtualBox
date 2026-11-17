// Test-only pure environment codec assertions. No process launch or native calls.
using System;
using System.Collections.Generic;
using System.Text;
namespace PortableVBox {
 internal static class NativeLaunchEnvironmentTests {
  static int checks;
  static KeyValuePair<string,string> Pair(string key,string value) { return new KeyValuePair<string,string>(key,value); }
  static void Check(bool condition,string name) { ++checks;if(!condition) throw new InvalidOperationException("ASSERT: "+name); }
  static void Exact(byte[] actual,string expected,string name) {
   byte[] bytes=new UnicodeEncoding(false,false,true).GetBytes(expected);
   Check(actual.Length==bytes.Length,name+" byte count");
   for(int i=0;i<bytes.Length;i++) Check(actual[i]==bytes[i],name+" byte "+i);
  }
  static void Reject(KeyValuePair<string,string>[] entries,string name) {
   bool rejected=false;try { EnvironmentBlockCodec.Encode(entries); } catch(ArgumentException) { rejected=true; }
   Check(rejected,name);
  }
  static KeyValuePair<string,string>[] BlockAtUnits(int units) {
   // Four one-unit names: 12 separators/name units, one final NUL, then values.
   int remaining=units-13;
   var result=new KeyValuePair<string,string>[4];
   for(int i=0;i<4;i++) { int count=Math.Min(4096,remaining);remaining-=count;result[i]=Pair(((char)('A'+i)).ToString(),new string('x',count)); }
   Check(remaining==0,"boundary fixture complete");return result;
  }
  internal static void RunCodecTests() {
   Exact(EnvironmentBlockCodec.Encode(new[]{Pair("z","last"),Pair("A","a=b"),Pair("b","")}),"A=a=b\0b=\0z=last\0\0","sorted exact UTF16LE");
   Exact(EnvironmentBlockCodec.Encode(new KeyValuePair<string,string>[0]),"\0\0","empty double NUL");
   Exact(EnvironmentBlockCodec.Encode(new[]{Pair("Text","Привет = fixture \U0001F642")}),"Text=Привет = fixture \U0001F642\0\0","Unicode supplementary exact");
   Exact(EnvironmentBlockCodec.Encode(new[]{Pair("Text","e\u0301=%TEMP%=é")}),"Text=e\u0301=%TEMP%=é\0\0","no normalization or expansion");
   var source=new[]{Pair("key","original")};byte[] encoded=EnvironmentBlockCodec.Encode(source);source[0]=Pair("other","changed");
   Exact(encoded,"key=original\0\0","does not alias caller array");
   byte[] second=EnvironmentBlockCodec.Encode(new[]{Pair("key","original")});encoded[0]=0;
   Exact(second,"key=original\0\0","fresh returned allocation");
   Reject(null,"null array");Reject(new[]{Pair(null,"value")},"null name");Reject(new[]{Pair("name",null)},"null value");
   foreach(string name in new[]{"","has space","=drive","equals=","dash-name","é","a\0b","a\ud800",new string('a',65)}) Reject(new[]{Pair(name,"v")},"invalid name");
   Exact(EnvironmentBlockCodec.Encode(new[]{Pair("Ab_019","")}),"Ab_019=\0\0","ASCII name alphabet");
   Exact(EnvironmentBlockCodec.Encode(new[]{Pair(new string('a',64),"")}),new string('a',64)+"=\0\0","64-unit name");
   Reject(new[]{Pair("Path","one"),Pair("PATH","two")},"case-insensitive duplicate");
   foreach(string value in new[]{"a\0b","\ud800","\udc00","a\ud800b","\udc00\ud800","\ud800\ud800","\udc00\udc00"}) Reject(new[]{Pair("key",value)},"invalid value UTF16/NUL");
   var entries=new KeyValuePair<string,string>[16];for(int i=0;i<entries.Length;i++) entries[i]=Pair("K"+i,"");
   Check(EnvironmentBlockCodec.Encode(entries).Length>0,"16 entries allowed");
   var tooMany=new KeyValuePair<string,string>[17];for(int i=0;i<tooMany.Length;i++) tooMany[i]=Pair("K"+i,"");Reject(tooMany,"17 entries rejected");
   Check(EnvironmentBlockCodec.Encode(new[]{Pair("A",new string('x',4096))}).Length==(4096+4)*2,"4096 value units allowed");
   Reject(new[]{Pair("A",new string('x',4097))},"4097 value units rejected");
   string supplementaryAtBound=new string('x',4094)+"\U0001F642";
   Check(EnvironmentBlockCodec.Encode(new[]{Pair("A",supplementaryAtBound)}).Length==8200,"supplementary uses two UTF16 units");
   Reject(new[]{Pair("A",new string('x',4095)+"\U0001F642")},"supplementary exceeds value bound");
   Check(EnvironmentBlockCodec.Encode(BlockAtUnits(16384)).Length==32768,"exact total block bound");
   Reject(BlockAtUnits(16385),"total block bound plus one");
  }
  public static int Main() { RunCodecTests();Console.WriteLine("PASS environment codec: "+checks+" assertions");return 0; }
 }
}
