// TEST ONLY. The one byte-preserving legacy/fixed Binary command formatter.
using System.Globalization;
using System.Text;
namespace PortableVBox {
 internal static class FixedFixtureCommand {
  internal static StringBuilder Format(string image,string scenario,long candidate,string token) {
   return new StringBuilder("\""+image+"\" "+scenario+" "+candidate.ToString(CultureInfo.InvariantCulture)+" "+token);
  }
 }
}
