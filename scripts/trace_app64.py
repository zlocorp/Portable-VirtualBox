"""Developer-only preparation probe; invokes the normal file-only implementation.

Does not suppress tracebacks. Use only with disposable CI paths; not a user CLI.
"""
import sys
from pathlib import Path
import prepare_app64

original = prepare_app64.cabinet_members

def inspect_cabinet(path):
    with Path(path).open('rb') as source:
        header = source.read(40)
    print(f'Cabinet boundary: {Path(path).name}, size={Path(path).stat().st_size}, header={header.hex()}', flush=True)
    return original(path)

prepare_app64.cabinet_members = inspect_cabinet
prepare_app64.prepare(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], '7.2.20')
