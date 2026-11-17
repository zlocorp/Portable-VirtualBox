# Bounded, failure-only SDS observation

## Trigger and non-authority boundary
The existing Prepare registration/identity try block records entry immediately
before its unchanged Run-Sds call and acceptance immediately after its unchanged
identity predicate. Its catch invokes optional diagnostics only when entered and
not accepted, catches all diagnostic failures, and rethrows the original record.
Preflight refusal, success, driver-stage failure and later marker/receipt failures
do not collect. There is no registration retry, new gate, late-success promotion,
cleanup authorization, or persisted authority file. Existing two V1 records remain.

## Collection surface
All functions remain in the existing hash-protected worker script. No new public
bridge API, Add-Type, P/Invoke, external command, helper binary or service control.
Two samples separated by one 200ms delay contain:
- Get-Service with the literal VBoxSDS name; observed status or error plus numeric
  exception HResult. This is not a claim of raw native SCM GetLastError fidelity.
- Read-only .NET RegistryKey LocalMachine views Registry32/Registry64, fixed
  SYSTEM/CurrentControlSet/Services/VBoxSDS key, ImagePath/ObjectName/Type/Start only.
  Environment strings are not expanded. Registry32/64 readings need not differ.
- .NET Process.GetProcessesByName with literal VBoxSDS; at most four metadata rows:
  PID, creation FILETIME, and image equality classifier. All process objects are
  disposed, including any beyond the retained cap. No process is signaled or waited.
- sampled UTC ticks. This is not a registry last-write timestamp.

Raw paths, usernames, command lines, event messages/XML and exception strings are
never output. Image/account strings become fixed classifiers; numbers require
actual int/long primitives and bounds; malformed values become unknown/unavailable.
Event collection is deliberately deferred: service display-name localization and
privacy filtering require separate validation and are not needed for this increment.

## Bounds and limitations
Each sample has at most eight ASCII records: service, two registry views, process
summary, up to four process rows. Each record including CRLF <=1024 bytes; total
<=6144 bytes, reserving the unchanged V1 maximum of 2048 bytes for a combined
<=8192-byte diagnostic bound. A sample's complete output is checked before emission. Sink failure
is swallowed and cannot replace the original refusal. Truncated process results
are explicit. Each axis failing independently yields error/unknown, not absence.

These are bounded call/record counts, NOT a hard wall-clock deadline for Windows
RPC/registry/process getters. Get-Service and process enumeration may incur OS
latency. There is no cancellation/termination of a pending native observation.
No interpretation that these extra snapshots establish identity continuity or
creation provenance is permitted. A later matching snapshot does not repair the
failed gate, and disagreement is observational evidence only.

## Verification
Actual Prepare AST executes with existing mocked system boundaries and a throwing
new collector. All previous trace/outcome/exception-identity assertions remain;
additional assertions verify failure-only invocation, including no capture after
marker/receipt failures or successful registration. A separate executable fixture
loads actual renderer/coordinator functions, replaces only read boundaries, checks
two samples/exact selectors/error isolation/66+ assertions, rejects raw malicious
strings and malformed primitives, caps rows/output, and exercises sink failure.
Native adapter bodies are read-only code-reviewed; these mocks do not establish
real Windows observation accuracy. Windows PS5.1 and failure-triggered CI evidence
remain necessary after integration.
