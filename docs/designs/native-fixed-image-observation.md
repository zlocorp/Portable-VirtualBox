# Test-only fixed-image observation and preflight

## Status and boundary

Task 1 file-only implementation is present for independent review. Exact-source
Windows file-only evidence is pending; Task 2 remains gated and unimplemented.
At environment source `929c3463d1c717f6bceefabb276e4f3b63f38691`, push and PR
observations have been independently accepted: all three environment and nine
baseline cases passed, including the actual 110-byte PVE1 record. All eleven source workflows have completed successfully and been accepted,
each on attempt 1: eight push and three PR runs. These results do not verify this
proposed increment.

This is fixed-fixture observation and preflight, not privileged image admission.
Use only owned temporary files and the existing harmless sibling child. No
production changes, signatures, elevation, drivers, services, security settings,
user's Windows experiments, merge or release. Preserve the nine baseline cases,
three environment cases, their assertions and their separate evidence schemas.

## Approaches and recommendation

1. Own an exact native file handle and hash through bounded synchronous ReadFile
   calls. This adds a small read loop but makes entry, return and close evidence
   explicit. Recommended.
2. Own the same native handle and hash through a FileStream borrowing a
   SafeFileHandle with ownsHandle=false. Dispose the borrowed stream/wrapper before
   explicit native close. This reuses managed hashing I/O but adds borrowing and
   disposal states that cannot prove native close.

Both extend ChildCaptureOwner with one sealed, opt-in context; neither duplicates
its launcher. Existing FileStream.Dispose evidence remains managed disposal only.
Do not silently strengthen baseline native-close claims.

## Build provenance and closed entry

Compile NativeCaptureFixtureChild.exe first in the runner's fresh private fixture
build directory, using existing C# 5/x64/.NET Framework 4.8 settings. Hash those
completed bytes and generate FixedFixtureBuildExpectation.g.cs there, then compile
it into the harness. Retain that source with the build. The generated source has
fixed syntax, fixed sibling filename, exact positive length and exactly 64 lowercase
SHA-256 hex characters; cap it at 2 KiB. Generation format is deterministic, not
an assertion of reproducible compiler output. Do not interpolate arbitrary strings
into C# source. Fail the build if generation or compilation fails.

At runtime expected values come only from these compiled constants. They must not
be recomputed from whichever file happens to be present. No native entry accepts
an external path, digest, manifest, command or environment-selected executable.
A runner's evidence-output directory never selects execution inputs. Update all
affected compile paths, including managed contract builds, without placeholder
native expectations or stale generated-source fallback. Managed-only testing may
compile the harmless child to generate constants without running it.

Use an internal sealed FixedFixtureImage with private construction:
CreateForObservation() returns an unopened owner; PrepareOnce() opens and observes
only NativeCaptureFixtureChild.exe beside the executing harness. Root this object
before PrepareOnce and every native call. It exposes immutable observations and
separate readiness/release state, never a public raw-handle or arbitrary-path API.
Task 2 adds ChildCaptureOwner(FixedFixtureImage), accepting only an unused context
and selecting existing Binary behavior internally. Existing constructors remain
closed and unchanged. The new mode need not change the child or its argument set.

## Exact held-file observations

- CreateFileW: GENERIC_READ, FILE_SHARE_READ only, OPEN_EXISTING, null security
  attributes (non-inheritable), FILE_FLAG_OPEN_REPARSE_POINT, synchronous I/O.
  Reject directory/reparse leaves using GetFileInformationByHandleEx with
  FileAttributeTagInfo. Ancestors remain unvalidated.
- GetFileSizeEx: positive size, at most 16 MiB, equal to generated expected length.
- ReadFile: chunks at most 64 KiB; checked cumulative count bounded by 16 MiB;
  require exactly expected bytes, then a positive-length terminal request (one
  byte) returning TRUE with zero bytes. This extra request is required even at the
  exact 16 MiB boundary; a zero-length request never proves EOF. A returned extra
  byte rejects the image without hashing it or increasing the accepted byte bound.
  Hash accepted bytes with SHA-256. Read error, impossible byte count or incomplete observation
  never constitutes a digest match. No reopen by path for hashing.
- GetFileInformationByHandleEx(FileIdInfo): record UInt64 volume serial and the
  128-bit file ID. Unsupported query fails observation; no weaker silent fallback.
- GetFinalPathNameByHandleW(FILE_NAME_NORMALIZED | VOLUME_NAME_DOS): one bounded
  32,768-WCHAR buffer. Reject failure, truncation, invalid UTF-16/NUL and unsupported
  non-local-DOS forms. Preserve the actual result, not a substituted expected path.

