# SYSTEM cleanup outcomes model implementation plan

> For agentic workers: use the repository test-first workflow; this task is an
> explicitly assigned internal implementation, with parent review before publishing.

**Goal:** executable non-authorizing SYSTEM outcome specification.
**Architecture:** pure typed-event inspector plus fault-injected in-memory writer;
no production integration, serialization parser or effect dispatch.
**Tech stack:** Python standard library, unittest.
**Spec:** `docs/designs/system-cleanup-outcomes.md`.

## Constraints and review focus

Only this plan, that design, `tests/system_cleanup_outcomes_model.py` and
`tests/test_system_cleanup_outcomes.py` may change. No native effects, user Windows,
commit/push, merge/release, multi-VM, USB or updater. Review malformed evidence,
uncertain writes, misleading absence, replacement resources and incomplete lineage.
All decision results must explicitly deny mutation authority.

## Task: model outcome inspection

- [x] Write failing tests for repeat validation, missing history, NO_EFFECTS lineage,
  restart prefixes, fresh postconditions, uncertain children, malformed ordering,
  exhaustive bounded sequences, and each simulated writer fault boundary.
- [x] Run `python3 -m unittest discover -s tests -p test_system_cleanup_outcomes.py -v`.
  Observe assertion failures for the missing reference model before implementation.
- [x] Implement immutable Binding/Record/Result values, `validate(observations)`,
  `inspect(records, binding, *, fresh, trusted_no_launch, complete_lineage)` and
  `SimulatedWriter.append(record, *, fault)` / `inspect()` in the test-only module.
  Expose no native operation or continuation API.
- [x] Run targeted tests and the full `python3 -m unittest discover -s tests -v` suite.
- [x] Review four-file diff; report evidence/limits to parent without commit/push.

## Verification record

- Initial red: 11 expected missing-model assertion failures, before implementation.
- Malformed-field red: 1 expected failure (a non-string equality impostor was
  classified UNKNOWN instead of INVALID), before strict field validation.
- Final targeted green: 12 tests pass, including 781 short event sequences and
  36 simulated fault boundaries.
- Full suite: 307 tests, OK, 11 platform-specific skips. No Windows run claimed.
- `git diff --check` passes. Only the four assigned files were created by this
  worker; parent-owned security documentation changes were left untouched.
- No commits or pushes performed. Independent parent review remains required.

## Review follow-up

- Malformed-observation regression red: 13 failing subcases in one new test,
  including equality impostors and string subclasses satisfying predicates.
  Strict tuple length and exact bounded string checks now precede comparisons.
- Package-targeted invocation initially failed with 13 import errors; import now
  uses the test package when present and standalone module otherwise, without
  modifying sys.path.
- Follow-up verification uses `PVBOX_TEST_POWERSHELL=/tmp/pvbox-pwsh/pwsh`,
  `XDG_CACHE_HOME=/tmp/pvbox-pwsh-cache`, and
  `XDG_CONFIG_HOME=/tmp/pvbox-pwsh-config`. Focused discover and package invocation:
  13 tests pass each. Full suite: 308 tests, OK, 6 platform-specific skips.
