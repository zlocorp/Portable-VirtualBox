# Execution report: 2026-10-18

Status: **experimental implementation, runtime locked**.

## Repository safety / provenance

- Primary repo: `zlocorp/Portable-VirtualBox`.
- Original preserved `master` and independent archive `archive/legacy-zlocorp-2020`: `6b91c6d3f664535ab31a9038ada1db11c83bf5cc`.
- Clean upstream reference `work/upstream-baseline-2026`: `5b58dbbe701c3e2eb348942a9059708063b0cb96`.
- Implementation branch: `dev/modernization-2026`. No original personal patches merged; Deac2 code not imported.
- Draft review PR: [#7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) against clean upstream reference, **NOT** historical `master`.
- No merges to `master`, no official releases, no real VM/driver install.

## Evidence from GitHub Actions

Representative fully verified CI run at `a814170d6ac77a1d2d8110a29dd677f5650cc778`:
[GitHub Actions #39150301475](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39150301475).

- Python unittest: **13 tests passed**.
- Read-only audit and VM inventory tests: passed.
- Oracle `7.2.20` checksum-manifest retrieval: passed (metadata only).
- Selected Oracle installer: `VirtualBox-7.2.20-175154-Win.exe`.
- Oracle manifest SHA-256 for installer: `a81777d2b36380ce042a29e9c554cf032eb46a793f62e3cc82e7411e535c2c26`. **Installer not downloaded in the CI metadata check and not validated by Authenticode.**
- Windows Server 2022 hosted runner: official AutoIt 3.3.18.0 signed compiler discovered; x64 compiler execution and PE checks passed.
- Compiled binary `--selftest`: passed; `--diagnose`: passed; `--preflight`: correctly blocked incompatible hosted Windows Server 2022 with exit code 3.
- Normal-path EXE: 1,756,672 bytes; SHA-256 `129899fa8cdf72a8dd27252346490990e2cd355bdc802c419e22410a3b697b21`.
- Compiler run under a path containing spaces and Cyrillic: passed; output 1,756,160 bytes; SHA-256 `c0eeff683cd84a0faefc10c867a4b830a5b69c9acdc8d1e8e207718005847c25`.
- **These two builds differ in length/hash:** verified repeatable compilation but not bit-for-bit reproducibility. The reason is not yet established; do not represent these as reproducible outputs.

The branch also has later documentation-only commits excluded from CI through `paths-ignore`. No executable code changed in those commits.

## What exists

- Windows x64 build pipeline pinned to action commit SHAs; read-only audits and signed official AutoIt compiler; short-lived CI artifacts.
- A development safety gate prevents execution of the hazardous inherited runtime; no privileges required for diagnostic/test commands.
- Pure policy helpers for path traversal, ownership of services/processes and version-family gating.
- Read-only Windows host preflight detects Oracle installation, VBox services and processes.
- Independent SHA256SUMS parser and optional verified Oracle installer download; no execution.
- Read-only VirtualBox.xml inventory detects duplicate IDs, unsafe/external paths and missing local machine configs. No XML writes.
- Source audit, unit tests and explicit threat model.

## Not completed and not claimed

- Replacement runtime lifecycle implementation (driver creation, COM/VBoxSDS, cleanup ownership journal), safe extraction of 7.2, network/USB support, official release and migration.
- Real Windows 11 x64 hardware/VM tests, VirtualBox 7.2 system service/driver tests and installed-VBox coexistence validation.
- Oracle installer extraction/layout compatibility, and Extension Pack licensing/compatibility.
- Deterministic binary compilation.

**Do not remove the preview gate, use the build as a functioning portable hypervisor, merge into `master`, or publish a release until these gates have been completed.**

## Next work packages

1. Implement privileged lifecycle behind an auditable operation journal and *fail-closed* preflight, with offline simulations for partial success/failure and pre-existing resources.
2. Implement safe, version-aware extraction and optional signature checks for Oracle VirtualBox 7.2 without running installers by default.
3. Replace direct VM XML rewrites with planned operations and explicit backups; demonstrate no destructive behavior against fixture VM trees.
4. Run isolated Windows 11 x64 acceptance tests, then consider real-PC tests and a merge/release.

## Follow-up Oracle binary investigation

- [GitHub Actions #39150686025](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39150686025): downloaded the exact official 7.2.20 Windows EXE, verified its SHA-256 against Oracle's live checksum manifest **and verified Authenticode publisher signature**. Oracle-documented `-extract` did not exit in 120 seconds in an unattended Windows Server 2022 runner; only that launched process was terminated. No MSI was installed and no driver/VM tests were attempted. This investigation was marked failed, as extraction was not confirmed.
- [GitHub Actions #39150939847](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39150939847): repeat verified official download/signature; ran *passive* `7z l -slt` without executing the installer. 7-Zip inspected the wrapper but did not expose an MSI entry; **the package extraction layout is still unresolved**. The job succeeded as a bounded read-only investigation, *not* as proof of successful extraction.
- [GitHub Actions #39150939834](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39150939834): latest normal CI green after the one-off investigation workflow was updated.
- Future work must not treat `-extract` as headless-safe without additional investigation. Do not attempt to install Oracle drivers on GitHub Actions solely to force extraction.
