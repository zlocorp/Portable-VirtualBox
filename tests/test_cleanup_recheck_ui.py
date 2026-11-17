"""UI request eligibility is not elevated cleanup authority; native CI executes policy."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class CleanupRecheckUi(unittest.TestCase):
    def test_retry_ticket_is_action_bound_and_consumed_before_launch(self):
        s=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _MS_CleanupFailureAction(',s)
        self.assertIn('Func _MS_CleanupRetryAction(',s)
        take=s.split('Func _MS_TakeCleanupRetry(',1)[1].split('\nEndFunc',1)[0]
        self.assertLess(take.index('$s["cleanup_retry_action"] = ""'),take.index('_MS_State('))
        run=s.split('Func _MS_RetryCleanup(',1)[1].split('\nEndFunc',1)[0]
        self.assertLess(run.index('_MS_TakeCleanupRetry('),run.index('_MS_Worker('))
        self.assertIn('_MS_Allowed(',run)
        self.assertIn('_PB_Medium()',run)
        self.assertIn('$pending["handle"] <> 0',run)
        self.assertIn('worker-not-confirmed-START-retain-session',run)
        pending=run.split('If $pending["handle"] <> 0 Then',1)[1].split('EndIf',1)[0]
        self.assertNotIn('_MS_State(',pending)
    def test_gui_uses_same_eligibility_and_explains_possible_refusal(self):
        s=(ROOT/'source/ManagerWindow.au3').read_text(encoding='utf-8-sig')
        self.assertIn('_MS_CleanupRetryAction($s)',s)
        self.assertIn('retry_cleanup_hint',s)
        self.assertIn('Retry cleanup checks',s)
        self.assertIn('Повторить проверку',s)
    def test_native_cases_cover_observed_worker_and_double_click(self):
        s=(ROOT/'tests/native/test_manager_session.au3').read_text(encoding='utf-8-sig')
        for marker in ('confirmed harmless worker exit', 'second click cannot create another request', 'post-admission is never inferred safe'):
            self.assertIn(marker,s)

    def test_gate_failure_keeps_an_existing_worker_in_a_polled_phase(self):
        s=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _MS_GateFailureState(',s)
        state=s.split('Func _MS_State(',1)[1].split('EndFunc',1)[0]
        self.assertIn('_MS_GateFailureState(',state)
        tick=s.split('Func _MS_Tick(',1)[1]
        self.assertIn('If _MS_WorkerPhase($state) Then',tick)
        native=(ROOT/'tests/native/test_manager_session.au3').read_text(encoding='utf-8-sig')
        self.assertIn('persistent unknown worker remains polled despite CLI gate failure',native)

    def test_recheck_cancellation_cannot_reopen_cli_or_release_session(self):
        s=(ROOT/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _MS_RecheckCancelled(',s)
        block=s.split('Func _MS_RecheckCancelled(',1)[1].split('EndFunc',1)[0]
        self.assertIn('_MS_State($s, "FAILED"',block)
        self.assertNotIn('CLEANUP_DECLINED',block)
        self.assertNotIn('ReleaseMutex',block)
        tick=s.split('Func _MS_Tick(',1)[1]
        self.assertLess(tick.index('_MS_RecheckCancelled($s)'),tick.index('$worker["exit_code"] = 1223'))
