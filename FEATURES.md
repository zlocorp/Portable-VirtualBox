# Features and differences from the original

Updated **2026-10-21**. The comparison baseline is upstream `vboxme/Portable-VirtualBox` at `5b58dbbe701c3e2eb348942a9059708063b0cb96`, not every community fork. This branch is still a **diagnostic development preview**, not a replacement for an existing working launcher.

| Capability | Current status | What that means / evidence |
| --- | --- | --- |
| Native RU/EN shell and UTF-8 CLI | Public preview | Locale switching, diagnostics, copy report, localized readiness; `LauncherI18n.au3`, native catalog tests |
| Remember language / restore Windows language | Public preview | Explicit save only, portable `data/launcher.ini`; Deac2-inspired independent adaptation; native + compiled public CLI tests |
| Report all missing runtime files | Public preview | 15 required EXE/DLL/driver inputs; regular/nonempty paths; **not signature verification**; `PortableApp.au3` |
| Identify missing portable directories | Public preview | Names `data/Machines` etc.; preparation preserves existing user data |
| Distinguish Manager / guest / background processes | Public preview | Query-only diagnostic snapshot; not VM state or teardown permission |
| About, authors and reuse notices | Public preview | Concise GUI/`--about`; detailed authors and component notices in one CREDITS file, also included in ZIP |
| Legacy binary-free source/build | Implemented | Old AutoIt/7za/DevCon/SnetCfg removed; signed external compiler; source-tree guard |
| Oracle 7.2.22 verified file-only preparation | Developer tooling / CI | Exact pinned official package, MSI/CAB extraction, hashes and publisher checks; not a user-facing installer |
| Empty VM boot and own-resource teardown | CI-only | Actual compiled AutoIt and signed VBoxSup on disposable Windows Server; not a shipped user flow |
| Controlled powered-off root/drive relocation | CI-only | Fixture UUID/data preservation; not general cross-host/snapshot migration |
| Manager Start / Finish / Reopen and guest-aware cleanup | **Integrated experiment, CI verified** | Real compiled GUI + Oracle Manager; live VM preserved, second controller refused, two clean sessions/same UUID; separate non-distributed EXE, not production UAC |
| Production Manager/VM Start/Stop | **Not yet enabled for ordinary users** | Integrated experimental frontend now works; the privileged adapter and Windows 11 standard-user acceptance remain open |
| Separate elevated helper / normal-user UAC | **Partial, CI-only** | Fixed helper plus protected Oracle runtime: medium-privilege Manager/guest, forged-input refusal, denied protected writes and two clean cycles verified in [39649261984](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39649261984). Interactive `ShellExecuteExW runas` delivery remains **unverified**: [39649261666](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39649261666) failed with the frontend still `IDLE`. Not a production UAC approval. |
| Existing VM import, snapshots and media-chain migration | Planned | Read-only inventory foundation exists; no automatic rewrite or unregister/delete |
| Transactional Oracle updater / rollback | Planned | Download/extraction safeguards exist; no complete end-user updater |
| USB passthrough / bridged-network driver management | Deferred | No automatic installation of extra drivers |
| New community icon/splash | Not adopted | Optional artwork/license review; old splash was removed |

## Substantive architecture changes

Compared with the inherited launcher/build, this branch removes bundled old executables, separates file preparation from system installation, uses explicit process observations and refuses unknown states rather than guessing. The public GUI does not request blanket administration. Ordinary data setup is explicit, and reused work is credited in CREDITS without adding contributor lists to the interface.

Those are engineering differences, **not a blanket security certification**. Signed external packages do not make the unsigned launcher trusted, and its CI-only environment markers are not an access-control boundary.

## Verification boundaries

Linux tests exercise parsing, packaging, hashes and contracts. Native Windows tests execute compiled AutoIt helpers. Public CLI tests exercise a separately launched EXE across restarts and root relocation. Real driver/empty-VM experiments use disposable Windows Server hosts only. GUI visual/DPI review, Windows 11 standard-user transitions and real guest OS/disk acceptance remain pending.

[Community adoption ledger](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/COMMUNITY-ADOPTION.md) · [Changelog](CHANGELOG.md) · [Credits](CREDITS.md)
