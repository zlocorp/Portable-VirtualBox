# Managed fixture process-exit diagnostics

On source `5337ee62e25434fefb0da9ed8d0fa8604755b776`, the push
[native workflow](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/44165717758)
failed its managed owner step with process exit 5 after both
`FIXED_EFFECT_MANAGED_PASS` and `SDS_DIAGNOSTIC_FILES_PASS`. The log gives no
cause. The SDS marker was printed before its `finally` deleted a temporary
fixture directory, and therefore did not prove that `Main` returned. The PR
run of the same tree passed; that does not explain or erase the push failure.

The test-only harness now records bounded exit-status snapshots and return
markers after each managed `Main`. SDS cleanup logs entry and successful return
from `Directory.Delete`; the delete exception is not caught or suppressed.
Diagnostics do not assign `LASTEXITCODE` or `Environment.ExitCode`. The
regression checks absent and pre-existing nonzero `LASTEXITCODE`, plus simulated
Main and cleanup exceptions, without turning failures into success. Output and
additional reads can perturb timing, and future observations may still leave
an exit unexplained.

A separate, deterministic Linux PowerShell 7 experiment exposed a fixture bug:
a close-fault `FileStream` override could throw again from its finalizer. With
an explicit garbage collection in a separate process, the old fixture produced
an unhandled injected `IOException` and process exit 134; after limiting the
injection to explicit `Dispose(true)`, the same check completes and a test-only
counter confirms entry into the close-fault `Dispose(false)` path. The existing
assertion still requires the injected exception from explicit disposal. This
is evidence about the fixture, not proof that it caused Windows exit 5, nor
proof of any Windows access-denied error. No production service or driver code
is changed by this diagnostic increment.

Local controlled tests run on Linux PowerShell 7; the new Windows PowerShell
5.1 CI step and its exact-source outcome remain pending. Neither substitutes
for interactive Windows 10/11 acceptance.
