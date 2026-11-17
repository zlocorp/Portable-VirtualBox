# Test-only explicit launch environment

## Status and scope

This test-only design is implemented and independently reviewed. At source
`929c3463d1c717f6bceefabb276e4f3b63f38691`, all 11 naturally triggered workflows
passed on attempt 1. Independent artifact review accepted all three environment
cases and rechecked all nine baseline cases on push and PR. See the
[execution record](../EXECUTION-2026-11-11-native-launch-environment.md) for exact
checkouts, actual captured bytes, artifact digests and limitations.
Baseline source `50262c86658ce99453845a021786b781d68aae87` has nine fixed-child
capture cases. Preserve their cases, output expectations and lifetime assertions.
Baseline capture observations on both push and PR have been accepted separately.
All 11 baseline workflows subsequently passed; none of that evidence verifies this
new environment increment.

This independently useful increment supplies an explicit bounded Unicode
environment to the retained native owner and observes it in the harmless fixed
child. No production source, elevation, services, PnP, downloads, security settings,
primary-host experiments or executable selection are in scope. Passing observations
never authorize admission, cleanup, retry, lock release, merge or release.

Two approaches were considered: extend the existing test-only owner with one
closed environment policy, or duplicate the owner in a second launcher. Select the
first: it reuses the original process/thread ownership and unchanged pipe slots
without duplicating their failure paths. Keep the nine baseline modes intact;
add a separate environment-observation mode and test entry point.

## Managed interfaces

All types are internal C# 5 / .NET Framework 4.8 test code:

- `EnvironmentBlockCodec.Encode(KeyValuePair<string,string>[] entries)` returns
  a new `byte[]`. It is a pure serializer, not a process API. Arbitrary synthetic
  entries are accepted only by serializer tests.
- `FixedChildEnvironment.CreateForObservation()` returns a sealed immutable
  policy with a private constructor. It queries the OS and supplies the four
  fixed entries below. No overload accepts caller entries or executable paths.
- `FixedChildEnvironment.CopyBytes()` returns a defensive copy of prepared bytes;
  `WindowsDirectory` exposes the expected OS-derived value for assertions.
- Preserve the nine accepted values of `ChildCaptureOwner(CaptureCase scenario)`.
  That constructor rejects `EnvironmentObservation` and every invalid enum value
  before setup; only a policy constructor may select the new mode. Add
  `ChildCaptureOwner(FixedChildEnvironment environment)`, which selects only
  `CaptureCase.EnvironmentObservation`. Reject null before setup. No arbitrary
  environment overload is added to the existing case constructor. For fault tests add
  `ChildCaptureOwner(FixedChildEnvironment environment, EnvironmentObservationFault fault)`
  with the closed enum `None, AfterCreate, Evidence`; the one-parameter policy
  constructor delegates to `None`. Fault injection remains parent-side and does
  not change the fixed child arguments.
- `EnvironmentAllocation` owns the unmanaged copy. `Prepare(byte[] bytes)`,
  read-only `Pointer`, `TryRelease(CreateEntryState createState)` and read-only
  `ReleaseUncertain` support one-shot preparation and release. The exact enum is
  `CreateEntryState { NotEntered, EnteredReturnUnknown, ReturnedFalse, ReturnedTrue }`. This is internal
  storage, not a public launch surface; the owner passes only policy-produced bytes.

The owner remains single-use. The policy is constructed before `Run`; environment
allocation and all native owners exist before CreateProcessW. Failure before native
entry creates no child. Unknown native outcome retains allocation and owner.
Creation moves irreversibly to EnteredReturnUnknown before the call; only an actual
native return can advance it to ReturnedFalse or ReturnedTrue. The real launcher
never accepts synthetic success or externally supplied create state. The pure model
can test such transitions without invoking native creation.

Allocation and free each have separate NotEntered/EnteredReturnUnknown/Returned
states, set irreversibly before their respective native calls. Unknown allocation
or free forbids reuse, retry and release; unknown create forbids allocation release.
NotEntered creation allows release of a known completed allocation after preparation
failure. Known FALSE/TRUE returns permit environment-memory release, subject to the
owner's stricter existing lifetime gates; TRUE alone never releases child ownership.
Reports distinguish preparation rejection, known create failure and unknown outcome.
The runner roots each owner before any native entry and stops starting new cases if
an owner remains unresolved, retaining it through harness exit.

