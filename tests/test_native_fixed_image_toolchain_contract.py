"""Pinned reference metadata provisioning; no downloaded code is executed."""
import hashlib
import io
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parent))
import prepare_native_fixed_image_toolchain as toolchain

ROOT=Path(__file__).resolve().parents[1]
NAMES=('mscorlib.dll','System.dll','System.Core.dll','System.Security.dll')


def fixture(missing=None,duplicate=None,symlink=None,wrong=None):
    contents={name:('synthetic reference '+name).encode() for name in NAMES}
    output=io.BytesIO()
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        for name in NAMES:
            if name==missing: continue
            member='build/.NETFramework/v4.8/'+name
            info=zipfile.ZipInfo(member)
            if name==symlink:
                info.create_system=3;info.external_attr=(stat.S_IFLNK|0o777)<<16
            archive.writestr(info,b'wrong bytes' if name==wrong else contents[name])
        if duplicate:
            # Avoid a duplicate-name writer warning while still producing duplicate entries.
            info=zipfile.ZipInfo('build/.NETFramework/v4.8/'+duplicate)
            archive.filelist.append(archive.getinfo(info.filename))
        archive.writestr('../../outside.txt',b'must never extract')
        archive.writestr('tools/unrequested.exe',b'must never execute or extract')
    raw=output.getvalue()
    hashes={name:hashlib.sha256(value).hexdigest() for name,value in contents.items()}
    return raw,contents,hashes


class FixedImageToolchainContracts(unittest.TestCase):
    def configured(self,raw,hashes):
        return mock.patch.multiple(toolchain,PACKAGE_SHA256=hashlib.sha256(raw).hexdigest(),REFERENCE_SHA256=hashes)

    def test_exact_source_pins(self):
        self.assertEqual(toolchain.PACKAGE_URL,'https://api.nuget.org/v3-flatcontainer/microsoft.netframework.referenceassemblies.net48/1.0.3/microsoft.netframework.referenceassemblies.net48.1.0.3.nupkg')
        self.assertEqual(toolchain.PACKAGE_SHA256,'8a7e348538e7eb91351696911689f49e3d4f63f8bab517432bbe159b8b1104a2')
        self.assertEqual(tuple(toolchain.REFERENCE_SHA256),NAMES)
        for digest in toolchain.REFERENCE_SHA256.values(): self.assertRegex(digest,r'\A[0-9a-f]{64}\Z')

    def test_extracts_only_exact_pinned_regular_references(self):
        raw,contents,hashes=fixture()
        with tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
            parent=Path(temporary);package=parent/'package';package.write_bytes(raw)
            result=toolchain.prepare(parent/'owned',package)
            self.assertEqual(result,parent/'owned/references')
            self.assertEqual({p.name:p.read_bytes() for p in result.iterdir()},contents)
            self.assertFalse((parent/'outside.txt').exists())
            self.assertFalse((parent/'owned/tools').exists())

    def test_download_is_fixed_bounded_and_verified_before_use(self):
        raw,contents,hashes=fixture()
        with tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
            with mock.patch.object(toolchain,'urlopen',return_value=io.BytesIO(raw)) as opening:
                result=toolchain.prepare(Path(temporary)/'owned')
                opening.assert_called_once_with(toolchain.PACKAGE_URL,timeout=60)
                self.assertEqual(result.joinpath('System.dll').read_bytes(),contents['System.dll'])
        with tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
            root=Path(temporary)/'owned'
            with mock.patch.object(toolchain,'MAX_PACKAGE_BYTES',len(raw)-1),mock.patch.object(toolchain,'urlopen',return_value=io.BytesIO(raw)):
                with self.assertRaises(ValueError): toolchain.prepare(root)
            self.assertFalse((root/'references').exists())
            self.assertLessEqual((root/'reference-pack.nupkg').stat().st_size,len(raw)-1,
                                 'Oversized download chunks must be refused before writing')

    def test_wrong_package_digest_fails_before_zip_or_reference_output(self):
        raw,_,_=fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)/'owned';package=Path(temporary)/'package';package.write_bytes(raw)
            with mock.patch.object(toolchain.zipfile,'ZipFile',side_effect=AssertionError('must verify first')):
                with self.assertRaises(ValueError): toolchain.prepare(root,package)
            self.assertFalse((root/'references').exists())

    def test_missing_duplicate_symlink_and_wrong_reference_are_refused(self):
        for problem in ('missing','duplicate','symlink','wrong'):
            with self.subTest(problem=problem):
                raw,_,hashes=fixture(**{problem:'System.dll'})
                with tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
                    root=Path(temporary)/'owned';package=Path(temporary)/'package';package.write_bytes(raw)
                    with self.assertRaises(ValueError): toolchain.prepare(root,package)
                    self.assertFalse((root/'references').exists(),'Validate every required DLL before exporting any references')

    def test_local_package_and_reference_size_bounds(self):
        raw,_,hashes=fixture()
        for limit in ('MAX_PACKAGE_BYTES','MAX_REFERENCE_BYTES'):
            with self.subTest(limit=limit),tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
                root=Path(temporary)/'owned';package=Path(temporary)/'package';package.write_bytes(raw)
                with mock.patch.object(toolchain,limit,1):
                    with self.assertRaises(ValueError): toolchain.prepare(root,package)
                self.assertFalse((root/'references').exists())

    def test_existing_destination_is_never_overwritten(self):
        raw,_,hashes=fixture()
        with tempfile.TemporaryDirectory() as temporary,self.configured(raw,hashes):
            root=Path(temporary)/'owned';root.mkdir();(root/'preserved').write_text('existing')
            package=Path(temporary)/'package';package.write_bytes(raw)
            with self.assertRaises(FileExistsError): toolchain.prepare(root,package)
            self.assertEqual((root/'preserved').read_text(),'existing')

    def test_failure_prints_no_exportable_reference_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            package=Path(temporary)/'wrong-package';package.write_bytes(b'invalid')
            argv=['prepare','--directory',str(Path(temporary)/'owned'),'--package',str(package)]
            with mock.patch.object(sys,'argv',argv),mock.patch('sys.stdout',new_callable=io.StringIO) as output,mock.patch('sys.stderr',new_callable=io.StringIO) as error:
                self.assertEqual(toolchain.main(),1)
                self.assertEqual(output.getvalue(),'')
                self.assertIn('SHA-256 differs from source pin',error.getvalue())

    def test_output_path_cannot_inject_extra_environment_lines(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError): toolchain.prepare(Path(temporary)/'new\nINJECTED=value')
            self.assertEqual(list(Path(temporary).iterdir()),[])

    def test_workflow_provisions_before_mandatory_managed_tests(self):
        workflow=(ROOT/'.github/workflows/ci.yml').read_text()
        audit=workflow.split('  audit:',1)[1].split('  compile:',1)[0]
        setup=audit.index('Prepare pinned net48 references for managed contracts')
        tests=audit.index('Unit tests for audit')
        self.assertLess(setup,tests)
        between=audit[setup:tests]
        self.assertIn('python3 tests/prepare_native_fixed_image_toolchain.py --directory',between)
        self.assertIn('PVBOX_TEST_NET48_REFERENCES',between)
        self.assertIn('"$GITHUB_ENV"',between)
        self.assertIn('python3 -m unittest discover -s tests -v',audit[tests:])
        self.assertNotIn('continue-on-error',audit[:audit.index('Check official Oracle manifest')])


if __name__=='__main__': unittest.main()