All size/hash/identity/path observations use the same retained handle. Compare the
actual digest against the embedded expectation before Proof.BeforeCreate or any
CreateCalls increment. A mismatch is a preflight refusal, not a native create
failure. File-only Task 1 harnesses never create a fixture child. The trusted runner must
still invoke those file-only harness executables; that is not forbidden process
creation under this boundary.

For Task 2, derive the explicit application and working-directory strings solely
from the sealed context. After a known successful CreateProcessW return and original
handle validation, call QueryFullProcessImageNameW(Original.Process, 0, ...) with
one 32,768-WCHAR buffer. Query before original-handle release, never via PID lookup
or OpenProcess. A query failure must not bypass draining and exit observation.
Compare valid local DOS paths ordinally case-insensitively, stripping only a
recognized \\?\ DOS prefix when necessary. Keep raw held-file and process-image
paths separately. Path agreement is not proof of identical loaded-file bytes.

## Native ownership and return evidence

Each open/read/close has an irreversible entered state set before the call and a
separate recorded native return. A successful open stores the exact handle in its
rooted owner before further work. INVALID_HANDLE_VALUE is a known open failure,
not an owned handle. Unknown open return retains the owner and forbids retry.
Reads advance only after known successful returns; partial reads are permitted,
but unknown return poisons observation and forbids further read/close reuse.

Checked CloseHandle on the exact owned handle is the only explicit native-release
proof. Known FALSE or unavailable close return is unresolved; never close again.
Model these faults without creating real uncertain/leaked native operations. Root
unresolved owners through harness exit and stop new cases. Process teardown is not
explicit resource-release evidence.

Task 1 releases a known file handle after terminal synchronous file observations,
including known preflight rejection. Task 2 retains it through the existing owner
lifetime gates, including capture, terminal I/O and original-handle exit observation.
Unknown creation outcome retains it. Image release participates in owner release
status; diagnostic failure remains sticky UNKNOWN even after successful release.

## Harmless coverage and evidence

All negative setup occurs before opening the image, in fresh owned build copies:

- Matching image: actual length/hash/identity/path, then explicit file release.
- Same-length digest mismatch: change one deterministic byte in an owned copy of
  the harmless child, preserving length and the original embedded expectation.
  Never execute that copy. Assert digest comparison was reached and rejected.
- Size mismatch: append one harmless byte before opening. Assert size rejection,
  distinct from digest rejection. Never execute that copy.
- Missing image: omit or move only the owned fixed sibling before the attempt.
- While held, separate GENERIC_WRITE and DELETE-access probes use OPEN_EXISTING
  and FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE. Their own sharing
  must permit the existing reader, so failure cannot be caused by an incompatible
  probe share mask. Capture GetLastWin32Error immediately after each failed open;
  require ERROR_SHARING_VIOLATION. Do not write, delete, truncate or request
  delete-on-close. Checked CloseHandle must close an unexpectedly successful probe;
  fail that case even if close succeeds, retain uncertainty if it does not. Pin
  these exact access/share/disposition arguments with a managed call-contract test.

Every negative case must prove zero CreateProcessW entries in Task 2; Task 1 has no
launcher for a fixture child. Build four separate harnesses, each with exactly one
compile-time case constant from the fixed four-case allowlist below. All four embed
the same pristine child expectation unchanged. Only afterward prepare the negative
child copies in their separate fixture directories. Each harness accepts no
arguments and opens only its own fixed sibling. The trusted runner invokes these
fixed harnesses and aggregates records in the specified order; no runtime
path/digest/case selector is introduced. Never regenerate expectations after
negative setup. Isolate cases so corrupted/missing images cannot carry into a
positive launch. No exploit, race or hostile replacement reproduction.

## Separate artifact contract (version 1)

Task 1 validators accept only `stage=file-only`; `composed` validation remains unavailable until Task 2 passes its prerequisite gate.

`native-fixed-image-observation.jsonl` is UTF-8 text, at most five records, 16 KiB
per line including newline and 128 KiB total. Each record has exact keys; reject
duplicate/unknown keys, wrong types, invalid UTF-16/NUL in strings, excess bounds
and trailing records. Do not truncate observations into apparently valid evidence.

Case order is exactly `matching-image`, `digest-mismatch`, `size-mismatch`,
`missing-image`. Each case record has only these keys:

- `kind`: `fixed_image_case`; `schema`: integer 1; `stage`: `file-only` or `composed`;
  `case`: one name above; `status`: `PASS` or `FAIL`; `mutation_authorized`: false.
- `refusal`: `none`, `digest-mismatch`, `size-mismatch`, `missing-image` or
  `observation-failure`; `create_calls`: nonnegative integer.
- `expected_size`: positive integer <=16 MiB; `expected_sha256`: 64 lowercase hex.
  These are generated expectations, never actual observations.
- `open_state`: `not-entered`, `return-unknown`, `returned-failure` or
  `returned-success`; `open_error`: UInt32 only on returned-failure, otherwise null.
