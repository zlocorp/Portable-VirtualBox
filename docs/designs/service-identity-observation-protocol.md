# Isolated TEST-ONLY service identity protocol

No production sources are modified. A dedicated disposable Windows CI job executes the test-only protocol. These files are a candidate protocol, not a Windows API guarantee or permission to retry cleanup effects.

Files:
- tests/windows/ServiceIdentityObservationModel.cs: internal managed observation capability; no effect API, name lookup, durable import, ledger reset, or production wiring.
- tests/windows/ServiceIdentityObservationTests.cs + .ps1: adversarial capability/generation checks and real-thread query/close serialization.
- tests/windows/ServiceIdentityNativeTests.cs: guarded disposable CI draft, not executed locally. Creates only a random `pvbox-test-<GUID>` stopped service with a never-executed image path. No StartService, ControlService or VBox names. OpenService is restricted to a final read-only absence probe (SERVICE_QUERY_STATUS only). Uses only CreateService-returned service handles. One-shot DeleteService on CreateService-returned handles only; collisions abort without adoption/name cleanup. Final absence requires ERROR_SERVICE_DOES_NOT_EXIST (1060); ERROR_SERVICE_MARKED_FOR_DELETE (1072) receives bounded observation-only waiting. Other errors fail UNKNOWN. An unexpectedly opened service handle is only closed and causes failure, never mutation or adoption. It does not use a retained second keeper and does not test registry/driver-package ownership.
- tests/test_service_identity_protocol.py: managed execution and compile-only net48 checks for both programs.

Local validation: initial model stub produced the expected RED assertion `live exact handle observed`; implemented model then passed 45 checks. The executable model and native fixture compile against pinned net48 references. Native SCM semantics are not verified until the exact-source disposable Windows job executes. Local model results must not be substituted for that native evidence.

To run local model/compile checks, configure PowerShell and pinned net48 references as for the existing fixture suite, then run `python -m unittest tests.test_service_identity_protocol -v`. This does not execute the native SCM fixture.

Native draft intentionally requires Windows, GITHUB_ACTIONS=true, exact GITHUB_REPOSITORY=zlocorp/Portable-VirtualBox, RUNNER_ENVIRONMENT=github-hosted, RUNNER_OS=Windows, and the explicit --disposable-scm-identity CLI argument. Environment checks are an accident-prevention fixture guard, not a security boundary against forged environment variables. The test needs an authorized disposable elevated runner. The dedicated CI job has a five-minute timeout.

Important limits: observation context is not a security boundary against hostile code in the same process. Input service object is admission-observed, never creation-owned. Native fixture separately establishes create-returned-handle lifetime when executed, not production installer provenance. Later query success never changes OriginalStop and never grants mutation authority. Process-loss model invalidates the capability, but does not claim to emulate SCM process teardown. A throwing Close leaves the model terminal, not proof of successful native resource release. Original errors and cleanup delete/close failures are retained together in AggregateException; none authorizes retry. Native cleanup failures may leave a fixture service until disposable machine teardown. Final success is printed only after verified name absence and SCM close. Native error-injection behavior has not been executed or established by the compile-only check.


## Why this does not authorize cleanup replay

A CreateService-returned handle establishes a different provenance from opening
an existing name after an external installer. The latter does not prove our
session created the selected object. A retained handle postpones actual deletion;
it cannot be held blindly across SDS unregister or package teardown. A subsequent
successful status query cannot repair an unknown or failed stop outcome.

The fixture observes name absence at one instant, not a guarantee against later
privileged recreation. Same-object configuration changes, keeper handles, process
crash, injected native close/delete failures and PnP package identity are not
claimed covered. A lost process capability cannot be restored from a receipt.

Primary API semantics: [CreateService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew),
[DeleteService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-deleteservice),
[OpenService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openservicew),
and [QueryServiceStatusEx](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-queryservicestatusex).
