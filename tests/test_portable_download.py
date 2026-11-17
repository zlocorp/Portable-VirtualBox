"""Pinned official online first-run retrieval without Oracle execution or overwrite."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
import portable_prepare as pp


class PinnedOnlineSetup(TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/"Portable USB"; self.root.mkdir()

    def test_official_download_pinned_then_prepared_and_cleaned(self):
        seen=[]
        def downloader(url,dest,expected):
            seen.append((url,expected))
            Path(dest).write_bytes(b"fake-download")
        with patch.object(pp,"offline_prepare",return_value={
                "file_count":pp.FILE_COUNT,"total_bytes":pp.TOTAL_BYTES}) as prepare:
            pp.online_prepare(self.root,downloader=downloader,require_windows=False)
        self.assertEqual(seen,[(pp.OFFICIAL_URL,pp.PINNED_SHA256)])
        args=prepare.call_args.args
        self.assertEqual(args[1],self.root)
        self.assertEqual(args[0].name,pp.INSTALLER)
        self.assertFalse(args[0].exists())
        self.assertEqual(list(self.root.iterdir()),[])

    def test_download_failure_preserves_absence_of_app64(self):
        def downloader(url,dest,expected):
            Path(dest).write_bytes(b"incomplete")
            raise OSError("network aborted")
        with self.assertRaisesRegex(OSError,"network aborted"):
            pp.online_prepare(self.root,downloader=downloader,require_windows=False)
        self.assertEqual(list(self.root.iterdir()),[])

    def test_progress_file_is_one_shot_reserved_and_cleaned(self):
        name = ".pvbox-setup-123-20261025123456-1.progress"
        status = self.root/name
        with pp.ProgressFile(self.root, status) as report:
            report.update("DOWNLOAD", 1048576, 2097152)
            self.assertEqual(status.read_text(), "DOWNLOAD|1048576|2097152\n")
            with self.assertRaises(FileExistsError):
                with pp.ProgressFile(self.root, status):
                    pass
        self.assertFalse(status.exists())
        with self.assertRaises(ValueError):
            pp.ProgressFile(self.root, self.root.parent/"outside.progress")

    def test_online_progress_reports_download_and_extract_and_cleans_on_error(self):
        phases=[]
        class Reporter:
            def update(self, phase, done=0, total=0):
                phases.append((phase, done, total))
        def download(url, dest, sha, *, progress):
            self.assertEqual((url,sha),(pp.OFFICIAL_URL,pp.PINNED_SHA256))
            progress(2,4)
            Path(dest).write_bytes(b"fixture")
        with patch.object(pp,"download_verified",side_effect=download), \
             patch.object(pp,"offline_prepare",return_value={"file_count":185,"total_bytes":247834716}):
            pp.online_prepare(self.root,require_windows=False,progress=Reporter())
        self.assertIn(("DOWNLOAD",2,4),phases)
        self.assertEqual(phases[0][0],"DOWNLOAD")
        self.assertEqual(list(self.root.iterdir()),[])

    def test_existing_app64_blocks_download_before_network(self):
        app=self.root/"app64"; app.mkdir()
        (app/"VM.vdi").write_text("keep")
        def downloader(*args): self.fail("Network must never be called")
        with self.assertRaises(FileExistsError):
            pp.online_prepare(self.root,downloader=downloader,require_windows=False)
        self.assertEqual((app/"VM.vdi").read_text(),"keep")


if __name__=="__main__": main()
