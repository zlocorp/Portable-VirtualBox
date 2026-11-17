# TEST ONLY: fixed managed path comparison, no native API or child execution.
# stdin: <=128 KiB strict UTF8 JSON array of <=4 exact {held,process} pairs.
# stdout: one compact ordered Boolean array plus LF; host identity is stderr.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
try {
    if ($args.Count -ne 0) { throw 'No arguments accepted' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
        $PSVersionTable.PSEdition -cne 'Desktop' -or
        [Object].Assembly.GetName().Name -cne 'mscorlib' -or
        [Environment]::Version.Major -ne 4) { throw 'Windows PowerShell 5.1/.NET Framework 4.8 required' }
    $framework=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release
    if ($framework.Release -lt 528040) { throw 'Windows PowerShell 5.1/.NET Framework 4.8 required' }
    $bridgeSource=@'
namespace PortableVBox {
 // Constant managed wrapper: its only operations parse bounded data and compare.
 public static class FixedImagePathBridge {
  public static void Run(System.IO.Stream input,System.IO.TextWriter output) {
   byte[] bytes=new byte[131073];int count=0;
   while(count<bytes.Length) {
    int read=input.Read(bytes,count,bytes.Length-count);
    if(read==0)break;
    count+=read;
   }
   if(count>131072)throw new System.ArgumentException("Bridge UTF8 input bound");
   string json=new System.Text.UTF8Encoding(false,true).GetString(bytes,0,count);
   string result=new PairReader(json).Read();
   output.Write(result+"\n");
  }
  sealed class PairReader {
   readonly string text;int offset;
   internal PairReader(string json) { text=json; }
   System.ArgumentException Invalid() { return new System.ArgumentException("Invalid exact path-pair batch"); }
   void White() { while(offset<text.Length && (text[offset]==' ' || text[offset]=='\t' || text[offset]=='\r' || text[offset]=='\n'))offset++; }
   bool Take(char value) { White();if(offset<text.Length && text[offset]==value) { offset++;return true; }return false; }
   void Need(char value) { if(!Take(value))throw Invalid(); }
   string StringValue() {
    Need('"');var value=new System.Text.StringBuilder();
    while(offset<text.Length) {
     char c=text[offset++];
     if(c=='"')return value.ToString();
     if(c<32)throw Invalid();
     if(c!='\\') { value.Append(c);continue; }
     if(offset>=text.Length)throw Invalid();
     c=text[offset++];
     switch(c) {
      case '"':case '\\':case '/':value.Append(c);break;
      case 'b':value.Append('\b');break;
      case 'f':value.Append('\f');break;
      case 'n':value.Append('\n');break;
      case 'r':value.Append('\r');break;
      case 't':value.Append('\t');break;
      case 'u':
       int unit=0;
       for(int i=0;i<4;i++) {
        if(offset>=text.Length)throw Invalid();
        char digit=text[offset++];
        int hex=digit>='0' && digit<='9'?digit-'0':digit>='a' && digit<='f'?digit-'a'+10:digit>='A' && digit<='F'?digit-'A'+10:-1;
        if(hex<0)throw Invalid();unit=unit*16+hex;
       }
       value.Append((char)unit);break;
      default:throw Invalid();
     }
    }
    throw Invalid();
   }
   bool Pair() {
    Need('{');string held=null,process=null;
    for(int i=0;i<2;i++) {
     if(i!=0)Need(',');
     string key=StringValue();Need(':');string value=StringValue();
     if(key=="held" && held==null)held=value;
     else if(key=="process" && process==null)process=value;
     else throw Invalid();
    }
    Need('}');
    if(held==null || process==null)throw Invalid();
    return FixedImagePath.Agree(held,process);
   }
   internal string Read() {
    Need('[');var result=new System.Text.StringBuilder("[");int count=0;
    if(!Take(']')) {
     do {
      if(count>=4)throw Invalid();
      if(count!=0)result.Append(',');
      result.Append(Pair()?"true":"false");count++;
     } while(Take(','));
     Need(']');
    }
    White();if(offset!=text.Length)throw Invalid();
    return result.Append(']').ToString();
   }
  }
 }
}
'@
    # Only these fixed source bytes and the constant wrapper are compiled.
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'NativeFixedImagePath.cs'))
    Add-Type -TypeDefinition ($source+"`n"+$bridgeSource) -Language CSharp -WarningAction Stop
    [Console]::Error.WriteLine(('FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;FrameworkRelease='+$framework.Release+';CLR='+[Environment]::Version.ToString()+';CoreLibrary='+[Object].Assembly.GetName().Name+';OS='+[Environment]::OSVersion.Platform))
    [PortableVBox.FixedImagePathBridge]::Run([Console]::OpenStandardInput(),[Console]::Out)
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
