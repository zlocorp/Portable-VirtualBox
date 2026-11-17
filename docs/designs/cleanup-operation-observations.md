# Cleanup operation diagnostics, not retry authority

`NOT_ATTEMPTED` previously survived an exception or unavailable/late result after
entering a protected cleanup dispatch. It therefore implied more than the script
knew. Each of the four full-cleanup operations now changes its existing status to
`DISPATCH_ENTERED_OUTCOME_UNKNOWN` immediately before calling its existing
protected or standalone boundary. This means only that the dispatch was entered;
it does not prove child creation or any system mutation.

The additive `operation_observations` map has one entry per existing status key:
`sds_cleanup`, `service_stop`, `driver_package_removal`, `service_delete`.
Each contains:
- `dispatch_entered`: false until immediately before the existing call;
- `within_deadline`: null until a result is returned;
- `exit_code_known`: null until a result is returned, false for unavailable exit;
- `exit_code`: null unless an exit was observed as known, including nonzero/late.

For protected dispatch, result facts are copied before the existing deadline and
known-exit rejection gates. Known results set `EXIT_n`; successful SDS verification
still sets `CLEAN`. Successful report values remain compatible. A standalone
Run-Bounded normal return establishes a within-deadline known exit; an exception
provides no returned result, so its result fields remain null. Earlier pre-dispatch
refusals and later uncalled operations remain `NOT_ATTEMPTED`.

No outcome field is an authorization input. No checks, timeout decisions, effect
ordering, selectors, cleanup markers, retry gates, or command count are changed.
A recorded EXIT_0 with within_deadline=false is not cleanup success. The later partial-cleanup diagnostic increment applies the same observation
semantics to partial recovery without changing effect authorization or replay.
Unknown protected bridge failures are not classified as
"no launch" and never grant permission to repeat an operation.

The new executable fixture extracts the actual report initializer and top-level
try/catch/finally from production using the PowerShell AST. All OS boundaries are
replaced with controlled observations/tripwires. Four operations x six outcomes
(pre-dispatch refusal, dispatch exception, late result, unknown exit, nonzero,
success) x protected/standalone paths verify persisted report content and exact
call prefix. Existing full-script preflight fixture and finalization fixture also
remain required. These tests are not real SCM/PnP or Windows API evidence.

## Partial-recovery diagnostics

The partial-recovery report now records the same four dispatch observations.
For each fixed operation, it marks entry before invoking the existing protected
or standalone call. A returned protected deadline and known exit are recorded
before the existing failure checks; standalone exceptions remain unknown. A
verified SDS unregistration still reports CLEAN, and successful status fields
remain compatible. These fields are diagnostic and never authorize continuation.

When a system-operation error is followed by a report-write error, the exception
reports both failures and retains the first as its inner exception. A failed
report write may leave no report or an incomplete report; it is not a durable
checkpoint and the existing admission proof remains untouched. A report-write
failure after otherwise successful effects still fails the operation. No system
call is repeated, and replay remains refused.

The fixture executes the production report initializer and effect body with all
OS boundaries replaced. It covers four operations and pre-dispatch, thrown, late,
unknown-exit, nonzero and successful outcomes in protected and standalone modes,
as well as Stage, Start and failed-stopped paths. A separate full-script fixture
checks that write failure retains the proof and prevents a second dispatch. These
are local controlled observations, not native Windows system-effect evidence.
Exact-source Windows CI and the existing release gates remain pending.
