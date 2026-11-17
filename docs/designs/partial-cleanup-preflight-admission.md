# Partial-recovery preflight before admission

After an interrupted preparation at a verified Stage, Start or SDS checkpoint,
the prior partial Recover wrote its one-shot proof before the partial cleanup
script checked the pinned package, services, controller and remaining receipts.
A read-only refusal could therefore consume admission before any cleanup effect.

The protected worker supplies a bounded prospective proof in memory. The partial
cleanup script validates the same proof and its existing owner, package, process,
service and checkpoint checks before creating the proof with CreateNew and
Flush(true). It checks conflicting markers and controller quiescence again at
the boundary. Immediately before each system effect it rechecks the relevant
service identities, status, receipts and exact package observations. These checks
reduce the observation interval; they do not establish resource continuity or
eliminate races. Once a proof exists, including after partial write or flush failure,
a later attempt refuses; it is never removed or repaired for retry. The legacy
file-proof path remains available under its existing checks.

This permits an explicit recheck only when partial cleanup has not been admitted.
It does not permit replay after a system operation has started, authenticate
resource continuity across attempts, or permit ambiguous SDS recovery. It does
not claim crash or power-loss recovery or make a release candidate acceptable.

The local fixture runs the production script with controlled observations and
effect tripwires for Stage, Start, failed-stopped Start and SDS, plus invalid
proofs, admission markers, writer failures, races and legacy file proof. It
performs no system operations. The disposable Windows workflow has a planned
locked-INF refusal and explicit recheck at each of the three real checkpoints;
its exact-source result and separate workstation acceptance remain pending.
