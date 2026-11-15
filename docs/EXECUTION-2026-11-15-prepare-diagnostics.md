# Preparation failure evidence preservation

## Runtime change

Preparation previously persisted stdout, stderr and token facts in sequence.
A failed stdout write/capture prevented the remaining diagnostics and image
observation; a diagnostic failure could mask a nonzero worker exit or deadline.

`CompletePrepareWorker` now preserves the worker outcome as the primary failure,
attempts both retained capture results, image observation and all available
stdout/stderr/facts writes independently, then rethrows the first failure. A
capture failure does not fabricate missing output. Failure remains exit 70;
there is no new cleanup checkpoint, system retry, or recovery authority. Native
owner disposal and the existing final controller check are unchanged.

The managed fixture executes the actual private implementation for success,
nonzero exit, deadline and injected persistence/capture/image/write failures.
It invokes neither helper Main nor native/system operations. This is not a
Windows 10/11 acceptance or a demonstration of physical power-loss recovery.

## Still blocked

General operational cleanup retry remains blocked. Existing cleanup proof and
output directories deliberately prevent replay after uncertain/partial system
effects. Removing these markers or trusting an old service name/configuration
would not establish continuity of the original resources. A separately reviewed
protocol and disposable Windows system-effect acceptance are required; this
change does not relax that boundary.
