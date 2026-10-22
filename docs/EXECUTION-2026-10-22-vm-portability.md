# Read-only VM/media/global-registry audit and Manager clean-state stabilization

**2026-10-22.** Branch `dev/modernization-2026`, Draft PR #7, no release or master merge.

The ordinary diagnostic launcher can now inspect `data/Machines/**/*.vbox`, count snapshots/media and warn about missing/external disk paths. A separate read-only inspection of `data/.VirtualBox/VirtualBox.xml` detects machines registered outside the portable data root, unregistered .vbox files and malformed/unsafe XML. Neither parser opens external media, rewrites XML, starts Oracle or installs drivers.

An offline `data` backup with an incomplete/unsafe inventory now requests explicit GUI confirmation; the CLI warns to stderr. **The backup is still a file copy of data only**, not a full VM snapshot or migration.

A separate non-distributed Manager experiment now holds its cross-root lock after helper teardown until services and processes remain absent for 2.5 seconds, with a bounded fail-closed wait. This avoids claiming a completely clean host too early; a transient conflict can be retried only with fresh preflight. No production UAC/Windows 11 approval is claimed.

**Evidence:** [native VM catalog 39790407525](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39790407525) 23 native harnesses passed; [compiled RU/EN 39790408168](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39790408168) passed; [full Manager repeat-cycle 39791350463](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39791350463) passed; [real Oracle-produced .vbox 39791602687](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39791602687) passed; [backup warning x64 39792091758](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39792091758) passed. Registry extension [e8732507](https://github.com/zlocorp/Portable-VirtualBox/commit/e873250753036d47b5d8be3a2a6b09812f59cc07) passed 157 local Python tests (5 platform skips), with new Windows CI still required at report creation. Later CI updates must reference the exact checked commit, not rely on prior test results.

**Still missing:** complete VM-media chain validation, external-disk backup, VM registration rewrite, ordinary-user driver Start/Stop, interactive Windows 11 UAC, physical power-loss recovery and guest OS/disk acceptance.