## Exact environment policy

Emit only these entries:

| Name | Value and provenance |
| --- | --- |
| `SystemRoot` | Bounded successful `GetSystemWindowsDirectoryW` result |
| `WINDIR` | The same successful query value used for SystemRoot |
| `PVBOX_FIXTURE_TEXT` | Literal `Привет = fixture \U0001F642`, where the escape denotes one U+1F642 character |
| `PVBOX_FIXTURE_EMPTY` | Empty string |

No PATH, module path, temporary directory, profile, CI or loader variables are
copied. This is deliberately smaller than the production helper's environment.
Do not fall back to an ambient variable if the Windows-directory query fails.
Use one query with a 260-WCHAR buffer; accept returned lengths 3 through 259 only.
Require an ASCII drive letter, colon and backslash, followed by zero or more nonempty
backslash-separated components. Root `C:\` is supported; bare `C:` is not. Reject UNC,
device/extended paths, forward slashes, NUL/control characters, `<>:"|?*` within
components, dot/dot-dot components, trailing spaces/dots and trailing backslash except
at drive root. Reject zero/truncated/oversize or invalid UTF-16 results, without retry
or ambient fallback. Both entries use this one validated value. These deliberately
narrow fixture restrictions are not claims about every supported Windows deployment.
An OS directory query is not proof of trusted ACLs.

The pure codec accepts at most 16 entries. Names are ASCII letters, digits and
underscore only, nonempty and at most 64 UTF-16 code units. Reject null names or
values and duplicate names under ordinal case-insensitive comparison. Values may
be empty and contain `=`; reject embedded NUL and unpaired surrogates. Preserve
valid UTF-16 exactly, without normalization or environment expansion. Each value
is at most 4,096 UTF-16 code units. The whole block is at most 16,384 UTF-16 code
units, including separators and final terminators. These are fixture policy limits,
not Windows limits. Validate and use checked length arithmetic before allocation.

Sort names ordinally case-insensitively, then encode UTF-16LE without BOM as
`name=value\0...name=value\0\0`. Empty codec input produces exactly two UTF-16
NULs (exactly four zero bytes). Fixed names avoid broader Unicode name-ordering ambiguities. The returned
bytes do not alias caller storage.

