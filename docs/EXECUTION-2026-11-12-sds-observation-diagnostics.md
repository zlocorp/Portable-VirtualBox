# SDS observation diagnostics: accepted hosted checkpoint

## Current decision and historical boundary

Independent source, native/build, system/payload and ALPHA file/build reviews
accept the bounded diagnostic increment at
[`fc6abadde89feda0c86a741a4e21fe2afabd0976`](https://github.com/zlocorp/Portable-VirtualBox/commit/fc6abadde89feda0c86a741a4e21fe2afabd0976),
tree `6fd4627bcef4c3769858c29aa5c60323e2479fdd`. All **12 natural workflows
succeeded on attempt 1: nine push and three pull_request runs**. No rerun-for-green,
manual dispatch, cancellation or assertion weakening occurred.

**The changed-source diagnostic/native prerequisite is accepted. Test-only Task
2D may resume, but is still unimplemented.** Task 2E's actual native composition,
schema-2 validator/status-guard integration and whole-composition independent
review remain required. No Task 2D/2E checkbox or production/release gate is
completed by this record. This is the subsequent next-stage decision after the
scoped audits, not a change to their earlier pause or to historical outcomes.

The [6a164db partial checkpoint](EXECUTION-2026-11-11-exclusive-image-ownership-partial.md)
remains **ten successes/one failed payload Prepare, all attempt 1, zero completed
continuation cases**, absent verified teardown/final data-preservation proof and
unknown registration cause. Its first Prepare reached VBoxSup staging/start but
found no SDS key after a success-like process branch; no numeric SDS exit was
independently persisted. Initial false proof fields are not evidence of data loss.
New successful executions do not establish a causal fix or authorize cleanup of
that ambiguous state. The [b2229c5 failures](EXECUTION-2026-11-11-native-fixed-image-file-only.md)
also remain unchanged.

Independent harmless fixed-fixture work can continue because the new source has
its own accepted native prerequisites, regression/refusal evidence and observed
hosted payload completion. It neither depends on explaining the old registration
failure nor changes production registration/recovery authority. Work stays on the
Draft development branch. No merge, release, production integration, valuable-VM,
primary-host or user-Windows permission follows.

## Immutable source and change scope

The [published delta from 6a164db](https://github.com/zlocorp/Portable-VirtualBox/compare/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff...fc6abadde89feda0c86a741a4e21fe2afabd0976)
changes three code/test paths: the bounded diagnostic renderer/writer and capture
of existing facts in [privileged_session_worker.ps1](https://github.com/zlocorp/Portable-VirtualBox/blob/fc6abadde89feda0c86a741a4e21fe2afabd0976/scripts/privileged_session_worker.ps1),
Windows behavioral fixtures in [check_driver_start_gate.ps1](https://github.com/zlocorp/Portable-VirtualBox/blob/fc6abadde89feda0c86a741a4e21fe2afabd0976/tests/windows/check_driver_start_gate.ps1),
and [source-contract tests](https://github.com/zlocorp/Portable-VirtualBox/blob/fc6abadde89feda0c86a741a4e21fe2afabd0976/tests/test_driver_start_gate.py).
Four documentation paths record the earlier ownership checkpoint. Existing native
fixture/owner sources, schemas, workflows and helper packaging code are unchanged.

- Worker Git-LF SHA-256: `56b978a66a2a961fc663629d41d444634e885ed0cc2eb27193842c9e5a0bd6a9`.
- Windows gate fixture SHA-256: `e90ee7d8e05afc44e3300a7f6d72cb063634353d826d331ff1e1596b07711f19`.
- Native push actually checks out the published SHA. Native PR actually checks out
  synthetic merge `55d3cc09167c0da68c50082deac37d9ac998fb39`. Its
  [Git object](https://api.github.com/repos/zlocorp/Portable-VirtualBox/git/commits/55d3cc09167c0da68c50082deac37d9ac998fb39)
  has the identical tree and ordered parents
  `5b58dbbe701c3e2eb348942a9059708063b0cb96`, then `fc6abadde89feda0c86a741a4e21fe2afabd0976`.
  Standard push/PR build logs preserve the same direct-head/synthetic-merge
  distinction. Same-tree PR evidence is not a direct-head checkout.

## Complete natural workflow inventory

The [full-head inventory](https://api.github.com/repos/zlocorp/Portable-VirtualBox/actions/runs?head_sha=fc6abadde89feda0c86a741a4e21fe2afabd0976&per_page=100)
contains exactly these 12 final runs. A PR-only list omits nine push runs. Each
row has the published head SHA, conclusion success and attempt **1**.

| Workflow | Event | Run | Result / attempt |
| --- | --- | --- | --- |
| Commit-bound source snapshot | push | [43137192480](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192480) | success / 1 |
| Fixed helper with medium user processes (no UAC acceptance) | push | [43137192387](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192387) | success / 1 |
| Guarded rollback after interrupted VBox driver preparation (disposable host) | push | [43137192482](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192482) | success / 1 |
| Noninteractive UAC pending (no consent acceptance) | push | [43137192448](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192448) | success / 1 |
| Workstation alpha candidate (build and server refusal only) | push | [43137192469](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192469) | success / 1 |
| Native AutoIt policy regressions | push | [43137192595](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192595) | success / 1 |
| Exact-owned orphan cleanup after abandoned controller (no UAC acceptance) | push | [43137192656](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192656) | success / 1 |
| Portable-VirtualBox CI (build only) | push | [43137192540](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192540) | success / 1 |
| Private payload cleanup continuation (disposable host) | push | [43137192517](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192517) | success / 1 |
| Native AutoIt policy regressions | pull_request | [43137201161](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201161) | success / 1 |
| Verified Oracle package preparation (no installation) | pull_request | [43137201330](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201330) | success / 1 |
| Portable-VirtualBox CI (build only) | pull_request | [43137201126](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201126) | success / 1 |

Detailed artifact audits cover native/build, the system/payload jobs and ALPHA
below. Source-snapshot and Oracle-preparation success in this table are inventory
findings, not a new detailed audit of those two workflows' artifacts.

## Actual Windows and Linux execution

Both native jobs ran on **Windows Server 2022 Datacenter 10.0.20348**, image
`20261101.353.1`, with **Windows PowerShell 5.1/Desktop**, CLR `4.0.30319.42000`
and `mscorlib`. Neither is a Windows 10/11 workstation. The named non-ASCII
Framework bridge assertion actually ran and passed once per job: `C:\é` versus
`C:\É` returned true through the fixed Windows adapter, after portable proof was
refused. Observed Framework Release is **533509**; the gate is **>=528040
(Framework >=4.8)**, not an assertion of exact Framework 4.8.0.

The retained runtime inspection records System assembly 4.0.0.0, MVID
`9c83289f-802b-45ce-b0d0-615c55db0a6c`, file version
`4.8.9363.0 built by: NET481REL1LAST_25H2_B`, on-disk SHA-256
`15adc79ede47ebfa67c9cbac1bfdc98493cddfcdff743fcfc10f4be4224a14aa`.
Its status is bounded-truncated. Its compatibility OS string is not runner OS
identity; the disk hash does not attest loaded-module association, and ordered
calls alone do not prove complete control flow.

Both standard Linux discoveries provisioned the pinned net48 references and ran
**430 total tests: 423 passed, seven skipped**, in 85.748s (push) and 54.976s (PR).
The skips are three cabinet path/workspace cases, Windows main-manager execution,
two native cabinet/API cases and the Windows-only Framework bridge. No missing
compiler/reference skip is hidden. Linux managed compilation is not Windows
execution; the Windows bridge was separately observed above.

Both standard Windows compile jobs and their artifact checks passed. The actual
compiled harmless selftest, RU/EN diagnostics, GUI switching, first-run/collision,
inventory/refusal, relocation/backup and Unicode-root setup modes executed despite
the workflow's build-only wording; they did not launch a VirtualBox VM. GUI JSON
contains 25 controls per RU/EN/return view; only the 16 Button captions have
actual font-fit measurements. Subsequent independent inspection viewed all six
686 × 843 PNGs and found no blocking caption clipping, overlap or Cyrillic defect.
Each run's Russian return PNG and full 25-row JSON are byte-identical to its
initial Russian view. This closes only those captured views' pixel inspection,
not workstation, DPI, Oracle, UAC, accessibility or portability acceptance.
Two minor Russian wording suggestions (GUI/headless jargon and the outside-data
backup warning) remain unimplemented; no GUI source changed.

## Windows managed SDS fixtures with substituted effects

Both real Windows PowerShell steps execute the changed renderer/writer, original
Prepare/Run-Sds bodies and actual collector AST selection. Their system/process,
registry and filesystem boundaries are substituted with controlled fixtures; the
elevated worker preamble, Oracle registration provider, SCM and real drivers are
not run by these managed tests.

Each job reaches the unique renderer PASS producer after eight derived/inherited
CLR invocations and fourteen ScriptProperty/NoteProperty regressions. Hidden CLR
getters receive zero callbacks; base HRESULTs -17/-18/-19 and missing-key facts
remain correct. Reads use six fixed nonvirtual base-member descriptors, not
input-selected getters. ErrorCategoryInfo has no genuine public/protected subclass
fixture; fixed-base descriptor and extended-member checks are the coverage limit.

Each job has **47 ordered Prepare characterizations**, **29 captured-pair
summaries**, eleven collector-selection refusals, and actual refused-Prepare
export of two records/497 bytes. Early/no-launch/render-failure cases intentionally
lack captured-pair summaries. All 47 traces retain SCM=0, at most one launch and
the original registry/normal exit read. Late0/Late5 retain completion wait and no
late ExitCode read; LaunchError is not proof that no child was created.

The real writer permits two ASCII, non-authoritative records, **1024 bytes each /
2048 total including CRLF**, at most two non-retried writes, and conservative
missing/unknown values without raw private-value rendering. Export preserves the
original refusal and intent/stage/start evidence. The strict whole-file cutoff
includes 262143 bytes and excludes 262144; nested app64 is omitted. Harmless
helper-*.exe text is intentionally selected, so this name/size collector is not a
general executable-content filter or arbitrary-source sandbox.

## Preserved native observation suites

All ten native ZIPs pass independent metadata size/SHA-256, CRC and extracted-byte
checks. Each run's **55 JSONL records** matches exactly once as entire
timestamp-stripped native-log payloads: 20 launch, 16 pipe, ten capture, four
environment and five image records. Strict capture/environment/image validators
run with require_pass=True; the strict pipe validator passes. Counts, hashes,
framing, lifecycle accounting and file probes were independently reconstructed,
not inferred from PASS fields.

- **Nine capture cases:** Empty, Binary, Large, Nonzero, Exit259, PostCreateFault,
  CaptureFault, EvidenceFault, WithheldEof. PVC2 header remains
  `50 56 43 32 01 00 00 a5`. Binary emits 4105/257 bytes with FNV-1a64
  `031381f5c4fbe740` / `c98455caf71ceb86`; Large emits 196739/204829 bytes with
  `c1f1accadf2339e9` / `8b07499bc23a9f3e`. Empty is 0/0 with both empty hashes
  `cbf29ce484222325`; Nonzero/Exit259 preserve actual exits 23/259. All cases
  retain both EOFs, observed exit, one-shot refusal and released ownership.
  The four fault/withheld-EOF cases stay UNKNOWN; whole-stream counts/hashes do
  not replace raw streams or prove every child-side/CLR-internal close.
- **Three environment cases:** None, AfterCreate, Evidence. Strict base64/PVE1
  decoding preserves version 1/mask 30/five fields/exact EOF, 110 payload bytes,
  absent parent sentinel, Unicode value, present empty value and both Windows
  directory values. Stdout is 118 bytes including PVC2; stderr is empty. Exit,
  parent/environment restoration and release are verified. Only None is OBSERVED;
  AfterCreate/Evidence remain UNKNOWN.
- **Four standalone image cases:** matching-image, digest-mismatch, size-mismatch,
  missing-image stay **schema 1/stage file-only**, create_calls=0,
  process_observation=null and mutation_authorized=false. Pristine size is 19968;
  same-size negatives are fully hashed, size 19969 is refused before hashing and
  missing-image reports error 2. Unicode file paths, held file ID/volume, positive
  one-byte EOF request/zero return, error-32 write/DELETE probes with share=7 and
  OPEN_EXISTING, checked closes and readiness revocation remain verified.
  Push/PR builds are independently generated, not assumed byte-reproducible.

Each run also retains one injected-owner PASS following six real-owner contract
methods with substituted native calls and genuine pristine bytes. The standalone
native harness uses CreateForObservation, never ClaimForComposition, and launches
no child. Pipe coverage remains 14 cases/573 checks/all owners released; launch
coverage remains 64 managed checks/zero native calls then 232 native checks/11
calls. These are not Task 2D composition or Task 2E schema-2 acceptance.

## Real protected SDS output and nine payload continuations

Separate real disposable-host executions exported **16 protected-worker diagnostic
pairs**: four fixed-helper successful Prepares, one orphan Prepare, normal and
tampered interrupted Sds Prepares, and nine payload Prepares. Each pair is
**254 process bytes + 227 registry bytes = 481 including CRLF**, fixed ASCII
without extra fields, private filesystem paths, SIDs, raw registry strings or exception text in these
new records. Existing receipts/error files are not claimed to be path-free.

Every pair records returned launch, nonzero handle, within-deadline wait,
confirmed completion and **measured exit_code=0**, deadline 30000ms. The original
registry gate observes absent preflight then a matching requested image, type 16,
start 3, LocalSystem and identity_match. Registry success uses the conservative
error=unknown/exception_hresult=unavailable vocabulary. Actual elapsed values are
168–312ms; these samples do not establish a hard runtime bound.

Unlike the old success-like control-flow inference, the numeric exit is captured
at the original exit read and survives in helper-owned stdout. Both
**launched_image=not_observed** and authority=none remain explicit. Registry
matches_requested compares against the requested path; it is not running-image,
PE/hash or process-image identity attestation. A nonzero handle does not supply
that identity.

All fourteen fully prepared sessions emit success before the two optional records.
The two Sds interruptions retain their SDS marker, no session receipt/success
marker, original controlled exception, worker exit 1 and helper refusal. Stage/
Start interruptions emit no SDS records because SDS was not reached. The helper
persists these streams only after retained worker exit; actual exported bytes and
upload metadata were checked.

| Payload case | Cycle | Final ledger | Exported prior hashes unchanged |
| --- | ---: | --- | ---: |
| AfterFirstDelete-Finish | 41 | 220 objects / 441 events / COMPLETE | 28 |
| BeforeMarker-Recover | 42 | 220 objects / 441 events / COMPLETE | 28 |
| BeforeStdout-Finish | 43 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeStdout-Recover | 44 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeStderr-Finish | 45 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeStderr-Recover | 46 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeFacts-Finish | 47 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeFacts-Recover | 48 | 220 objects / 441 events / COMPLETE | 27 |
| BeforeFacts-Recover-InitialRecover | 49 | 220 objects / 441 events / COMPLETE | 27 |

Every ledger's hash chain, ordered BEGIN/DONE pairs, terminal COMPLETE and binding
to its owner/checkpoint/plan were independently verified. Plans were reconstructed
from the genuine 185-file Oracle manifest, .prepared.json and six exact published
helper resources with Windows CRLF. Each case preserves exactly two original
worker journals: Prepare and original system teardown (eight Finish, one initial
Recover), both observed worker exits 0 within deadline. The deliberately
interrupted teardown journals remain INTENT/WORKER_EXIT only, without fabricated
HELPER_COMPLETE. Continuation creates no additional worker journal/system-operation
evidence; payload completion has its own ledger/marker. The initial-Recover case
retains distinct original-owner and initiating-controller generations.

All **245 exported prior hashes** match. Four raw stage/start streams per case
are intentionally not exported: those 36 comparisons remain executed on-host
assertions, not independently downloaded bytes. Initial pending/interrupted ledger
states were asserted on-host; final artifacts retain the completed ledger, not
separate initial-ledger copies. Seven cases still lack exactly their injected
diagnostic file, with the expected controlled-interruption error preserved.

Final receipts and independent resource checks confirm SDS CLEAN, package removal,
empty VBox services/errors, no system driver/INF, absent app64/code and no transient
recreation/watcher overflow. The original VM sentinel is hash-checked after every
case. All nine finish before final data-preservation, unchanged-evidence,
no-recreation and owned-services-removed booleans become true. Payload guest boot
and interactive UAC remain false/noncoverage.

The other system audits retain both helper variants' two clean cycles and live
guest refusals, main-launcher Alpine VDI write/readback and snapshot proof,
Stage/Start/Sds recovery, live-owner/missing-receipt/replay refusals, explicit
absent-owner orphan recovery and tamper-stage/tamper-Sds refusals with resources
intentionally retained. All 99 reviewed frontend/Manager/CLI/guest token captures
are medium/non-admin; 39 helper facts are high/admin. Direct elevated invocation
is not interactive UAC. The pending-UAC UI probe proves responsiveness only,
without consent approval/cancellation or system Prepare.

## Exact ALPHA file/build provenance, not runtime acceptance

The natural ALPHA run's actual package passes full outer/inner ZIP CRC, exact
member inventory, reconstructed ten-row SHA256SUMS and uploaded verification-JSON
checks. Outer ZIP is 9576865 bytes; inner
Portable-VirtualBox-Win10-11-ALPHA-TEST-ONLY.zip is 9573997 bytes, SHA-256
`5846b64883d3353dba843a0c288bc7db83ef10dcc0ef70e4a667dd48c7b2b576`.
The flat inner layout has exactly eleven regular unique members: ten manifested
inputs plus SHA256SUMS.txt, 10487069 total uncompressed bytes. Inputs are the four
EXEs below, VBoxManage.cmd, ALPHA-TEST-ONLY.md, CREDITS.md, LICENSE.md, README.md and
README.ru.md. No extra Oracle/app64/driver/VM payload, logs, .git or loose
credential files are packaged. The helper intentionally embeds the six scripts.

| Executable | Bytes | SHA-256 |
| --- | ---: | --- |
| Portable-VirtualBox.exe | 1188352 | `e47b39bd3e4effdd60aed9b8b0323932a2fc2d2e7d3f5637bf20ab3df6e6ec59` |
| Portable-VirtualBox-Helper-Alpha.exe | 165888 | `f2f64c677cb52cc70446afc7e16509054a1e1f00291930c9126f9e55d65d14ff` |
| Portable-VirtualBox-Setup.exe | 9006895 | `75bf1970646527772c864045766b382b820c9984a281eedab7c48af692575ed8` |
| VBoxManagePortable.exe | 22528 | `585ecb912fabf807aa144dcb371ac991fcf131203b37d6917c547f85abde3c4e` |

Static PE/CLR inspection independently recovers helper/CLI constants:
FrontendName=Portable-VirtualBox.exe, the exact frontend hash above, Mode=ALPHA,
HelperName=Portable-VirtualBox-Helper-Alpha.exe and InventorySha256=
`7995ca1d963882b472e075db65dca7975cac2c6d3e587b76500a46bd9089bc60`.
That inventory pins Oracle 7.2.22, 185 files/247834716 bytes; installer SHA-256 is
`afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f`.

The helper has exactly these resources: privileged_session_worker.ps1,
vbox_sup_standalone.ps1, vbox_sup_start_owned.ps1, vbox_sup_cleanup.ps1,
vbox_sup_partial_cleanup.ps1 and vbox_sup_package_identity.ps1. Each equals the
published blob after only CRLF-to-LF normalization. The embedded worker is 30904
bytes/SHA-256 `30f53ee11a51f5dc12379301c30d04530adf3c63947a72da0ead05d62ef041b8`;
normalized, it is 30478 bytes and the corrected worker hash above. CLI has no
embedded effect-script resources. Packaged documents likewise match source after
CRLF normalization; VBoxManage.cmd is byte-identical.

All four AMD64/PE32+ manifests request asInvoker/uiAccess=false; all four have
zero embedded Authenticode security directories. **The candidate is unsigned,
ALPHA-TEST-ONLY, verified-non-release, with no runtime acceptance.** asInvoker
does not prevent inherited elevation or deliberate helper elevation. Ordinary
launch stays diagnostic with ALPHA mode false; explicit --alpha-runtime and
independent helper checks retain fixed filename/hash, paired helper, token,
workstation and session/user admission requirements.

Build logs/source report official AutoIt 3.3.18.0 with Valid signer guard,
PyInstaller 6.22.3/Python 3.12.10 and Microsoft-guarded Framework64 C# compilation;
the compiler certificate/archive was not retained for independent revalidation.
The setup was only statically parsed: 68 CArchive entries, 155 base-library ZIP
members and 129 PYZ module-table entries. No packaged executable was run by the
independent artifact reviewers. Eleven Python-only archive-verifier tests passed.
Full compiled-source equivalence, reproducible builds and absence of arbitrary
hidden binary content are not proved. The Server-refusal fixture's exit-9 and
specific service/driver/cache checks are narrow log-reported assertions, not a
workstation trial or proof of every possible effect.

Both ordinary preview packages separately pass checksums/CRC and their seven-member
allowlist, with no Oracle/legacy payload. Their launcher equals that run's compiled
launcher. Push/PR inner preview SHA-256 values are respectively
`95030b168a9259e140e2e525c505d822402d2f16f9c0191bb5d5afda10a8bccd` and
`2efd5d7d5f3b638ed1b6d3dd692cd37ef8c8e42735e569bc4ee5d48e9738a1a6`.
Independent builds have different hashes; no reproducibility claim is made.

## Selected artifact integrity anchors

The audits checked all **27 outer ZIPs** (ten native, eight standard build, eight
system/payload and one ALPHA), full lengths/digests against metadata and upload
logs, CRCs and actual member bytes. Selected anchors below make the proof
traceable without reproducing every inventory or raw protected record. GitHub
artifacts expire on 2026-11-19; a digest is integrity evidence, not a publisher
signature or runtime-safety guarantee.

| Scope | Artifact | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| Native push runtime | [13908121206](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192595/artifacts/13908121206) | 10116 | `a142918ab3b334333231705bfacfcbfcd1c29c77e7672a1cd51a4c04a28c2e38` |
| Native PR runtime | [13907618275](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201161/artifacts/13907618275) | 10104 | `2d4e373a3635636f9eca899a743854983eb1c6f972ef365b2c4eb63120d37adb` |
| File-only image push | [13908325739](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192595/artifacts/13908325739) | 963 | `6cf2163c45b733211507a51f2f056e4ccb8e578590f950686b2d9d7074354012` |
| File-only image PR | [13907932456](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201161/artifacts/13907932456) | 962 | `5b9cc5c8d71809ce3f56f4e445d73eca8f50f86f5cc3356d3142c2d37105e1a8` |
| Main-helper real system evidence | [13907014949](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192387/artifacts/13907014949) | 72439 | `01d5d112298bc6ce2cc2f4a732393ab26cbec96534f8f5370104b9212a182766` |
| All nine payload cases | [13908451380](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192517/artifacts/13908451380) | 493291 | `995698dc8d35704274eb706ea844b4426ac5e7c921bb414c12623f1d967daaa3` |
| Ordinary preview push | [13907569105](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192540/artifacts/13907569105) | 9479374 | `7d6d775d359bc911b4a07e23410935fde2513b866a99a81b8dbaa716b130232c` |
| Ordinary preview PR | [13908041989](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201126/artifacts/13908041989) | 9479753 | `696e274853d6a0c0c6a639cd558d7b37bd5de863ff1a9970718cb191c62311c9` |
| Captured GUI views push | [13908116346](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192540/artifacts/13908116346) | 101641 | `297ea1c252b0fa0f27c29e495c33cddf9d76d0dd7f6664db07e856e9766e5582` |
| Captured GUI views PR | [13908305873](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137201126/artifacts/13908305873) | 101668 | `4166ceb7b96ba52883d4206f81ba86c815aa65d31b852fff76a30a4c27c50080` |
| ALPHA outer package | [13907134192](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43137192469/artifacts/13907134192) | 9576865 | `51ca6fedf464ab2d712e38f0b9b9fbafe2ec1250deace3a49840aba2d2688f84` |

## Unchanged production and next-stage limits

- Facts reuse the original preflight, launch, retained handle, timed/completion
  waits, normal ExitCode read and registry identity gate. There is **no new
  SCM/registry/process/image query, registration retry, polling delay, cleanup
  authority or admission change**. Optional finally-reporting follows original
  markers/receipts or the original propagating error; unknown/mismatch still
  refuses. The fixed CLR-member correction changes only value normalization.
- Original gate/marker/error ordering and ambiguous-SDS partial-recovery refusal
  stay intact. The old failure's root cause is unknown; neither current numeric
  exit 0 nor upstream synchronous-registration source establishes a causal repair.
- Production outer-worker and nested SDS exceptional launch/handle/wait/dispose
  lifetime gaps, descendants/delegated work and owned-resource release guarantees
  remain open. A launch exception does not prove no child was created. The
  completion wait may outlast 30000ms; byte bounds do not prove hard latency.
- Diagnostics can be missing, partial, unpersisted or excluded by whole-stream
  cutoff. Actual current exports do not prove arbitrary disk/upload/abrupt-exit
  success, crash durability or atomic receipts. Unavailable-field tests do not
  inject actual Stopwatch/fact-copy failure; Linux fake HandleError behavior is
  baseline characterization, not Windows ownership acceptance.
- Standalone image/schema-1 and managed recording-call passes cannot satisfy
  schema-2 native transferred-image composition. Task 2D implementation, Task 2E
  native/schema validation and whole-composition review are still required.
- No Windows 10/11 isolated-host matrix, interactive UAC accept/cancel/secure
  desktop, full DPI/GUI acceptance, production integration, merge or release gate is
  passed. See [release gates](RELEASE-GATES.md), the [design](designs/native-fixed-image-observation.md)
  and [unchecked implementation work](plans/2026-11-11-native-fixed-image-observation.md).

These source-bound executions do not certify later documentation or source edits.
