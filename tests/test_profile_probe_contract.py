"""Static contract for isolated configuration smoke without starting any VM."""
from pathlib import Path
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'scripts/vbox_profile_probe.ps1'

class PortableProfileContract(unittest.TestCase):
    def test_only_disposable_host_and_profile(self):
        text=SCRIPT.read_text(encoding='utf-8')
        for phrase in ('GITHUB_ACTIONS','GITHUB_REPOSITORY','VBOX_USER_HOME',
                       'machinefolder','createvm','--register',
                       '--platform-architecture=x86','list','VirtualBox.xml',
                       '.vbox','WaitForExit'):
            self.assertIn(phrase,text)
    def test_no_unscoped_host_mutation(self):
        text=SCRIPT.read_text(encoding='utf-8').lower()
        for phrase in ('taskkill','msiexec','stop-service','remove-service','startvm','virtualboxvm.exe'):
            self.assertNotIn(phrase,text)
if __name__=='__main__': unittest.main()
