# Full-owner import-fault execution ledger

- [x] Identify actual uncovered RunCore branches and distinguish prior synthetic adoption.
- [x] Draft narrow test-only design; independent review requested before native execution/publication.
- [x] RED source-preservation/build/wiring tests.
- [x] Exact reversible source generator; temporary artifacts only.
- [x] Two native-boundary modes and failure-safe closed-child harness (not native-executed).
- [x] Nine source/managed/runner-contract checks and .NET Framework 4.8 compilation pass locally.
- [ ] Independent implementation review.
- [ ] Exact-source disposable Windows run and log/artifact audit.

No production hooks, package inputs, replay permission, services or drivers change.
Native execution and complete ownership-path acceptance must not be inferred from
local compilation or instrumented source tests.

Review corrections: real FALSE requires all four PROCESS_INFORMATION outputs zero;
unknown Thread.Start is entered before invocation; duplicate readiness is separate
from nonzero handle bits; native exit-code success is required even if a failed
query supplied output bits. Observer duplicate and retained foreground readers
are reclaimed only by test-host exit after natural child exit proof. No explicit
observer close, production disposal, private owner flag observation, native fault
coverage outside the two modes, or interactive workstation result is claimed.

Cross-thread integer observations use explicit Volatile.Read; no reliance on
Thread.Sleep or ThreadState as a publication barrier. LF and CRLF checkout bytes
are each preserved exactly, mixed line endings refused.

## Separate TRUE-alias extension (base 2465798)

- [x] Design review: import-only Thread=Process after genuine snapshot/observer.
- [x] RED alias wiring and runner modes; implement normal and expected-negative hosts.
- [x] Explicit genuine distinct-valid versus injected equal handle assertions;
      owner wait/create/close/exit-query and retention checks before/after child exit.
- [ ] Final local full suite and independent implementation review.
- [ ] Exact-source disposable Windows execution and evidence audit.

This extension does not claim invalid-output or unknown-return coverage. Its
Windows result must not be inferred from the preceding two-case CI. Production
source and reversible declaration transformation are unchanged.
