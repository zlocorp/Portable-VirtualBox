"""Executable specification; no native effects or continuation adapter."""
import importlib
import itertools
from pathlib import Path
import unittest

class SystemCleanupOutcomes(unittest.TestCase):
    def setUp(self):
        self.assertTrue(Path(__file__).with_name('system_cleanup_outcomes_model.py').exists(),
                        'Missing non-authorizing SYSTEM cleanup reference model')
        self.m = importlib.import_module(
            '.system_cleanup_outcomes_model' if __package__ else 'system_cleanup_outcomes_model',
            package=__package__ or None)
        self.binding = self.m.Binding(*('test-' + str(i) for i in range(10)))
    def record(self, kind, step=None, **kw):
        return self.m.Record(self.binding, kind, step, **kw)
    def history(self):
        rows = [self.record('ADMIT')]
        for step in self.m.STEPS:
            rows += [self.record('BEGIN', step), self.record('SUCCESS', step,
                     child='EXITED_ZERO', postcondition='VERIFIED')]
        return rows + [self.record('COMPLETE')]
    def inspect(self, rows, **kw):
        r = self.m.inspect(tuple(rows), self.binding, **kw)
        self.assertIs(r.mutation_authorized, False)
        return r
    def test_validation_is_repeatable_not_admission(self):
        observations = ('PRESENT',) * 5
        for _ in range(3):
            r = self.m.validate(observations)
            self.assertEqual(r.status, 'VALIDATION_ELIGIBLE')
            self.assertIs(r.mutation_authorized, False)
        self.assertEqual(observations, ('PRESENT',) * 5)
        for state in ('ABSENT', 'UNKNOWN', 'ERROR', 'DELETE_PENDING'):
            self.assertEqual(self.m.validate((state,) * 5).status, 'INSPECTION_REQUIRED')
    def test_missing_history_is_not_no_attempt_proof(self):
        self.assertEqual(self.inspect([]).status, 'INSPECTION_REQUIRED')
    def test_no_effects_needs_trusted_executor_and_complete_lineage(self):
        rows = [self.record('ADMIT'), self.record('NO_EFFECTS')]
        for trusted, lineage in itertools.product((False, True), repeat=2):
            r = self.inspect(rows, trusted_no_launch=trusted, complete_lineage=lineage)
            self.assertEqual(r.status, 'VALIDATION_ELIGIBLE' if trusted and lineage else 'INSPECTION_REQUIRED')
        self.assertEqual(self.inspect(rows + [self.record('ADMIT')]).status, 'INVALID')
        self.assertEqual(self.inspect(self.history()[:2] + [self.record('NO_EFFECTS')]).status, 'INVALID')
    def test_restart_never_authorizes_next_resource(self):
        rows = self.history()
        for n in range(1, len(rows)):
            r = self.inspect(rows[:n], fresh=('ABSENT',) * 5)
            self.assertEqual(r.status, 'UNKNOWN' if n % 2 == 0 else 'INSPECTION_REQUIRED')
        r = self.inspect(rows[:3], fresh=('MATCH', 'PRESENT', 'PRESENT', 'PRESENT', 'PRESENT'))
        self.assertEqual(r.observationally_completed, (self.m.STEPS[0],))
        self.assertEqual(r.status, 'INSPECTION_REQUIRED')
    def test_completion_is_diagnostic_and_needs_fresh_postconditions(self):
        rows = self.history()
        for state in ('PRESENT', 'ABSENT', 'UNKNOWN', 'ERROR', 'DELETE_PENDING'):
            self.assertEqual(self.inspect(rows, fresh=(state,) * 5).status, 'INSPECTION_REQUIRED')
        self.assertEqual(self.inspect(rows, fresh=('MATCH',) * 5).status, 'DIAGNOSTIC_COMPLETE')
        self.assertFalse(hasattr(self.inspect(rows), 'payload_checkpoint'))
    def test_uncertain_child_or_postcondition_is_unknown(self):
        for child, post in itertools.product(('NONZERO', 'TIMEOUT', 'LAUNCH_EXCEPTION', 'UNKNOWN', 'EXITED_ZERO'),
                                             ('UNKNOWN', 'VERIFIED')):
            if (child, post) == ('EXITED_ZERO', 'VERIFIED'): continue
            rows = self.history()[:2] + [self.record('SUCCESS', self.m.STEPS[0], child=child, postcondition=post)]
            self.assertEqual(self.inspect(rows).status, 'UNKNOWN')
    def test_invalid_order_duplicate_foreign_oversize_records_fail(self):
        rows = self.history()
        bad = [rows[1:], rows + [rows[-1]], [rows[0], rows[2]],
               [rows[0], self.record('BEGIN', 'wrong')], [rows[0], self.record('COMPLETE')],
               [object()], rows * 10,
               [self.m.Record(self.m.Binding(*('foreign' for _ in range(10))), 'ADMIT')],
               [self.record('ADMIT', self.m.STEPS[0])], [self.record('WAT')]]
        for candidate in bad:
            self.assertEqual(self.inspect(candidate).status, 'INVALID')
    def test_all_bounded_event_prefixes_are_non_authorizing(self):
        alphabet = [self.record('ADMIT'), self.record('BEGIN', self.m.STEPS[0]),
                    self.record('SUCCESS', self.m.STEPS[0], child='EXITED_ZERO', postcondition='VERIFIED'),
                    self.record('NO_EFFECTS'), self.record('COMPLETE')]
        for length in range(5):
            for rows in itertools.product(alphabet, repeat=length):
                self.inspect(rows, fresh=('MATCH',) * 5, trusted_no_launch=True, complete_lineage=True)
    def test_every_writer_fault_boundary_poisons_without_progress(self):
        for cut in range(len(self.history())):
            for fault in ('WRITE', 'FLUSH', 'READBACK'):
                writer = self.m.SimulatedWriter(self.binding)
                for row in self.history()[:cut]:
                    self.assertEqual(writer.append(row).status, 'RECORDED')
                before = writer.records
                result = writer.append(self.history()[cut], fault=fault)
                self.assertEqual(result.status, 'POISONED')
                self.assertIs(result.mutation_authorized, False)
                self.assertEqual(writer.records, before)
                self.assertEqual(writer.append(self.history()[cut]).status, 'POISONED')
                self.assertEqual(writer.inspect().status, 'UNKNOWN')
    def test_writer_rejects_invalid_without_recording(self):
        writer = self.m.SimulatedWriter(self.binding)
        self.assertEqual(writer.append(self.record('COMPLETE')).status, 'INVALID')
        self.assertEqual(writer.records, ())
        self.assertEqual(writer.append(self.record('ADMIT')).status, 'RECORDED')
        self.assertEqual(writer.append(self.record('NO_EFFECTS')).status, 'RECORDED')
        self.assertEqual(writer.append(self.record('BEGIN', self.m.STEPS[0])).status, 'INVALID')
    def test_malformed_fields_bindings_and_contradictory_metadata(self):
        from dataclasses import replace
        class Impostor:
            def __eq__(self, other): return True
            def __ne__(self, other): return False
        for value in (True, 7, None, '', 'x' * 513):
            wrong = replace(self.binding, helper=value)
            self.assertEqual(self.m.inspect((), wrong).status, 'INVALID')
        for field in self.binding.__dataclass_fields__:
            foreign = replace(self.binding, **{field: 'changed'})
            self.assertEqual(self.inspect([self.m.Record(foreign, 'ADMIT')]).status, 'INVALID')
        for value in (True, 7, Impostor(), 'x' * 513):
            self.assertEqual(self.inspect([self.record('ADMIT'), self.record('BEGIN', value)]).status, 'INVALID')
        for kind in ('ADMIT', 'BEGIN', 'COMPLETE', 'NO_EFFECTS'):
            self.assertEqual(self.inspect([self.record(kind, child='EXITED_ZERO')]).status, 'INVALID')
        for field in ('child', 'postcondition'):
            bad = replace(self.history()[2], **{field: Impostor()})
            self.assertEqual(self.inspect(self.history()[:2] + [bad]).status, 'INVALID')

    def test_malformed_observations_never_satisfy_predicates(self):
        class Impostor:
            def __eq__(self, other): return True
        class Text(str): pass
        for good in ('PRESENT', 'MATCH'):
            invalid = [None, True, 1, Impostor(), Text(good), '', 'x' * 513]
            candidates = [(value,) * 5 for value in invalid]
            candidates += [(good,) * size for size in (0, 4, 6, 513)]
            candidates += [[good] * 5, good, None]
            candidates += [(good,) * 4 + (value,) for value in invalid]
            for observations in candidates:
                with self.subTest(good=good, observations=repr(observations)):
                    result = self.m.validate(observations)
                    self.assertIs(result.mutation_authorized, False)
                    self.assertEqual(result.status, 'INSPECTION_REQUIRED')
                    result = self.inspect(self.history(), fresh=observations)
                    self.assertEqual(result.status, 'INSPECTION_REQUIRED')
                    self.assertEqual(result.observationally_completed, ())

    def test_no_effect_sink_or_recovery_dispatch(self):
        import inspect
        self.assertEqual(tuple(inspect.signature(self.m.inspect).parameters),
                         ('records', 'binding', 'fresh', 'trusted_no_launch', 'complete_lineage'))
        self.assertFalse(hasattr(self.m, 'resume'))
        self.assertFalse(hasattr(self.m, 'execute'))

if __name__ == '__main__': unittest.main()
