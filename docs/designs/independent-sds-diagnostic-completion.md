# Independent SDS diagnostic completion

## Failure being corrected

Sequential stdout/stderr collection and persistence could hide the available
second stream when the first failed. Disposal could also replace the original
completion exception. These are diagnostic failures, not permission to repeat an
admitted operation.

## Fixed scope

Collect each completed decoded stream independently, attempt the existing image
observation, and attempt persistence of each available stream. Preserve the first
failure. Encoding, write or flush failure in one channel must not suppress the
other. Consume the one-shot write flag before either attempt. CreateNew intent
files remain present and must never be reopened, replaced or truncated.

Attempt both owned-resource closes while preserving an earlier completion error.
Clear each file reference before closing it. Observe a successful attempt only
after completion and owned cleanup succeed; failures retain the existing failed
attempt ledger. Fixed commands, admission checks and unresolved-child ownership
are unchanged.

## Evidence and limits

Executable managed tests cover independent task failures, image observation,
persistence failure, invalid encoding, actual file write/flush failures, both close
attempts and one-shot behavior. The full bridge must compile against .NET Framework
4.8 and run in the existing disposable Windows integration workflows.

This is complete decoded-output preservation, not partial streaming capture. It
does not add a new task-wait deadline, expose every secondary failure, change outer
admission disposal, or establish safe post-effect retry. Windows CI and manual
workstation acceptance remain separate gates.
