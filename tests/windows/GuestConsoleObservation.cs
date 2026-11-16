// TEST ONLY: exact observations of a fixed 1024x768 Alpine console, not OCR.
// No imported font code/table. Provenance: tests/fixtures/guest-console/README.md.
using System;
using System.Collections.Generic;
using System.Text;
namespace PortableVBox.Tests {
 public static class GuestConsoleObservation {
  internal static readonly Dictionary<string,char> Glyphs=new Dictionary<string,char> {
   {"00000000000000000000000000000000",' '},
   {"0000006c6cfe6c6c6cfe6c6c00000000",'#'},
   {"0000386cc6c6d6d6c6c66c3800000000",'0'},
   {"00001838781818181818187e00000000",'1'},
   {"00007cc6060c183060c0c6fe00000000",'2'},
   {"00007cc606063c060606c67c00000000",'3'},
   {"00000c1c3c6cccfe0c0c0c1e00000000",'4'},
   {"0000fec0c0c0fc060606c67c00000000",'5'},
   {"00003860c0c0fcc6c6c6c67c00000000",'6'},
   {"0000fec606060c183030303000000000",'7'},
   {"00007cc6c6c67cc6c6c6c67c00000000",'8'},
   {"00007cc6c6c67e0606060c7800000000",'9'},
   {"00000000181800000018180000000000",':'},
   {"0000fc6666667c66666666fc00000000",'B'},
   {"00007cc6c6c6c6c6c6c6c67c00000000",'O'},
   {"0000fc6666667c60606060f000000000",'P'},
   {"0000c6c6c6c6c6c6c66c381000000000",'V'},
   {"0000c6c66c7c38387c6cc6c600000000",'X'},
   {"00000000000000000000000000ff0000",'_'},
   {"0000000000780c7ccccccc7600000000",'a'},
   {"0000e06060786c666666667c00000000",'b'},
   {"00000000007cc6c0c0c0c67c00000000",'c'},
   {"00001c0c0c3c6ccccccccc7600000000",'d'},
   {"00000000007cc6fec0c0c67c00000000",'e'},
   {"00001c36323078303030307800000000",'f'},
   {"000000000076cccccccccc7c0ccc7800",'g'},
   {"0000e060606c7666666666e600000000",'h'},
   {"00001818003818181818183c00000000",'i'},
   {"00003818181818181818183c00000000",'l'},
   {"0000000000dc66666666666600000000",'n'},
   {"00000000007cc6c6c6c6c67c00000000",'o'},
   {"0000000000dc7666606060f000000000",'r'},
   {"00000000007cc660380cc67c00000000",'s'},
   {"0000103030fc30303030361c00000000",'t'},
   {"0076dc00000000000000000000000000",'~'},
  };
  public static string[] Decode(byte[] bgra,int width,int height,int stride){
   if(width!=1024||height!=768||stride!=4096||bgra==null||bgra.Length!=stride*height)
    throw new InvalidOperationException("Unsupported fixed Alpine console geometry");
   var lines=new string[height/16];
   for(int y=0;y<lines.Length;y++){
    var line=new StringBuilder();
    for(int x=0;x<width/8;x++){
     var key=new StringBuilder();
     for(int r=0;r<16;r++){
      int mask=0;
      for(int c=0;c<8;c++){
       int i=(y*16+r)*stride+(x*8+c)*4;
       if((bgra[i]|bgra[i+1]|bgra[i+2])!=0)mask|=1<<(7-c);
      }
      key.Append(mask.ToString("x2"));
     }
     char ch;string k=key.ToString();
     // Linux text cursor over an empty cell may blink as two full bottom rows.
     // It is accepted only as trailing whitespace, never as a prompt character.
     if(k=="0000000000000000000000000000ffff")ch=' ';
     else if(!Glyphs.TryGetValue(k,out ch))ch='?';
     line.Append(ch);
    }
    lines[y]=line.ToString().TrimEnd(' ');
   }
   return lines;
  }
  static int Last(string[] lines){int i=lines.Length-1;while(i>=0&&lines[i].Length==0)i--;return i;}
  public static bool Login(string[] lines){int i=Last(lines);return i>=0&&lines[i]=="localhost login:";}
  public static bool Shell(string[] lines){int i=Last(lines);return i>=0&&lines[i]=="localhost:~#";}
  public static bool Acknowledged(string[] lines,string nonce){
   if(nonce==null||nonce.Length!=32)return false;
   foreach(char c in nonce)if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;
   int i=Last(lines);return i>0&&Shell(lines)&&lines[i-1]=="PVBOX_"+nonce;
  }
 }
}
