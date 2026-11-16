# Observed guest console readiness in disposable fixtures

## Confirmed failure

Run 43844144887 at 66647ba failed the mandatory offline VDI marker readback.
Its screenshot shows the disk command at `localhost login:` followed by a password
prompt. A fixed delay had sent `root` before login was ready. This is evidence of
an input-readiness failure, not evidence that cleanup lost guest disk data. The
old `guest_disk_write_checked` flag was also incorrectly based only on a valid PNG.

## Narrow replacement

Use Oracle's existing screenshot command and an exact decoder of independently
measured glyph observations from this project's own guest screenshots. No font
source/table or OCR dependency is imported. The fixture supports only the known
Alpine 1024x768 console with 8x16 cells. Unknown glyphs are never guessed; other
boot geometries remain not-ready. Each poll saves the screenshot and decoded text.

Wait for an exact last nonempty login prompt before sending root once. Then wait
for an exact last nonempty root shell prompt before sending the disk command once.
After successful `dd` and `sync`, printf emits a fresh nonce with a fixed prefix.
The prefix and nonce are separate command arguments, so the input echo cannot
contain the accepted full acknowledgment. Require the exact standalone nonce line
immediately followed by the shell prompt. Timeout refuses the fixture, never
retries the write. Only then set the write-request acknowledgment flag.

The original offline raw-sector comparison after full teardown is still mandatory
and is the disk-preservation authority. The acknowledgment JSON explicitly says
that it has not itself verified offline readback. No production code, helper
admission, effect replay, guest ISO verification or host permissions are changed.

## Verification and limits

Managed checks decode the actual success and command-as-login failure frames and
reject stale prompts, command echoes, missing/foreign/stale acknowledgments,
unknown prompt glyphs and unsupported geometry. Controlled orchestration checks
observe the delayed-login sequence and one-shot guest input. Windows native CI
also exercises the real System.Drawing PNG loading path. The two real integration
workflows must still pass with exported observation/ACK evidence and offline bytes.

This is not a general guest console reader, security authenticator, interactive
UAC acceptance or an arbitrary font/resolution solution. The fixed guest controls
its display; its acknowledgment is only fixture sequencing evidence, not trusted
storage evidence. A changed font/display must fail rather than fall back to blind
input or inferred success. Observation deadlines are bounded per phase; each
existing Oracle invocation retains its separate command timeout.

A shared budget allows at most 30 screenshots across all phases, each at most
256 KiB and 4 MiB accepted PNG data in total. Size checks precede image decoding.
Oversized newly generated fixture screenshots are removed after bounded refusal
metadata is saved; prior observations are never overwritten. If that removal
fails, the gate remains failed and the one rejected frame may remain until runner
teardown. Poll intervals are two seconds; the nominal 90-second phase timeout can
be exceeded by the existing bounded 40-second Oracle call, so it is not described
as a hard wall-clock deadline. Count/byte exhaustion never resends keyboard input.
