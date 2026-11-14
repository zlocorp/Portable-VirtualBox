# Test-only native launch observations

## Intent and boundary

This is a disposable Windows experiment that does not request elevation, not a replacement for the
helper's launch path. The assistant selected the implementation details below
under the user's request to continue independent research; they are not recorded
as user design decisions. No production source, script, build or package input is
changed. Every observation has `mutation_authorized=false`. No report consumer,
PID lookup, retry/resume protocol, cleanup authority or production/input-selected callback is introduced.

`SessionHelper.Main.cs` starts a runnable child and then starts capture and waits.
The accepted runtime commit `175e6a4` sequences cleanup completion only after
genuine exit; that does not solve an exception between launch and that boundary.
[Pinned Microsoft reference source](https://github.com/microsoft/referencesource/blob/3b1eaf5203992df69de44c783a3eda37d3d4cd10/System/services/monitoring/system/diagnosticts/Process.cs)
calls CreateProcess before constructing streams and associating the process
handle. It is 4.7.2-family evidence, not an attestation of the exact serviced 4.8
binary and not an observed hosted-CI failure. The later exact-commit loaded-method
inspection below strengthens this premise without reproducing that failure. A
managed Start exception cannot certify that nothing launched; disposing a Process
closes handles, not execution.

## Approaches and chosen limits

1. More managed Start simulations would exercise policy but leave the native
   lifetime premise hypothetical.
2. A production bootstrap/admission implementation would require substantially
   more security design and runtime integration, which are outside this task.
3. **Selected by the assistant:** direct CreateProcessW for one fixed harmless
   fixture image, with the original process handle retained immediately and
   native identity/wait queries. No arbitrary executable, shell, inherited
   handles, redirected pipes, suspension, termination, driver or VBox effects.

The fixture writes only bounded markers beneath a fresh generated temporary
directory and exits naturally. Its finite mode set covers immediate 0, nonzero
70, 259 and a completion-gated zero exit. The gate is only fixed fixture
orchestration: a parent-written marker or a finite ten-second fallback lets the
child exit naturally. Short-timeout tests wait before release; trusted draining
releases before waiting, and still waits for natural fallback if release fails.
It is not bootstrap/admission IPC or a production capability. The image is copied from the runner's own
fixed compiled fixture and held read-only without write/delete sharing while
used. Hash, parent PID/generation and expected build mismatches refuse before
launch. This is an owned test-directory assumption, not an adversarial filesystem
or elevated image-admission security claim. Sanitized elevated environments,
pipe capture, IPC, production adoption and executable path race hardening are
deferred.

## Independent axes

The invocation axis distinguishes `NOT_INVOKED_THIS_ATTEMPT`,
`LAUNCH_ENTERED_UNKNOWN`, `CREATE_REJECTED_THIS_ATTEMPT`,
`EXACT_CHILD_RETAINED` and `EXACT_CHILD_EXITED`. Rejection requires an actual
CreateProcessW FALSE and immediately captured last error. It describes only that
call, never historical `NO_EFFECTS`. Entering the attempt permanently consumes
the instance, even if pre-call validation rejects it.

Overall `UNKNOWN` is sticky after timeout, injected managed setup/wait faults,
identity failures or uncertain evidence. Later native exit 0 can add the genuine
exit fact but cannot clear UNKNOWN. WaitForSingleObject must signal before
GetExitCodeProcess is interpreted; 259 after a signal is an exit code, not a
live-process test. WAIT_FAILED is neither absence nor exit.

The process and thread handles returned in PROCESS_INFORMATION are assigned to
retained fields before fallible metadata or journal work. The thread handle may
then close. Finally drains a successfully created child using only its exact
retained process handle, obtains the exit code after a native signal and only
then closes that handle. A controlled WAIT_FAILED injection deliberately retains
the handle for a separately invoked trusted drain. A persistent real native wait
failure remains unresolved, retains the rooted handle and fixture files, fails the run
and is never silently converted into close, kill or success. Process teardown by
the operating system is not represented as successful harness draining.

Cleanup checks both retained handles and entry into the P/Invoke invocation
boundary/observed-return state. The call counter counts invocation attempts; an
unavailable return does not prove the OS function ran. Captured TRUE/FALSE is an
actual observed native result. An unavailable native outcome preserves the fixture even if no handle was
published. This includes the marshalling/return window that cannot safely be
reproduced by forcing an allocation failure. A separate managed decision test
models that unavailable outcome; the pre-call injected exception is not evidence
of that window's behavior.

PID, creation FILETIME, image hash/path, parent PID/generation and attempt ID are
diagnostics, not transferable capabilities. Same PID with a different generation
does not match. There is no OpenProcess, name lookup or persisted-handle adoption.

## Evidence

Each attempt owns a CreateNew bounded recorder, retains its original writer and
acknowledges append only after actual write, Flush(true), and byte-for-byte
readback. Any injected or actual write/flush/readback uncertainty poisons it; no
repair, reopen or resume API exists. Faults around these operations are labeled
injections, not physical durability certification. Historical, foreign, torn or
omitted text cannot launch anything. No WORKER_EXIT is invented for an uncreated
child. Logs are bounded diagnostics and never executable uploads.

The Windows report records the configured net48/x64 target, actual CLR, loaded
Process assembly identity and module MVID, separately labeled on-disk assembly
path file version/hash, and a bounded StartWithCreateProcess IL inspection with
raw IL, token mappings, branches and exception regions where supported. Missing
or unsupported inspection is explicit. The disk-byte association with the loaded
module is not attested. Call order is not control-flow proof, and
one runner's assembly cannot attest all serviced Framework 4.8 builds.

## Verification and exclusions

Portable managed checks exercise recorder poisoning and protocol decisions with
no native call. Windows checks exercise the fixed child, actual native FALSE,
actual timeout, exact-handle drain, exit 259, no relaunch, identity rejection and
injected exception paths. Injected faults do not reproduce a Framework allocation
failure; OOM is never induced. The local Linux run explicitly skips native APIs.
Official net48 references establish compilation compatibility, not Windows
runtime behavior. Hosted Windows execution is a separately reported result.

Local verification: 317 Python tests ran, OK with 6 platform skips; four focused
Python observation tests passed; both test executables compiled as C#5/x64 against
official net48 reference assemblies with warnings-as-errors. Those checks are
separate from the later native Windows observations below.

## Accepted hosted observations

At exact `f9bff11790b5f8324218a4c3d67be171b8526627`, both native workflows passed
on attempt 1 and independent artifact review accepted the test-only observations.
The [execution record](../EXECUTION-2026-11-11-native-launch-observation.md) binds
the two text files to the source SHA and archive digest. Its 16 attempts include
one observed native FALSE/error 2 and ten created children, each drained through
its retained handle before close. Timeout and injected faults remain UNKNOWN
after genuine exit; controlled WAIT_FAILED is not a reproduced persistent native
wait failure. The 232 total checks include 64 managed checks.

For the actual loaded private method, full raw IL, call/token decoding and all
five exception regions survived the bounded verbose-output truncation. Independent
control-flow review established successful native creation before redirected
stream construction and process association, with no local exception region
protecting that later construction. This is stronger than reference-family theory,
but does not attest the full outer Start/Dispose/finalizer/JIT chain, loaded bytes
from the disk hash, all serviced builds or an observed allocation failure. The
production lifetime gap remains open. A native two-pipe capture prototype is
future work, not a result of this observer.

No primary Windows run, production repair, merge, release or promotion gate is
claimed by this prototype.

## Childless production-owner WAIT_FAILED probe

`check_fixed_effect_worker_retention.ps1` builds the unchanged production
`FixedEffectWorker.cs` together with a separate test-only executable. The probe
uses no command-line selectors and starts no child. It first records the real
Windows result of waiting on a NULL handle (`WAIT_FAILED`, error 6), then invokes
the actual private `ObserveAndWait` method on a synthetic post-creation owner
whose process handle remains NULL. Minus one is deliberately not used because
Windows treats it as the current-process pseudo-handle.

The owner thread first acquires an unnamed fixture mutex and completes a two-way
entry handshake. The observer then requires the production query-failure field
and a retention sleep, verifies no exit/disposal/completion and no mutex release,
and repeats the checks after three thread interruptions. Failure to reach the
observed state within ten seconds fails, not passes. Native results for the
independent NULL wait are recorded explicitly; the production method itself is
not instrumented to expose its native return value.

The fixture exits its own childless process after bounded observation. It does
not release or recover the synthetic unknown owner. No valid native resource was
acquired by that owner, and no real worker, service, driver or guest is killed.
This tests production error-path retention for invalid-handle state and does not
prove arbitrary-duration retention, actual acquired-child wait failure, unknown
creation or contradictory native acquisition outputs. Local net48 compilation
is not Windows execution or workstation acceptance.

## Actual-child restricted-handle fixture (test only)

A separate closed fixture launches its own EXE once per case with native
CreateProcessW. The child opens only two GUID-bound Local ready/release events,
announces readiness and exits naturally after release (code 23), with a 30-second
natural timeout (code 77). It performs no service, driver, Oracle or privileged
operation. Unknown command modes and noncanonical tokens are rejected.

The parent retains the original full-access process/thread handles. It duplicates
the process handle with PROCESS_QUERY_LIMITED_INFORMATION (0x1000), no SYNCHRONIZE,
no inheritance and options 0. Duplication binds the same object, without reopening
by PID. Actual identity/image queries and WAIT_TIMEOUT on the retained original
prove the child is live before and after the retention observation. The restricted
duplicate must return WAIT_FAILED/error 5 in a separately measured sanity call.

The unchanged production ObserveAndWait method is invoked with a synthetic owner
adopting that duplicate. A private synthetic WithinDeadline=true sentinel is
replaced by the real method after its native wait returns; no native return is
injected. Query buffer/image success, owner sleep, held same-thread mutex,
no exited/disposed promotion and three interruptions are checked. After release,
the harness observes natural child exit on the original handle and requires 23;
the production owner must still retain UNKNOWN and the mutex. This is not an
exercise of production RunCore acquisition, original-handle failure, or system
recovery. The production native return itself is not instrumented.

Three cases run in separate test hosts: normal retention, a deliberate assertion
before adoption, and a deliberate assertion after retention. Both negative cases
must exit 1 only after verified child exit 23 and emit the exact terminal marker.
Every failure after known creation goes through natural-exit observation. Failed
release signalling still waits for the child's natural timeout; uncertain native
waits/creation and failed original-handle closes retain the test host fail-closed.
Logging failure cannot escape that retention loop. The restricted duplicate is
not closed under a retained owner; it remains rooted until the harmless test host
exits, after the child is proven exited. No forced child termination or close/wait
race is used. These unknown paths are not claimed dynamically fault-injected.

Microsoft documents that [waits require SYNCHRONIZE](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject),
[CreateProcess returns full-access handles](https://learn.microsoft.com/en-us/windows/win32/procthread/process-security-and-access-rights),
and [DuplicateHandle can request different access](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle).
Thus this is deliberate rights-fault adoption of a genuinely acquired child,
not evidence that ordinary CreateProcess returns restricted handles. Whole-product
Windows 10/11, interactive UAC and general SYSTEM retry remain separate gates.

The initial `adc3a69` PUSH/PR native jobs executed all three acquired-child cases
successfully but failed the step: PowerShell retained exit 1 from the last
expected-negative child and GitHub propagated it. The runner now clears
LASTEXITCODE only after every case's original status/marker checks and its final
summary. An executable contract extracts that actual tail and exercises nested
invocation plus GitHub wrapper semantics, including six rejected status/marker
variants. It uses a closed synthetic command, not a replacement native proof.
