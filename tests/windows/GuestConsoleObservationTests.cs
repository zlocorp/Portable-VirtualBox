using System;
using System.IO;
using System.IO.Compression;
namespace PortableVBox.Tests {
 public static class GuestConsoleObservationTests {
  static int checks;
  static void Require(bool ok,string label){checks++;if(!ok)throw new Exception(label);}
  static byte[] Frame(params string[] lines){
   var b=new byte[1024*768*4];int y=48-lines.Length;
   foreach(string line in lines){int x=0;foreach(char c in line){
    string key=null;foreach(var pair in GuestConsoleObservation.Glyphs)if(pair.Value==c)key=pair.Key;
    if(key==null)throw new Exception("Missing fixture glyph "+c);
    for(int r=0;r<16;r++){int bits=Convert.ToByte(key.Substring(r*2,2),16);
     for(int col=0;col<8;col++)if((bits&(1<<(7-col)))!=0){int i=(y*16+r)*4096+(x*8+col)*4;b[i]=b[i+1]=b[i+2]=170;}}
    x++;}y++;}return b;
  }
  static string[] Decode(byte[] frame){return GuestConsoleObservation.Decode(frame,1024,768,4096);}
  static string[] FileFrame(string root,string name){using(var f=File.OpenRead(Path.Combine(root,name+".bgra.gz")))using(var z=new GZipStream(f,CompressionMode.Decompress))using(var m=new MemoryStream()){z.CopyTo(m);return Decode(m.ToArray());}}
  public static void Run(string root){
   string nonce="0123456789abcdef0123456789abcdef";
   Require(GuestConsoleObservation.Shell(FileFrame(root,"observed-shell")),"Historical shell frame not recognized");
   var bad=FileFrame(root,"command-as-login");
   Require(!GuestConsoleObservation.Login(bad)&&!GuestConsoleObservation.Shell(bad)&&!GuestConsoleObservation.Acknowledged(bad,nonce),"Command-as-login accepted");
   Require(GuestConsoleObservation.Login(Decode(Frame("localhost login:"))),"Exact login rejected");
   Require(!GuestConsoleObservation.Login(Decode(Frame("localhost login: root"))),"Entered username accepted");
   Require(!GuestConsoleObservation.Login(Decode(Frame("localhost login:","abc"))),"Stale login accepted");
   Require(GuestConsoleObservation.Shell(Decode(Frame("localhost:~#"))),"Exact shell rejected");
   Require(!GuestConsoleObservation.Shell(Decode(Frame("localhost:~# echo"))),"Command echo accepted as shell");
   Require(!GuestConsoleObservation.Acknowledged(Decode(Frame("PVBOX_"+nonce)),nonce),"Ack without shell accepted");
   Require(!GuestConsoleObservation.Acknowledged(Decode(Frame("localhost:~# PVBOX_"+nonce,"localhost:~#")),nonce),"Echo accepted as acknowledgment");
   Require(!GuestConsoleObservation.Acknowledged(Decode(Frame("PVBOX_"+nonce,"abc","localhost:~#")),nonce),"Stale acknowledgment accepted");
   Require(GuestConsoleObservation.Acknowledged(Decode(Frame("PVBOX_"+nonce,"localhost:~#")),nonce),"Fresh ack and shell rejected");
   Require(!GuestConsoleObservation.Acknowledged(Decode(Frame("PVBOX_"+nonce,"localhost:~#")),"abcdef0123456789abcdef0123456789"),"Foreign nonce accepted");
   var corrupt=Frame("localhost:~#");corrupt[47*16*4096]=255;
   Require(!GuestConsoleObservation.Shell(Decode(corrupt)),"Unknown prompt glyph accepted");
   bool refused=false;try{GuestConsoleObservation.Decode(new byte[1],1,1,1);}catch(InvalidOperationException){refused=true;}
   Require(refused,"Wrong geometry accepted");
   Console.WriteLine("GUEST_CONSOLE_OBSERVATION_PASS checks="+checks);
  }
 }
}
