# Read-only inspection after partial cleanup

This developer diagnostic does **not** repair a session, retry cleanup, establish
ownership or certify the state of Windows. The operational cleanup/recovery
blocker in [release gates](RELEASE-GATES.md) remains open.

Use the repository's Python tool on an idle isolated test host, with the original
paired build and receipts preserved. Do not elevate it or change protected ACLs
just to make an unreadable input accessible. It is not included in the ordinary
or ALPHA ZIP and adds no helper command or automatic runtime action.

```powershell
python -B -X utf8 scripts/reconcile_cleanup.py "C:\ProgramData\PortableVirtualBox.Alpha\pvbox-manager-PID-CYCLE" --manifest "D:\OriginalPortableRoot\app64\.prepared.json"
```

Replace the example session and original manifest paths with the existing test
session's paths. The external original manifest is required even when the
protected `app64/.prepared.json` has already been removed. Its complete canonical
file inventory must match the repository's existing Oracle 7.2.22 pin. A missing
or modified manifest blocks the report; the observer never recreates it.

The tool compares expected `app64` files and the current build's fixed embedded
scripts with remaining files. It reports `INTACT`, `PARTIAL` or `FILES_ABSENT`,
missing-file counts/names, whether a protected manifest copy remains, and whether
small cleanup markers merely **claim** completion. Changed/extra files,
case-collisions, malformed JSON, links/reparse points, hardlinks, unreadable data
and detected mid-observation changes are refused. It reads neither VM data nor
arbitrary logs and prints no receipt contents, user SIDs or absolute paths.

Every JSON result has:

- `resume_authorized: false`
- `ownership: "UNVERIFIED"`
- `system_state: "NOT_OBSERVED"`
- `diagnostic_only: true`

Exit 0 / `REVIEW_ONLY` means the bounded file observations are consistent, not
that the resources are owned or Windows is clean. Exit 3 / `BLOCKED` means the
observation could not safely classify its inputs. Invalid CLI syntax exits 2.
`CLAIMS_VERIFIED` and `CLAIMS_REMOVED` describe JSON content only: the observer
does not authenticate its producer, inspect ACL ownership, query services or
prove that a driver was removed. Missing files may have many causes.

**Do not use the report to remove files/services, delete receipts, replay a
worker or complete a helper journal.** Repeated reads are not an atomic system
snapshot and do not protect against an administrator changing parent topology.
Preserve evidence and restore the disposable host snapshot when no already
supported safe recovery path exists. Safe mutation after arbitrary partial
cleanup still needs a separately reviewed, owner-bound per-effect protocol.
