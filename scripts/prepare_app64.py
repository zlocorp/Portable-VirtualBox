#!/usr/bin/env python3
"""Prepare a new app64 tree from a trusted hash-pinned Oracle wrapper, never install.

Windows only. Publisher signature must be checked by the invoking workflow.
A caller-provided expected checksum is a trust input, not one read from the EXE.
"""
from __future__ import annotations
import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
from oracle_extract import extract_packages
from msi_staging import assemble, build_plan, regular_file, single_name, validate_members
from windows_payload import MsiReader, cabinet_members, extract_cabinet

REQUIRED_PE=(
    'VirtualBox.exe','VirtualBoxVM.exe','VBoxManage.exe','VBoxSVC.exe','VBoxSDS.exe',
    'VBoxC.dll','VBoxRT.dll','VBoxVMM.dll','Qt6CoreVBox.dll','Qt6GuiVBox.dll',
    'Qt6WidgetsVBox.dll','platforms/qwindowsVBox.dll','drivers/vboxsup/VBoxSup.sys',
)
REQUIRED_DATA=('drivers/vboxsup/VBoxSup.inf','drivers/vboxsup/VBoxSup.cat')


def sha256(path):
    regular_file(path)
    with open(path,'rb') as file: return hashlib.file_digest(file,'sha256').hexdigest()


def pe_machine(path):
    size=regular_file(path).st_size
    with open(path,'rb') as file:
        dos=file.read(64)
        if len(dos)!=64 or dos[:2]!=b'MZ': raise ValueError('Not a PE image')
        offset=struct.unpack_from('<I',dos,60)[0]
        if offset<64 or offset>min(size-26,1024*1024): raise ValueError('Invalid PE header offset')
        file.seek(offset); header=file.read(26)
        if len(header)!=26 or header[:4]!=b'PE\0\0': raise ValueError('Invalid PE signature')
        if struct.unpack_from('<H',header,24)[0] not in (0x10b,0x20b): raise ValueError('Invalid optional header')
        return struct.unpack_from('<H',header,4)[0]


def validate_runtime(root):
    for name in REQUIRED_PE:
        if pe_machine(root/name)!=0x8664: raise ValueError('Required file is not AMD64: '+name)
    for name in REQUIRED_DATA:
        if regular_file(root/name).st_size==0: raise ValueError('Empty required driver metadata')
    return {'required_pe_count':len(REQUIRED_PE),'required_data_count':len(REQUIRED_DATA),
            'required_pe_machine':'AMD64','runtime_executed':False,'driver_installed':False}


def prepare(installer,destination,expected_sha256,version):
    destination=Path(destination)
    if os.path.lexists(destination): raise FileExistsError('Destination already exists')
    if not re.fullmatch(r'7\.2\.[0-9]+',version): raise ValueError('Only explicit 7.2.x packages are supported')
    if os.name!='nt': raise OSError('Windows APIs are required for MSI/CAB preparation')
    if not destination.parent.is_dir(): raise ValueError('Existing trusted output parent required')
    with tempfile.TemporaryDirectory(prefix='.vbox-prepare-',dir=destination.parent) as folder:
        work=Path(folder); packages=work/'packages'
        package_rows=extract_packages(Path(installer),packages,expected_sha256)
        compatible=[p for p in package_rows if p['architecture']=='amd64' and p['name'].endswith('.msi')]
        if len(compatible)!=1: raise ValueError('Expected one AMD64 MSI')
        msi=packages/compatible[0]['name']
        input_hashes={packages/p['name']:p['sha256'] for p in package_rows}
        for path,expected in input_hashes.items():
            if sha256(path)!=expected: raise ValueError('Package payload hash changed')
        outputs={}; cabinets=[]
        with MsiReader(msi) as reader:
            rows=reader.table('Property'); properties={r['Property']:r['Value'] for r in rows}
            if len(properties)!=len(rows): raise ValueError('Duplicate MSI property')
            template=reader.summary(7); flags=reader.summary(15)
            if (properties.get('ProductVersion')!=version or 'VirtualBox' not in properties.get('ProductName','')
                    or not properties.get('Manufacturer','').startswith('Oracle')
                    or not isinstance(template,str) or not template.startswith('x64;') or type(flags) is not int):
                raise ValueError('MSI identity/version/platform not accepted')
            metadata={name:reader.table(name) for name in ('Directory','Component','File','Media')}
            plan=build_plan(metadata,compressed=bool(flags&2))
            by_cabinet=defaultdict(list)
            for item in plan.files: by_cabinet[item.cabinet].append(item)
            for index,(cabinet,expected_files) in enumerate(by_cabinet.items()):
                if cabinet.startswith('#'):
                    cab=work/f'embedded-{index}.cab'
                    reader.export_stream(cabinet[1:],cab)
                else:
                    single_name(cabinet); cab=packages/cabinet
                    if cab not in input_hashes: raise ValueError('External cabinet not in signed wrapper')
                cab_hash=sha256(cab)
                members=cabinet_members(cab); validate_members(members,expected_files)
                raw=work/f'raw-{index}'; raw.mkdir()
                extract_cabinet(cab,raw,{item.key:item.size for item in expected_files})
                if sha256(cab)!=cab_hash: raise ValueError('Cabinet changed during extraction')
                for item in expected_files: outputs[item.key]=raw/item.key
                cabinets.append({'cabinet':cabinet,'sha256':cab_hash,'member_count':len(members),'selected_count':len(expected_files)})
        def validate(stage):
            result=validate_runtime(stage)
            for path,expected in input_hashes.items():
                if sha256(path)!=expected: raise ValueError('MSI/CAB input changed during preparation')
            if sha256(installer)!=expected_sha256: raise ValueError('Installer input changed')
            return {**result,'installer_sha256':expected_sha256,'product':properties['ProductName'],
                    'product_version':version,'platform':template,'cabinets':cabinets,
                    'package_inputs_unchanged':True,'msi_open_mode':'read-only',
                    'installer_executed':False,'msi_installed':False}
        return assemble(plan,outputs,destination,validate=validate)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('installer',type=Path); parser.add_argument('output',type=Path)
    parser.add_argument('--sha256',required=True); parser.add_argument('--version',default='7.2.22')
    args=parser.parse_args()
    try: report=prepare(args.installer,args.output,args.sha256,args.version)
    except (OSError,ValueError) as exc:
        print('Application preparation failed: '+str(exc),file=sys.stderr); return 1
    print(f"Prepared {report['file_count']} application files / {report['total_bytes']} bytes.")
    print('No installer, MSI action, driver or VirtualBox executable was run.')
    return 0

if __name__=='__main__': raise SystemExit(main())