- `actual_size`: nonnegative integer or null; `actual_sha256`: 64 lowercase hex or
  null; `bytes_hashed`: nonnegative integer; `read_state`: `not-entered`,
  `return-unknown`, `returned-failure`, `known-incomplete` or `complete`; `read_error`: UInt32 only on
  returned-failure, otherwise null; `eof_request_bytes` and `eof_return_bytes`:
  integers for the known successful terminal read, otherwise both null.
- `volume_serial`: 16 lowercase hex or null; `file_id`: 32 lowercase hex or null;
  `held_path`: nonempty actual local DOS path or null.
- `write_probe` and `delete_probe`: null when not attempted, otherwise objects with
  exactly `access` (respectively `GENERIC_WRITE` or `DELETE`), `share` (integer 7),
  `disposition` (integer 3 for OPEN_EXISTING), `open_state`, `open_error`, and
  `close_state`. Open states/errors follow the rules above.
- `close_state`: `not-opened`, `not-entered`, `return-unknown`, `returned-failure`
  or `returned-success`; applies to the exact owned image/probe handle.
- `process_observation`: null outside a successful composed positive launch;
  otherwise exactly `image_path` (actual nonempty local DOS path or null),
  `query_error` (UInt32 on known query failure, otherwise null), `exit_wait_result`
  (UInt32 actual wait result or null), `exit_code` (UInt32 actual code or null),
  `owner_release_state` (`retained` or `released`).

Unavailable means JSON null, never empty string, zero, expected-value substitution
or a made-up observation. Zero is valid only where it is an actual count/result.
The bytes_hashed counter starts at zero; other not-entered observations remain null.
No standalone `hash_matches`, `sharing_denied` or `released` Boolean substitutes
for evidence. A structurally valid report is not proof the native calls occurred;
acceptance additionally requires independently reviewed exact-source native runs.

Every PASS case except missing-image requires open_state=returned-success and
open_error=null. actual_sha256 is present only after a complete successful read;
failed/incomplete reads never publish a partial hash as an image digest.
Use read_state=known-incomplete when successful native reads are followed by
premature EOF, extra terminal bytes or managed hashing failure: read_error=null
and actual_sha256=null. Preserve any actual successful terminal read counts rather
than inventing a native error. Reserve complete for a full digest and the required
positive-size EOF proof. known-incomplete can appear in valid FAIL diagnostics,
never a PASS case.
A PASS matching case requires matching sizes/digests, bytes_hashed=expected_size,
read_state=complete, eof_request_bytes=1, eof_return_bytes=0, actual identity/path,
image close returned-success, and both probes with returned-failure/error 32 and
close_state=not-opened. A PASS digest mismatch requires equal sizes, a complete hash
with the same EOF proof but unequal digests, and checked image release. Size mismatch
requires unequal actual/expected sizes, no hash/read entry and checked image release.
Missing image requires returned-failure/error 2, no file observations or probes,
read_state=not-entered, bytes_hashed=0 and close_state=not-opened. Probes are confined
to matching-image. All file-only and all negative cases require create_calls=0 and
process_observation=null. Composed matching additionally requires create_calls=1,
actual matching process path, no query error, exit_wait_result=0, exit_code=0 and
owner_release_state=released. Inconsistent or missing required observations fail.

The final record has exactly `kind`=`fixed_image_summary`, `schema`=1, `stage`,
`status`, `cases` (case-record count), `failed` (FAIL-case count), `stop_reason`
(`none`, `case-failure`, `unresolved-owner`, `build-failure` or `evidence-failure`),
and `mutation_authorized`=false. Stage must agree across records. PASS requires all
four ordered PASS cases, cases=4, failed=0 and stop_reason=none. Structurally valid
failure diagnostics may contain an ordered prefix, including zero cases for build
failure, followed by FAIL summary with consistent counts and non-none stop_reason.
Include the attempted case whenever possible; unresolved-owner stops later cases.
Never fabricate absent later cases. Validators distinguish valid diagnostics from
acceptance: require-pass rejects every FAIL summary and every incomplete sequence.
Reports never provide release, retry or cleanup authority.

Task 1 includes narrowly scoped CI path triggers, file-only execution and this
separate bounded artifact. Independently reviewed exact-source Windows file-only
results are a prerequisite to beginning Task 2, not merely its final acceptance.

## Explicitly unproved

The build itself, harness, ancestor identity/ACLs, configuration, dependencies, CLR
behavior and loaded bytes are not attested. CreateProcessW opens by path rather
than by the retained image handle. Sharing denial concerns ordinary new leaf opens,
not existing writable mappings or all possible modification mechanisms. Post-launch
path observations cannot retroactively admit execution. Production suspended-before-
runnable lifetime design is a separate prerequisite, not silently added here.
Windows interactive acceptance and all existing release gates remain unchanged.
