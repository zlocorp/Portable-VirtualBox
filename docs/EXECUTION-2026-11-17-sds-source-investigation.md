# SDS failure: source investigation and next diagnostic

This is source analysis, not a causal explanation or a production fix. The
[retained failed attempt](EXECUTION-2026-11-17-sds-failure-evidence.md) records
SDS process exit 0 followed by a missing service key; it does not preserve the
actual child command line or an independent loaded-image attestation.

## Verified source and observed launch construction

Oracle's [7.2.22 source archive](https://download.virtualbox.org/virtualbox/7.2.22/VirtualBox-7.2.22.tar.bz2)
was read in memory. Its 257,289,481 bytes have SHA-256
`440a2b3eeb46e7e992961b70ef24f43e95b3c99fa2ab30aac20b963ef9e91ad7`,
matching Oracle's [SHA256SUMS](https://download.virtualbox.org/virtualbox/7.2.22/SHA256SUMS).
The extracted `src/VBox/Main/src-global/win/VBoxSDS.cpp` has SHA-256
`d475d54896ad28e2ec83f0d5339d02cb535a245b4bf17f356918511d43273003`.
This is corresponding published source, not proof of the exact instructions
executed in the retained failure.

At source commit `6c39a09`, the protected bridge selects
`FixedEffectWorker.RunSds(..., false, ...)` for registration. It constructs
`ProcessStartInfo(image, "--regservice")`, then a quoted image followed by that
argument, passed to `CreateProcessW` with the image as application name.
This is source-level construction, not independently recorded argv in the
failed artifact.

Oracle's `VBoxSDS.cpp` identifies `--regservice` (line 872) and sets
`fRegister=true`, `fRun=false` (923–926). In the registration path,
`registerService` first calls `uninstallService`, then
`onRegisterService` and `installService` (182–198). The first call may
stop and delete an existing service (445–488); registration is therefore not
a harmless observation or a safe blind retry. `installService` treats a
successful `OpenService` as already installed, or else calls
`CreateServiceW` and treats a returned handle as success (391–441).
Microsoft documents [OpenServiceW](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openservicew)
and [CreateServiceW](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
as returning service handles on success, and states that CreateService creates
the corresponding Services registry key. These calls do not identify what
happened in the historical run.

`WinMain` initializes `hrcExit` with `com::Initialize()` (1044) and
returns it (1118). The source's null branch after
`new CComServiceModule()` logs a failure without assigning `hrcExit`
(1061–1108); **if** COM returned S_OK and this particular new expression could
return null in the shipped build, source control flow permits exit 0 without
registration. The actual allocator, compiler/build semantics and reachability
of that branch in Oracle's shipped binary have not been established, and there
is no evidence it happened in this failure. Other parsing and service-mode
paths exist; actual child argv and loaded image were not recorded. During
registration, Oracle's source says its release log is not created by default
(977–980), so empty captured output does not distinguish these paths.

## One controlled experiment (proposed, not yet implemented or run)

Use two fresh independent disposable GitHub-hosted Windows jobs/VMs, or a
separately isolated Windows VM with a recoverable snapshot. GitHub-hosted
runners do not provide snapshot control. Without disabling UAC, antivirus, HVCI
or other protections, validate an instrumented diagnostic launcher first
against harmless fixed test processes and a uniquely named stopped test service.
Require it to detect success/failure, call/return pairing, concurrent threads,
lost events, and an intentionally missing breakpoint. The instrument must
report UNKNOWN when its coverage or process identity is uncertain.

Then, on the second fresh disposable runner, or a restored isolated snapshot,
with verified absent VBox resources, use that launcher for **one** invocation of the exact pinned and
signed Oracle image with `--regservice`. This is a dedicated diagnostic
experiment, not the protected production launch. Before resuming the child,
bind observations to its process handle and generation; record checked
image identity/hash, argv, exit and time. Using documented
[Windows debug events](https://learn.microsoft.com/en-us/windows/win32/debug/debugging-events)
and [process creation flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags),
or an equivalently validated mechanism, trace actual entry and return for fixed
VBoxSDS `OpenServiceW` calls including requested access, `CreateServiceW`,
and corresponding `ControlService`/`DeleteService` calls. Capture exact
return status, and error information only where reliably captured at the
return boundary, without changing arguments or return values. Distinguish the
install-path query from earlier uninstall-path calls by call order, access and
handle linkage; if this cannot be established, report UNKNOWN.

Take read-only SCM and Registry32/Registry64 observations before and after,
with timestamps and explicit absent/denied/error states. If independently
available, collect filtered process/registry events with buffer-loss counts;
service registry writes may be performed by SCM, so attribution requires
correlation and incomplete tracing cannot rule out another actor. Retain bounded
artifacts and the original outcome. Do not automatically repeat a failed
registration, infer ownership from a matching name or a success code, or
attempt cleanup from diagnostic observations. Collect and upload the bounded
evidence before the hosted job terminates: its ephemeral runner and local state
will not be available afterward. Preserve a recoverable snapshot where one
exists; otherwise discard the disposable runner without claiming cleanup. Never
apply these steps on a valuable host.

A complete trace can distinguish an observed successful existing-service open
from an observed successful creation, or show that the instrumented calls were
not observed. A post-exit SCM/registry discrepancy can direct further
investigation. No event, missing trace, or later success by itself proves
absence of a concurrent deletion, the historical cause, safe cleanup authority,
or workstation acceptance. Debugging perturbs timing and may interact with
Oracle hardening; a refusal or altered path is a result with that limitation,
not evidence that the original failure was repaired.
