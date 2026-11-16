# Bounded log evidence for exactly the disposable fixture VM

The main-GUI NEM start refusal at 5be0d6e retained VBoxManage stderr but not the
per-VM VBox.log. The global VBoxSVC/selector logs did not explain that refusal.

Both disposable fixtures now make a binding before their existing createvm call:
only their fixed VM name, expected root-local machine directory (which must not
preexist), and the UUID returned by that call. The final diagnostic export does
not enumerate machines or accept arbitrary source paths. It checks the one fixed
`.vbox` file's UUID with a bounded XML parser and disabled DTD/external resolution.
Missing binding/config/log produces explicit metadata without adopting another VM.
Existing reparse components are refused. These are observational fixture checks,
not an atomic identity protocol or production security capability.

Only `Logs/VBox.log` is read, shared with an active writer. A seek and fixed-size
buffer retain at most the final 128 KiB from the initially observed file length.
No config, disks, rotated logs, backup trees, other VMs or guest file contents are
copied. Tail truncation, offset and observed length are recorded. A shortened read
is an error, not complete evidence; growth after the length observation is not
claimed captured. Output files are CreateNew, never replacement of earlier proof.

The existing collectors already export bounded txt/json files from the fixture's
own proof folder. Metadata uses the fixed relative log name and stable error
classification, not raw exception messages or dynamic config contents. Export
failure is separately recorded and cannot replace the original fixture failure,
turn an unsuccessful VM start into a pass, or authorize any retry/system effect.

Executable filesystem tests cover zero/exact/oversize log boundaries, exact tail
bytes, missing config/log, foreign UUID/name/root, preexisting folder, XML entities,
oversized config, reparse files and immutable previous output. Real Windows CI
must verify the exporter against an actual created VM; a missing log remains a
useful explicit observation, never a reason to relax the start gate.
