# Read-only partial-cleanup reconciliation

## Intent and constraints

Explain remaining protected payload after an interrupted cleanup without turning
absence of files, a JSON claim or an old helper journal into deletion authority.
The production recovery blocker remains open. No new helper verb, elevation,
service/driver/process action, retry, package entry or VM-data access is added.

## Approaches

1. Retry the current cleanup worker: rejected because its one-shot markers and
   full inventory preconditions cannot distinguish every partially applied effect.
2. Implement a step-bound trusted resume protocol: needs separately reviewed
   ownership revalidation, durable per-effect intent/results and real interruption
   acceptance. Deferred, not silently substituted with receipt deletion.
3. Read-only filesystem reconciliation: selected. A developer Python tool checks
   the independently pinned Oracle inventory and current embedded-script bytes,
   reports exact remaining/missing payload, and labels cleanup JSON as claims.

## Chosen boundary

`scripts/reconcile_cleanup.py SESSION --manifest ORIGINAL_APP64/.prepared.json`
prints bounded JSON. The external manifest remains useful after the protected
copy was deleted; its canonical rows must match the existing Oracle package pin.
Only `app64`, `code` and known small cleanup markers under SESSION are inspected.
No recursive scan of VM data or arbitrary receipt contents is printed.

Every result includes `resume_authorized=false`, `ownership=UNVERIFIED` and
`system_state=NOT_OBSERVED`. `REVIEW_ONLY` means a consistent file observation,
not confirmed system teardown, authenticated ownership, readiness or a command.
Wrong/missing manifest, unexpected or changed files, unsafe paths, symlinks,
reparse points, hardlinks, unreadable or concurrently changing inputs block the
report. Stable absent expected files are reported, never recreated or removed.

The observer performs bounded repeated reads but cannot guarantee an atomic
system snapshot or resist an administrator changing parent topology. Stop use of
the isolated session before inspection. A full trusted resume requires a new
protocol and separate review; this diagnostic is not wired into runtime policy.
