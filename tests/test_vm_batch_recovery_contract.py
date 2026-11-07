"""Read-only batch recovery must never be confused with repair authority."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

class BatchRecoveryContract(unittest.TestCase):
    def get(self,path):
        return (ROOT/path).read_text(encoding='utf-8-sig')

    def test_readonly_reconciliation_reuses_proven_backup_and_uuid_evidence(self):
        code=self.get('source/PortableVmBatchRecovery.au3')
        for required in ('Func _PVB_Reconcile(', '_PBK_Verify(', '_PVR_DataMatches(',
                         '_PVB_Plan(', '_PVI_RegistryEntries(', '_PVR_StaleSource(',
                         '_PVI_RegistryTarget(', '_PBK_Hash(', '_PVI_Inspect(',
                         'STALE', 'ABSENT', 'LOCAL', 'REVIEW_ONLY', 'COMPLETE'):
            self.assertIn(required,code)
        active='\n'.join(x for x in code.splitlines() if not x.lstrip().startswith(';'))
        for forbidden in ('unregistervm ', 'registervm ', 'VBoxManage.exe', 'FileDelete(',
                          'FileWrite(', 'RegWrite(', 'Run(', 'RunWait(', 'ProcessClose('):
            self.assertNotIn(forbidden,active)

    def test_transition_model_checks_only_one_uuid_change(self):
        code=self.get('source/PortableVmBatchRecovery.au3')
        native=self.get('tests/native/test_vm_batch_recovery.au3')
        self.assertIn('Func _PVB_TransitionValid(',code)
        self.assertIn('$states[$uuid] = $state', code)
        for key in ('origin_sha256', 'manifest_sha256', 'statesBefore', 'statesAfter',
                    '$statesBefore[$uuid] <> $from', '$statesAfter[$uuid] <> $to',
                    '$key <> $uuid And $statesBefore[$key] <> $statesAfter[$key]'):
            self.assertIn(key,code)
        for case in ('only first unregister transition is valid',
                     'only first register transition is valid',
                     'skipped unregister observation is not a transaction',
                     'only second unregister transition is valid',
                     'only second register transition is valid',
                     'completed transaction may not regress to stale'):
            self.assertIn(case,native)

    def test_model_refuses_forged_counts_order_paths_and_skipped_recovery(self):
        code=self.get('source/PortableVmBatchRecovery.au3')
        native=self.get('tests/native/test_vm_batch_recovery.au3')
        for key in ('Func _PVB_StateConsistent(', '$r["paths"] = $paths',
                    '$r["order"] = $order', 'UBound($stateKeys) <> $r["count"]',
                    'UBound($pathKeys) <> $r["count"]',
                    '$countStale <> $r["stale"]', '$countAbsent <> $r["absent"]',
                    '$r["next_action"] <> $expectedAction',
                    '$before["next_uuid"] <> $uuid',
                    '$pathsBefore[$key] <> $pathsAfter[$key]',
                    '$orderBefore[$i] <> $orderAfter[$i]'):
            self.assertIn(key,code)
        for desc in ('forged state count is rejected','premature COMPLETE is rejected',
                     'forged next step target is rejected',
                     'additional unseen state UUID is rejected',
                     'reordered original UUID schedule is rejected',
                     'changed VM target path is rejected',
                     'must recover ABSENT before unregistering another VM'):
            self.assertIn(desc,native)

    def test_each_transition_binds_before_after_registry_and_all_vm_config_hashes(self):
        code=self.get('source/PortableVmBatchRecovery.au3')
        native=self.get('tests/native/test_vm_batch_recovery.au3')
        for key in ('current_registry_sha256', 'config_sha256',
                    '$r["current_registry_sha256"] = $registryBefore',
                    '$configHashes[$uuid] = $currentHash',
                    '$hashesBefore[$key] <> $hashesAfter[$key]',
                    '$before["current_registry_sha256"] == $after["current_registry_sha256"]'):
            self.assertIn(key,code)
        for key in ('forged unchanged registry hash is rejected',
                    'forged VM configuration hash is rejected',
                    'malformed registry SHA-256 is rejected',
                    'successful unregister changes observed registry SHA-256'):
            self.assertIn(key,native)

    def test_complete_trace_requires_all_strict_ordered_snapshots(self):
        code=self.get('source/PortableVmBatchRecovery.au3')
        native=self.get('tests/native/test_vm_batch_recovery.au3')
        self.assertIn('Func _PVB_TraceValid(',code)
        self.assertIn('_PVB_StateConsistent($observations[0])',code)
        self.assertIn('_PVB_TransitionValid($observations[$i], $observations[$i + 1]',code)
        self.assertIn('If $requireComplete Then Return $last["status"] == "COMPLETE"',code)
        for marker in ('complete ordered transition trace accepted',
                       'initial verified snapshot may be inspected',
                       'no-step trace is never a completed batch',
                       'interrupted first unregister trace is inspectable',
                       'interrupted trace cannot claim complete',
                       'trace with skipped register is rejected',
                       'replayed unregister transition is rejected',
                       'out-of-order UUID step is rejected',
                       'trace without original stale baseline is rejected',
                       'incomplete UUID event list is rejected'):
            self.assertIn(marker,native)

    def test_public_cli_is_readonly(self):
        entry=self.get('source/Portable-VirtualBox.au3')
        self.assertIn('PortableVmBatchRecovery.au3',entry)
        self.assertIn('Case "--review-multi-vm-rebind"',entry)
        self.assertIn('_PVB_Reconcile(@ScriptDir, $CmdLine[$iFirst + 1])',entry)
        self.assertIn('BACKUP_ONLY',self.get('source/PortableVmBatchPlan.au3'))

    def test_native_and_compiled_cross_interruption_cases(self):
        native=self.get('tests/native/test_vm_batch_recovery.au3')
        for key in ('two stale registrations', 'first unregister interrupted',
                    'first registration completed', 'second unregister interrupted',
                    'all machines local and complete', 'unknown registration refused',
                    'changed virtual disk refused', 'original backup unchanged'):
            self.assertIn(key,native)
        ps=self.get('scripts/check_vm_rebind_plan.ps1')
        for marker in ('batch-recovery-stale', 'batch-recovery-after-first-unregister',
                       'batch-recovery-one-complete', 'batch-recovery-finished',
                       'batch-recovery-foreign-uuid', 'batch-recovery-media-changed'):
            self.assertIn(marker,ps)

if __name__=='__main__': unittest.main()
