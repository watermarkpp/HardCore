# Cue Actor Retirement Handoff — 2026-10-04

## Scope and status
Task: cue-lifecycle-2c585-20261004.
Baseline: 2c58552d2d905eea1f5c13d38685f66c489b092c.
Worktree: C:/Users/Administrator/Documents/Codex/2026-10-04/task/HC-cue.
Branch: codex/collab-cue-lifecycle-20261004.
The controller requested freeze and integration after independently verifying RED/GREEN. No further source edits or native tests are authorized in this peer tree.
No push, merge, APK, or commit was made for this delivery.

## Confirmed defect and minimal repair
PresentationPort.start attached the real IgniteCue to the actor before registering its weak ownership in _nodes. SceneTree child_entered_tree notification is synchronous. A test observer called the existing real EffectRuntime.clear during this attachment. Logic retired, but presentation clear could not find the not-yet-registered cue. The returning start then registered the old cue and started prepared audio, retaining the resource lease.
The only production change is scripts/features/presentation/presentation_port.gd: register weak ownership before actor.add_child; after attachment, require the cue still exists, remains the same owned instance for that handle, and is not queued for deletion before starting audio. A retired/replaced onset returns true, matching the existing post-audio-notification cancellation behavior. It does not remove or stop a replacement's ownership.
scripts/features/presentation/ignite_cue.gd is unchanged. No HP, RNG, clock, runtime, registry, authoring, TTL, resource authority, or gameplay contract was added or changed.

## Authored tests
- tests/framework/feature_cue_actor_retirement_test.gd
- tests/framework/feature_cue_actor_retirement_test.tscn
- tests/framework/feature_cue_actor_retirement_reentry_test.tscn

The tests use the existing default-off feature's resource-cue validation catalog, real Root/Player factory, accepted nonempty resource lease and reservation ticket, real attack windup and base HP mutation, actual CanvasItem cue nodes, and existing prepared AudioStreamPlayer service. The child_entered_tree observer is deliberately injected to expose a real synchronous reentry boundary; it is not claimed to be a naturally occurring UI sequence.
Normal coverage: one cue/audio onset, refresh without replay, actual target queue_free, legal same declared slot replacement, old ActorRef invalidation, existing next-due-boundary retirement, unchanged replacement HP/RNG, repeated stop/clear, and weak lease release.
Reentry coverage: real runtime.clear during actual cue attachment, no late cue registration/audio onset, deferred cue destruction, and lease release.
Actor logic retirement follows the existing next-due-service boundary in the normal test; the real tree child disappears with actor destruction. Explicit clear is immediate. No timeout was added to production.

## Genuine RED
Evidence: outputs/cue_actor_retirement_20261004/red_20261004T171345Z_ef588a64/
Invocation: 1e48af78-ab9e-4b43-b1fd-29aad971cc01.
Source content fingerprint: fc14f3bd4494fcd4b94691b24e3a2fc594bff4dd99b9d33623c2a6450844375f.
Normal: 23/23 checks passed, natural native exit 0, PID 13156.
Reentry: 19 checks, 4 failed, natural native exit 1, PID 24084.
Both have complete corresponding receipts and zero engine errors. Source stable.
Failing labels:
- retired onset cannot register a late live cue after add_child callback
- retirement before audio onset cannot start or register old playback
- retired actual cue is destroyed after deferred deletion
- retired accepted lease is released without a surviving cue

## GREEN with unchanged assertions
Evidence: outputs/cue_actor_retirement_20261004/green_20261004T172103Z_2cab5ea9/
Invocation: a2bd7a5f-decf-4f6d-ac6f-71d6ed59ed9e.
Source content fingerprint: 82d2bab167c0b1667b5032ae3398fcfdd97ed47da219da9d73bb930389d87e23.
Normal: 23/23, natural native exit 0, PID 16104, exit observed 17:21:20.491 UTC.
Reentry: 19/19, natural native exit 0, PID 8280, exit observed 17:21:35.970 UTC.
Both receipts valid, source stable, no timeout, engine errors 0.
Tests and assertions were not changed between this RED and GREEN.

## Source fingerprints
Peer presentation_port before: 2bc7bcedd06305b1b2bd3cc66d6e652de75659a51753125049b731fa5dd2d00b (4074 bytes, CRLF).
Peer presentation_port after: 0bbcda6073f4a2155d09b039c7942c13941864e323b29db166f64ce44dea0cb1 (4384 bytes, CRLF).
Controller reported its original LF file was 3999 bytes with equivalent normalized content. Integration should preserve controller LF, not require peer raw hash equality.
Existing minimal patch: outputs/cue_actor_retirement_20261004/presentation_port.gd.20261004T172035Z.patch
Patch SHA256: 8b5496c9ff32cbe924b81d4b925c701192e8ccb9caa1de9b6d73e539d61e863e.

## Environment repairs are not production changes
The independent checkout initially lacked imported resources and had two identity-input raw-byte mismatches caused by checkout line endings. All bounded cache copies were separately approved by the controller and recorded with hashes; no entire cache, shared links, userdata, original media, class cache, or provider installation was used as a substitute for verification.
Two separately approved raw-byte input repairs remain in this worktree and must NOT be included in the production patch:
- assets/data/features/socketing_fixture_items.json — 410 bytes, ae2c7adbcf0ee9ed8e88f4e2dd8d4c4e2c55af6b49a7bcffc0828c8a29e23043
- assets/data/identity/item_categories_v1.json — 4025 bytes, c60d00da6b19047e87ea80b6c973e42a26c01f543d489fdb8b3ab64473adbb8a
JSON semantics equal baseline; original target bytes are backed up. All 15 registry input hashes then matched without changing registry or global Git config.
Imported products were reused from identical raw resources and the pinned existing engine. This is not evidence of a successful full cold first import.
All earlier environment failures, forced terminations, invalid/old receipts, output encoding failure, and NOT_RUN deadline skips remain in outputs. They are not counted as functional RED.
Pinned console SHA256: d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c; version 4.7.stable.official.5b4e0cb0f.
After reconnection, the sandbox account lacked default Python access. The existing absolute Python 3.12.7 path was successfully executed via the official require_escalated mechanism; no ACL/PATH/provider changes.

## Warnings and untested boundaries
Both genuine RED and GREEN scenes emit the same warning: 8 ObjectDB instances leaked at exit. This was not diagnosed or fixed; do not claim zero leaks globally.
This is real CPU/node/audio lifecycle evidence, not GPU pixel rendering or Android acceptance.
The prepared eleven-scene regression script was compile-checked and its scene paths verified, but the controller requested freeze and took integration before it ran. Peer regression status: NOT_RUN. Controller will test on its latest periodic/child baseline.
Existing cue/audio-onset reentry, multi-source cancellation, resource closure/acceptance, and periodic boundary/lifecycle regressions have NOT been rerun by this peer on final source.
Actual delayed old audio callback after pool reuse, same-handle replacement cue onset, broader world-exit combinations, full suite, GPU, Android, and APK were not independently completed by this peer. The normal test covers same-slot new actor life and subsequent old-state retirement; do not conflate that with a tested new cue replacing the same handle.
No result here certifies whole Task3–5/P6 or the controller's other changes.

## Integration
Apply only the production file and three new test files; this worklog is the fifth delivery file. Exclude the two raw environment JSON restorations and all cache outputs.
Preserve RED/GREEN evidence, run the same two scenes plus the controller's agreed resource/world/periodic regressions on one final source snapshot, and retain warnings.