# SDS registration failure: retained evidence

This record re-examines the already completed [orphan recovery workflow run
43844798725](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43844798725)
on source commit `6c39a0917367a97b1eb3dcce8b80e3e8b289f146`. No workflow
was rerun and no system operation was performed for this review.

The retained `orphan-recovery-evidence` artifact has GitHub artifact ID
`14214478577`, size 6,299 bytes, and SHA-256
`bd5f0bd08d9798949ebc43471150f5cc4909bf2323be41943332d58720b0f05e`.
The downloaded ZIP's SHA-256 was independently recomputed and matched the
GitHub artifact metadata.

## Observations

The helper Prepare stdout records:

- VBoxSup staging reported `pnputil=EXITED/0`, verified installation and
  matching driver hash; the subsequent driver start reported `EXITED/0`
  and both service and WMI state as Running.
- SDS registration recorded a returned launch, nonzero handle, completion
  within the deadline, `exit_code=0`, and elapsed time 459 ms.
- The SDS registry preflight was absent, and the subsequent gate recorded
  `query=missing`, `error=not_found`, and `gate=observation_error`.

The worker stderr says the `HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS`
key did not exist. Both retained SDS registration stdout and stderr files are
empty. The worker journal records exit 1 within its deadline; the workflow log
records `prepare-orphan exit=70, expected 0`. The artifact contains no
successful cleanup receipt or final host-state proof.

## Limits

These records establish the observed process result and missing-key refusal
for this attempt. They do not identify why registration did not produce the
expected key, prove the launched image identity independently of the existing
protected launch checks, or establish that no other system effect occurred.
They do not authorize registration replay or cleanup. This failure predates
the two-snapshot, failure-only SDS observations added in `4eda40b`; those
snapshots are not present in this artifact. A later successful workflow does not
explain or erase this failure. The release gate remains open.