Use `EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT` (`0x00080400`),
non-null environment pointer, explicit absolute application/current-directory paths,
mutable fixed command line, STARTF_USESTDHANDLES and the existing exact three-handle
list. Do not add CREATE_SUSPENDED, jobs or new process-control authority. See
[CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw),
[environment ordering](https://learn.microsoft.com/en-us/windows/win32/procthread/changing-environment-variables)
and [Windows directory provenance](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsystemwindowsdirectoryw).

## Harmless observation

The harness temporarily sets `PVBOX_FIXTURE_AMBIENT_SENTINEL=ambient-only` and
verifies its own value. Snapshot and restore native presence plus exact UTF-16 value,
not a managed null/empty approximation. Use native SetEnvironmentVariableW: null
means delete, non-null empty means present-empty. Restore in finally and independently
re-enumerate to verify absence, empty presence or original nonempty value. Test all
three initial states on normal and fault paths. Restoration failure is unresolved,
not PASS; stop new cases. Run serially; never manipulate real loader/profiler variables.

Use GetEnvironmentStringsW in parent and child. Scan at most 32,768 UTF-16 code
units including the final double NUL, at most 512 entries, and at most 8,192 code
units per entry including its NUL. A null pointer, API failure, invalid UTF-16,
malformed entry, duplicate name (ordinal case-insensitive), unterminated entry/block
or exhausted bound is an invalid observation, never proof of absence. Ordinary
entries split at their first equals and require a nonempty name. Permit Windows'
hidden drive entries only as `=X:=value` with ASCII drive letter X, using `=X:` as
the name; include them in bounds and duplicate checking but never in the report.
Accept absence only after a valid complete scan. Always free the original returned
pointer, never a scan cursor, in finally with FreeEnvironmentStringsW and check its
Boolean result. Free failure invalidates the observation and forbids a retry of
that free. Do not serialize unrelated environment contents.

The child keeps the eight-byte prefix length and now uses the query-only PVC2
sentinel result described in the [exact sentinel design](native-sentinel-observation.md).
Only EXCLUDED passes; the parent still separately observes its original event as
unsignaled. Local adapter/composition and managed tests are implemented; independent
Task 2 review and new Windows observations are pending. This does not reclassify
historical execution evidence. The test-only comparison API requires Windows 10 /
Server 2016 and does not change production support. The child then emits one environment
record of at most 16,384 bytes: ASCII magic `PVE1`, little-endian UInt16 version 1,
UInt16 presence flags, UInt32 total record bytes (including header), followed by five
fields in order sentinel, text, empty, SystemRoot, WINDIR. Each field is UInt32 byte
length followed by that many UTF-16LE bytes without BOM or terminator; length must
be even and at most 8,192 bytes. Flags bits 0..4 denote presence in that order;
reserved bits must be zero. An absent field must have zero length; present-empty
has presence set and zero length. Expected flags are 30, but serialize actual flags.
The bounded whole stdout is at most 16,392 bytes including handle diagnostic.
Parent rejects wrong magic/version, reserved flags, inconsistent presence/length,
invalid UTF-16/NUL, checked-length overflow, truncation, size excess or trailing bytes.
A failed scan/free cannot produce a successful absence record. The emitted values
are actual observations, compared separately against expected policy values.

The EnvironmentObservationFault.Evidence injection affects only a diagnostic sink,
never the retained observation capture. Do not route it through CaptureFault, whose
existing poisoned capture intentionally discards bytes. Test a record fragmented
across capture receives, fault the diagnostic sink before its final fragment, and
require the complete actual observation to remain parseable plus sticky UNKNOWN.
Also observe exit, both EOFs and terminal I/O independently. Keep this deterministic
fragmentation test even if native pipe reads happen to coalesce the child's writes.

The separate text-only artifact includes the actual allowlisted PVE1 record as
base64 (at most 1,536 raw bytes), plus the independently OS-queried expected directory
as strict UTF-16LE base64. The fixed four-entry policy's maximum record fits this
artifact limit. Missing or oversize bytes are explicitly unavailable, not substituted
expectations. The strict artifact validator independently decodes and compares the
observed Unicode literal, empty presence, sentinel absence and both directory fields.
Each JSON line stays within 4,096 bytes and the entire four-record artifact within
16,384 bytes. Failure diagnostics may retain bounded malformed bytes but cannot pass.

Parent assertions compare actual captured fields with separate expectations.
Do not require the entire runtime environment to equal the input block: the loader
or runtime may add entries. Child self-report proves only this trusted fixture's
observation, not independent image attestation. Preserve finite capture, original
handle exit observation, independent EOF and close facts, and sticky UNKNOWN.

## Separate later image-admission increment

The first increment keeps the existing fixed sibling image and read-only lease;
it must not describe that as a privileged executable trust boundary. A later,
independently reviewed task may compare SHA-256 from the held stream against a
build-generated digest embedded in the harness, record native volume/file identity
and handle-resolved path, and inspect the original process handle's image path.
Never accept an external digest manifest as authority or equate a self-computed
hash with authenticity. Hold the leaf with FileShare.Read through observation.

CreateProcessW opens by path, not by this lease. A leaf lease does not pin ancestors
or attest ACLs. Disk hashes do not attest loaded bytes, dependencies, configuration,
CLR behavior or the harness. Post-launch identity observations cannot retroactively
admit execution. No hostile replacement or exploit reproduction is needed to state
these limitations. The later task must not change production trust policy.

## Production gap remains

SessionHelper.Main still starts its managed worker before capture and wait setup
finish. Its sanitized environment includes protected session/build-derived values
which this fixture deliberately does not reproduce. Future production integration
requires a separate reviewed design preserving those semantics and fail-closed lock
lifetime across every launch/capture/wait exception.

Run-Sds separately starts VBoxSDS before its try/retained-handle boundary. Keeping
PowerShell alive does not establish descendant lifetime. Neither explicit environment
nor observed child exit creates system-effect replay or cleanup authority. Windows
10/11 interactive acceptance and the existing release gates remain unchanged.
