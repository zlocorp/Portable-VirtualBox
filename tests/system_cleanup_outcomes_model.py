"""TEST ONLY: abstract SYSTEM outcomes, never native authority or durability.

Trusted-no-launch/lineage inputs are hypothetical premises, not authentication.
No function performs effects, parses files, issues capabilities or resumes work.
"""
from dataclasses import dataclass, field, fields

STEPS = ('SDS_UNREGISTER', 'DRIVER_STOP', 'EXACT_PACKAGE_REMOVE',
         'CONDITIONAL_RESIDUAL_DELETE', 'TERMINAL_VERIFY')
MAX_RECORDS = 2 + 2 * len(STEPS)


@dataclass(frozen=True)
class Binding:
    build: str
    helper: str
    frontend: str
    root: str
    session: str
    sid: str
    original_controller_generation: str
    initiating_controller_generation: str
    receipt_digests: str
    plan_digest: str


@dataclass(frozen=True)
class Record:
    binding: Binding
    kind: str
    step: str | None = None
    child: str | None = None
    postcondition: str | None = None


@dataclass(frozen=True)
class Result:
    status: str
    observationally_completed: tuple = ()
    mutation_authorized: bool = field(default=False, init=False)


def _binding_valid(binding):
    return type(binding) is Binding and all(
        type(getattr(binding, f.name)) is str and 0 < len(getattr(binding, f.name)) <= 512
        for f in fields(Binding))


def _observations_valid(observations):
    return (type(observations) is tuple and len(observations) == len(STEPS) and
            all(type(value) is str and 0 < len(value) <= 512 for value in observations))


def validate(observations):
    """Repeatable read-only preflight predicate, not proof of no prior attempt."""
    ready = _observations_valid(observations) and observations == ('PRESENT',) * len(STEPS)
    return Result('VALIDATION_ELIGIBLE' if ready else 'INSPECTION_REQUIRED')


def inspect(records, binding, *, fresh=(), trusted_no_launch=False, complete_lineage=False):
    """Inspect hypothetical evidence only; no way to reach an effect sink."""
    if (not _binding_valid(binding) or type(records) is not tuple or
            len(records) > MAX_RECORDS):
        return Result('INVALID')
    admitted = False
    pending = None
    completed = []
    terminal = None
    uncertain = False
    for row in records:
        if (type(row) is not Record or not _binding_valid(row.binding) or row.binding != binding or
                terminal is not None or uncertain):
            return Result('INVALID')
        if any(value is not None and (type(value) is not str or len(value) > 512)
               for value in (row.step, row.child, row.postcondition)):
            return Result('INVALID')
        if type(row.kind) is not str or row.kind not in ('ADMIT', 'BEGIN', 'SUCCESS', 'COMPLETE', 'NO_EFFECTS'):
            return Result('INVALID')
        if row.kind != 'SUCCESS' and (row.child is not None or row.postcondition is not None):
            return Result('INVALID')
        if row.kind in ('ADMIT', 'COMPLETE', 'NO_EFFECTS') and row.step is not None:
            return Result('INVALID')
        if not admitted:
            if row.kind != 'ADMIT':
                return Result('INVALID')
            admitted = True
        elif row.kind == 'BEGIN':
            if pending is not None or len(completed) == len(STEPS) or row.step != STEPS[len(completed)]:
                return Result('INVALID')
            pending = row.step
        elif row.kind == 'SUCCESS':
            if pending is None or row.step != pending:
                return Result('INVALID')
            if (row.child not in ('EXITED_ZERO', 'NONZERO', 'TIMEOUT', 'LAUNCH_EXCEPTION', 'UNKNOWN') or
                    row.postcondition not in ('VERIFIED', 'UNKNOWN')):
                return Result('INVALID')
            if row.child != 'EXITED_ZERO' or row.postcondition != 'VERIFIED':
                uncertain = True
            else:
                completed.append(pending)
                pending = None
        elif row.kind == 'NO_EFFECTS':
            if pending is not None or completed:
                return Result('INVALID')
            terminal = row.kind
        elif row.kind == 'COMPLETE':
            if pending is not None or len(completed) != len(STEPS):
                return Result('INVALID')
            terminal = row.kind
        else:
            return Result('INVALID')
    matching = ()
    if _observations_valid(fresh):
        matching = tuple(step for index, step in enumerate(completed) if fresh[index] == 'MATCH')
    if pending is not None or uncertain:
        return Result('UNKNOWN', matching)
    if terminal == 'NO_EFFECTS' and trusted_no_launch is True and complete_lineage is True:
        return Result('VALIDATION_ELIGIBLE')
    if terminal == 'COMPLETE' and len(matching) == len(STEPS):
        return Result('DIAGNOSTIC_COMPLETE', matching)
    return Result('INSPECTION_REQUIRED', matching)


class SimulatedWriter:
    """Acknowledged-prefix simulation only. No real storage/flush operations.

    Faults might leave unacknowledged data on real storage. Never infer the
    stored tail from records, or discard this instance's poison on inspection.
    """
    def __init__(self, binding):
        self._binding = binding
        self._records = ()
        self._poisoned = False

    @property
    def records(self):
        return self._records

    def append(self, record, *, fault=None):
        if self._poisoned:
            return Result('POISONED')
        candidate = self._records + (record,)
        if inspect(candidate, self._binding).status == 'INVALID':
            return Result('INVALID')
        if fault is not None:
            self._poisoned = True
            return Result('POISONED')
        # Abstract WRITE -> FLUSH -> READBACK have all succeeded here.
        self._records = candidate
        return Result('RECORDED')

    def inspect(self):
        if self._poisoned:
            return Result('UNKNOWN')
        return inspect(self._records, self._binding)
