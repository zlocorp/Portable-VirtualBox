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
binary and not an observed hosted-CI failure. A managed Start exception cannot
certify that nothing launched; disposing a Process closes handles, not execution.

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

Local verification: 317 Python tests passed with 6 platform skips; four focused
Python observation tests passed; both test executables compiled as C#5/x64 against
official net48 reference assemblies with warnings-as-errors. These are not native
Windows observations; the committed hosted step is ready to produce those.

No primary Windows run, production repair, merge, release or promotion gate is
claimed by this prototype.
