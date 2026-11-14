# Preserve cleanup evidence on final observation failure

The full VBoxSup cleanup script previously queried the service namespace again
inside its `finally` block without handling observation failure. If that query
failed, it prevented `cleanup-results.json` from being written, discarding the
original operation error and the available completed-step evidence. A service
appearing between the terminal check and this last observation could also leave
`cleanup_verified=true` beside a nonempty final service list.

Finalization now keeps the original error and step results, records an unreadable
service namespace as `final_vbox_services=null` with observation `UNKNOWN`, and
sets `cleanup_verified=false`. A successful observation is marked `OBSERVED`;
a nonempty list also invalidates cleanup and adds an error. Observed absence
never upgrades a previously unverified cleanup. A report write failure is still
fatal and must not be represented as saved evidence.

The regression fixture extracts the actual top-level production `finally` AST.
It exercises failed and partially emitted queries, observed presence/absence,
prior verified/unverified cleanup, initial clean/error reports and failed report
writes. The observer is synthetic; only temporary report files are written.
No registry, service, driver, Oracle or elevated operation is executed by the
fixture. Windows PowerShell 5.1 execution is included in native CI.

This is diagnostic preservation, not an operational retry protocol. It does not
provide resource continuity, reacquire authority, repeat system commands, create
a payload checkpoint, authenticate reports, or promise crash-atomic report
storage. The remaining general SYSTEM cleanup retry and isolated Windows 10/11
release gates are unchanged.
