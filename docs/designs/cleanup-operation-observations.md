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
A recorded EXIT_0 with within_deadline=false is not cleanup success. Partial cleanup
is outside this change. Unknown protected bridge failures are not classified as
"no launch" and never grant permission to repeat an operation.

The new executable fixture extracts the actual report initializer and top-level
try/catch/finally from production using the PowerShell AST. All OS boundaries are
replaced with controlled observations/tripwires. Four operations x six outcomes
(pre-dispatch refusal, dispatch exception, late result, unknown exit, nonzero,
success) x protected/standalone paths verify persisted report content and exact
call prefix. Existing full-script preflight fixture and finalization fixture also
remain required. These tests are not real SCM/PnP or Windows API evidence.
