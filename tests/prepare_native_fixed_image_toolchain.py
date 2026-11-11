"""Prepare pinned official net48 reference metadata for managed-only tests.

Extract four exact verified DLLs, never execute or install downloaded software.
The optional local package must match the same immutable pin as the fixed URL.
"""
import argparse
import hashlib
import io
from pathlib import Path
import stat
import sys
from urllib.request import urlopen
import zipfile

PACKAGE_URL=('https://api.nuget.org/v3-flatcontainer/'
             'microsoft.netframework.referenceassemblies.net48/1.0.3/'
             'microsoft.netframework.referenceassemblies.net48.1.0.3.nupkg')
PACKAGE_SHA256='8a7e348538e7eb91351696911689f49e3d4f63f8bab517432bbe159b8b1104a2'
REFERENCE_SHA256={
    'mscorlib.dll':'6b35530467b914b0b195146ca1d1485ddd219afaad6461103f16f54e952f75a9',
    'System.dll':'2fe343569f794f2ca92ee14a41875571a9f21bf92637b8f8ee86306534209cca',
    'System.Core.dll':'94a1fc97eb0d36f13acd209bb7207da504c8be10caf7e5096b2c46e671dc6fe2',
    'System.Security.dll':'c867ee14fef732c5803c67a5a00797ef62080b29ce71f6fb14e1af325c8d2a3d',
}
MAX_PACKAGE_BYTES=32*1024*1024
MAX_REFERENCE_BYTES=8*1024*1024


def download(destination):
    with urlopen(PACKAGE_URL,timeout=60) as source,destination.open('xb') as output:
        total=0
        while True:
            block=source.read(65536)
            if not block: break
            total+=len(block)
            if total>MAX_PACKAGE_BYTES: raise ValueError('Reference package download bound')
            output.write(block)


def prepare(directory,package=None):
    root=Path(directory).absolute()
    if any(c in str(root) for c in '\r\n\0'): raise ValueError('Reference directory must be one line')
    root.mkdir(mode=0o700)  # Fresh private output only. Never reuse or overwrite inputs.
    if package is None:
        package=root/'reference-pack.nupkg'
        download(package)
    with Path(package).open('rb') as source:
        raw=source.read(MAX_PACKAGE_BYTES+1)
    if not raw or len(raw)>MAX_PACKAGE_BYTES: raise ValueError('Reference package size bound')
    if hashlib.sha256(raw).hexdigest()!=PACKAGE_SHA256: raise ValueError('Reference package SHA-256 differs from source pin')
    selected={}
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            for name,digest in REFERENCE_SHA256.items():
                exact='build/.NETFramework/v4.8/'+name
                matches=[info for info in archive.infolist() if info.filename==exact]
                if len(matches)!=1: raise ValueError('Missing or duplicate exact reference: '+name)
                info=matches[0]
                kind=stat.S_IFMT(info.external_attr>>16)
                if info.is_dir() or info.external_attr&0x10 or kind not in (0,stat.S_IFREG):
                    raise ValueError('Reference must be a regular file: '+name)
                if not 0<info.file_size<=MAX_REFERENCE_BYTES: raise ValueError('Reference size bound: '+name)
                with archive.open(info) as source:
                    data=source.read(MAX_REFERENCE_BYTES+1)
                if len(data)!=info.file_size or hashlib.sha256(data).hexdigest()!=digest:
                    raise ValueError('Reference bytes differ from source pin: '+name)
                selected[name]=data
    except zipfile.BadZipFile as error:
        raise ValueError('Invalid reference package ZIP') from error
    # Validate all four before creating any compiler-consumable reference output.
    references=root/'references'
    references.mkdir(mode=0o700)
    for name,data in selected.items():
        with (references/name).open('xb') as output: output.write(data)
    return references


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',required=True,type=Path,help='Fresh owned directory outside the source tree')
    parser.add_argument('--package',type=Path,help='Optional offline copy of the same pinned official package')
    args=parser.parse_args()
    try:
        references=prepare(args.directory,args.package)
    except (OSError,ValueError) as error:
        print('Reference metadata preparation failed: '+str(error),file=sys.stderr)
        return 1
    print(references)  # Single verified path, suitable for GITHUB_ENV only after success.
    return 0


if __name__=='__main__': sys.exit(main())
