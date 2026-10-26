"""Structural checks complement, not replace, native/real Manager acceptance."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]

class ManagerSessionContract(unittest.TestCase):
    def test_session_is_a_working_controller_not_a_diagnostic_counter(self):
        path=ROOT/'source/ManagerSession.au3'
        self.assertTrue(path.exists(), 'Missing integrated Manager session controller')
        data=path.read_text(encoding='utf-8-sig')
        for op in ('_MS_Start', '_MS_Stop', '_MS_Tick', '_MS_Reopen'):
            self.assertIn('Func '+op+'(',data)

    def test_real_ui_wires_start_stop_reopen_and_polls_without_waiting_for_vm(self):
        path=ROOT/'source/ManagerWindow.au3'
        self.assertTrue(path.exists(), 'Missing real Manager Start/Stop window')
        text=path.read_text(encoding='utf-8-sig')
        for op in ('_MS_Start(', '_MS_Stop(', '_MS_Reopen(', '_MS_Tick('):
            self.assertIn(op,text)
        self.assertNotIn('ProcessWaitClose(',text)

    def test_native_process_creation_retains_handles_and_never_terminates_by_name(self):
        path=ROOT/'source/ManagedProcess.au3'
        self.assertTrue(path.exists(), 'Missing native process handle implementation')
        data=path.read_text(encoding='utf-8-sig')
        for api in ('CreateProcessW','WaitForSingleObject','CloseHandle','PostMessageW'):
            self.assertIn(api,data)
        for bad in ('ProcessClose(', 'TerminateProcess', 'taskkill', 'WinClose('):
            self.assertNotIn(bad,data)

    def test_close_is_deferred_until_the_window_geometry_is_settled(self):
        source=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _MS_WindowReady(',source)
        self.assertIn('$s["close_posted"]',source)
        self.assertIn('$s["window_key"]',source)
        self.assertIn('_MS_WindowReady(',source)

    def test_exclusion_failure_is_explained_not_left_idle(self):
        source=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('session-lock-create-failed',source)
        self.assertIn('session-lock-result-unknown',source)

    def test_failure_details_preserve_worker_observation_and_exact_exit_code(self):
        source=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('worker-not-confirmed-',source)
        self.assertIn('worker-failed-no-guessed-cleanup-exit-',source)
        self.assertIn('$worker["exit_code"]',source)

    def test_transient_unknown_child_is_reobserved_not_marked_clean(self):
        s=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        for marker in ('worker_uncertain','Func _MS_WorkerUnknownWait(',
                       'If $status == "UNKNOWN" Then',
                       'TimerDiff($s["worker_uncertain"])',
                       'If $status <> "EXITED" Then',
                       '_MP_Release($worker)'):
            self.assertIn(marker,s)
        self.assertLess(s.index('If $status == "UNKNOWN" Then'),
                        s.index('If $status <> "EXITED" Then'))
        self.assertIn('elapsedMs < 5000',s)

    def test_declined_cleanup_has_explicit_exit_and_recover_without_reprompt(self):
        manager=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        window=(ROOT/'source/ManagerWindow.au3').read_text(encoding='utf-8-sig')
        gui=(ROOT/'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _MS_CanLeaveDeclined(',manager)
        self.assertIn('worker-not-confirmed-',manager)
        self.assertIn('worker-still-running-no-cleanup',manager)
        self.assertIn('MsgBox(0x34',window)
        self.assertIn('If $leftOwned Then Return 4',window)
        self.assertIn('If $managerExit = 4 Then Exit 4',gui)
        self.assertIn('Case "leave_declined"',window)
        self.assertNotIn('_MS_State($s, "FAILED", "worker-timeout',manager)

    def test_delayed_oracle_background_never_claims_clean_early(self):
        source=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        gui=(ROOT/'source/ManagerWindow.au3').read_text(encoding='utf-8-sig')
        for marker in ('Func _MS_HostClean(', 'Func _MS_RetryAllowed(',
                       'VERIFYING_CLEAN', 'TimerDiff($s["quiet"]) > 2500',
                       'clean-host-never-stabilized-resources-retained',
                       'existing-or-unknown-VirtualBox'):
            self.assertIn(marker,source)
        self.assertIn('VERIFYING_CLEAN',gui)
        self.assertIn('_MS_RetryAllowed($s["state"], $s["detail"])',gui)

    def test_diagnostic_package_does_not_ship_experimental_system_worker(self):
        import sys
        sys.path.insert(0,str(ROOT/'scripts'))
        from package_preview import MEMBERS
        self.assertFalse(any('Session' in x or x.endswith('.ps1') for x in MEMBERS))

# A Manager-only cycle must not manufacture a VM-boot receipt.
class SessionEvidenceContract(unittest.TestCase):
    def test_cleanup_requires_distinct_bound_quiescence_proof(self):
        s=(ROOT/'scripts/vbox_sup_cleanup.ps1').read_text(encoding='utf-8')
        for marker in ('ParameterSetName="Boot"','ParameterSetName="Session"',
                       'compiled-manager-quiescent-session', 'controller_created',
                       'no_vbox_processes_verified', 'cleanup_basis',
                       'vm_powered_off_before_cleanup=$bootVerified'):
            self.assertIn(marker,s)
        worker=(ROOT/'scripts/manager_session_worker.ps1').read_text(encoding='utf-8')
        self.assertNotIn('startvm_returned_zero=$true',worker)
        self.assertIn('ParentProcessId',worker)
        self.assertIn('already elevated disposable runner',worker)
        self.assertIn('vbox_sup_cleanup.ps1',worker)
        self.assertIn('-QuiescentReport',worker)

if __name__=='__main__': unittest.main()
