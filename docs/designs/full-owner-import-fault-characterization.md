# Full-owner import-boundary fault characterization (test only)

## Scope and honest claim

Compile all production method bodies unchanged; execute Run/RunCore/Prepare and
the applicable ObserveAndWait/RetainUnknown branches with real Windows pipes,
readers, image lease and a genuinely
CreateProcess-created harmless built-in PowerShell child. Instrument only selected
P/Invoke declarations in a temporary compilation. This is synthetic adapter
failure evidence through unchanged production control flow, NOT an unchanged
shipped binary, a natural contradictory Windows result, or system retry authority.

Production source/build inputs remain unchanged. The generator requires exactly
one occurrence of each complete declared replacement, permits only class `partial`
and native import renames with explicit original EntryPoint, then reverses every
replacement and requires byte identity with the input. Emit source/generated hashes
and a bounded manifest. Native wrapper and harness live only under tests; generated
sources/EXEs remain runner-temp and cannot enter package or helper inventories.

## Three scoped cases

1. Real CreateProcess TRUE with actual original handles. The wait wrapper probes
   that exact original handle with real zero-time wait (must be WAIT_TIMEOUT),
   then reports synthetic WAIT_FAILED to the owner. No handle is closed/reopened
   or deprived of access. Native returned failure is not claimed.
2. Real CreateProcess TRUE with actual original handles, but the create wrapper
   reports FALSE without altering those outputs. This reaches RunCore's
   contradictory-FALSE branch, rather than manually constructing an owner.

3. Real CreateProcess TRUE, saved genuine distinct valid process/thread handles,
   and the independent duplicate acquired from the genuine process. Change only
   the returned Thread field to the genuine Process handle, preserving TRUE.
   Both returned handles are valid; RunCore's equality guard retains before
   originalsOwned/CloseParentWriters/ObserveAndWait. Explicit runtime assertions
   distinguish genuine distinct handles from injected equal outputs. Owner wait,
   exit-query and original-close counts remain zero before and after natural exit.
   The genuine thread handle stays rooted separately in the test boundary until
   host teardown; it is never confused with the injected Thread or explicitly closed.

An independent immutable snapshot of native returned process/thread handles and
PID/TID are stored before injecting anything. Native FALSE counts as definite
absence only when BOTH handles and BOTH IDs are zero. A non-inheritable same-object duplicate
with QUERY_LIMITED_INFORMATION | SYNCHRONIZE (0x00101000) is acquired before
returning the injected result. Only a confirmed distinct successful duplicate
may enter the raw observer; uncertain duplication retains the host fail-closed. The wrapper records acquisition facts
without logging/diagnostic allocation. A fixed-size call trace identifies injected
waits and owner CloseHandle/GetExitCodeProcess calls. It never grants authority.

## Harmless child and retained-owner checks

A canonical GUID identifies fresh Local ready/release events. The fixed encoded
PowerShell script only opens these events, signals ready, waits at most 30 seconds,
and exits 23 after release or 77 on timeout. No arbitrary executable selector,
services, drivers, Oracle, guest VM, filesystem mutation or descendant launch.

The owner thread holds a fixture mutex across Run and its finally. The observer
requires the injected branch, original process identity/image, a still-live real
child, no owner return/throw or mutex release, and no original process/thread close
or owner exit-code query. No interruption, abort or handle-close race is used.
After child exit the owner must remain retained: exit is not retroactive permission
to complete the unknown attempt. No relaunch, cleanup or ledger manipulation.

## Failure-safe harness teardown

Every known created child gets its own release event signalled even after an
assertion failure. The observer waits on its same-object QUERY|SYNCHRONIZE duplicate (not PID),
requires actual signal before exiting the test host, and records the measured exit.
Unknown thread-start, native creation/observation/wait states retain the test host
fail-closed;
there is no watchdog kill, terminate API, handle-close race or forced child exit.
The existing disposable CI job timeout bounds an unresolvable failed experiment,
not a successful recovery claim.

Genuine original handles stay rooted in the boundary snapshot; the production
owner retains its returned outputs (including the synthetic alias in case three). The independent
observer duplicate is likewise reclaimed only by test-host process exit; no
explicit observer-handle close result is claimed. The fixture does
not call its Dispose or close those handles. Only after definite child exit may
its own host terminate, releasing test-process resources through OS teardown.
These retained cases intentionally never invoke owner Dispose. This is not
production disposal or recovery evidence. Each case has a separate
host; expected-negative assertion cases must also prove natural child exit 23
before their expected exit-1 marker is accepted.

## Still open

TRUE with invalid outputs, unknown native return, contradictory pipe
acquisition, all arbitrary native faults, crash/reboot recovery and workstation
acceptance remain unverified. Three synthetic cases cannot close the entire release blocker.
