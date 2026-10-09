# B05-003 audio release ledger disposition

Date: 2026-10-10

## Source binding and finding

The external B05 finding is bound to source SHA
`dfcfb9cda1b88d71d7cca3b432ba812831d93c23` and identifies
`scripts/audio_runtime_service.gd::_play_event_internal`,
`_owner_release_key`, and `stop_all_audio`, with the producer context in
`scripts/enemy.gd::_audio_context` / `_audio_attack_sequence`. Before this
change, every admitted release was inserted into `_owner_release_seen` under
`owner|event|release`. Monster attack contexts use `release_id=attack:<serial>`;
therefore each successful attack serial added another dictionary entry until a
world stop or test reset.

The authoritative distinction is now explicit. Monster attack `attack_start`
and `attack_frame` events with a positive `attack:<serial>` release use one
monotonic frontier per `audio_owner_key|event_id`. A serial at or below the
frontier is rejected as `duplicate_owner_release`; a greater serial is
admitted and advances the same entry. Other UUID-like or non-monotonic release
IDs retain exact-key de-duplication in `_owner_release_seen`, so this change
does not invent ordering for unrelated producers.

`stop_all_events()` only releases voice slots and does not erase the frontier;
old attack receipts must remain rejected while the world is alive. The
existing outer `stop_all_audio()` and explicit test reset clear the frontier at
the established world/test lifecycle boundary. The attack ledger is therefore
bounded by live owner/event frontiers rather than attack count, while
preserving old-receipt rejection. No TTL, finished-callback erase, audio-rate
change, or gameplay producer identity change was introduced; the Enemy change
only propagates its existing instance/life identity and retires the cached
audio owner at the existing setup/exit lifecycle boundaries.

Each live owner records only the small set of frontier/exact keys it admitted;
retirement erases those keys directly and does not scan the global ledgers.

For `source=enemy_actor`, service admission additionally requires the actual
`EnemyActor` instance, an in-tree/non-queued node, the current
`hc_combat_life_epoch`, and the canonical key
`monster:<monster_id>:<source_instance_id>`. This rejects aliases, stale life
contexts, and late contexts after retirement. Synthetic/editor/summon callers
without that producer marker retain the compatibility exact-key path and are
not silently promoted to the strict Enemy lifecycle contract.

## Implementation and evidence

Production change: `scripts/audio_runtime_service.gd`.

Current mixed-tree source SHA256 after the lifecycle extension:
`B3FDFCFD7F69EDAB42ECB9DF98CAEC659F84DB78EE210DB908652057EDF80C0C`.
This hash includes the pre-existing current-tree audio changes. The producer
source currently hashes to
`4B1C3AB263CBE13CEB3BE5353D9B061A821A213B9A477E25FE7523622CCE7EAE`.

The saved preimage is
`outputs/wake_drop_v108_review_followup_20261009/audio_runtime_service.b05_003.preimage.gd`
with SHA256
`BBC4D3425D302EFA647C6F6EC18315D328834A4649EDB1DA87E89099D03C16F5`.

The lifecycle-extension audio preimage is
`outputs/wake_drop_v108_review_followup_20261009/audio_runtime_service.b05_003.lifecycle.preimage.gd`
with SHA256
`BF7054277FD5AC51C6F569357A84F95B3BDC1715F431A4BB402A031D9A60D0B6`.

The focused fixture is:

- `tests/framework/audio_release_frontier_contract_20261010_test.gd`
- `tests/framework/audio_release_frontier_contract_20261010_test.tscn`

It covers real `EnemyActor._audio_context()` identity fields, first/new/replayed
attack serials, independent start/frame events, 20 owner creation/retirement
cycles, a retired-owner late context, 500 successive serials at the existing
12/sec admission cadence, exact-key ledger separation, and world-exit clearing.
The fixture is source-complete but has not been run in Godot/native in this
review (`NOT_RUN`). No claim is made about Android memory or frame time.

The production source still owns the only audio admission and playback pool;
the test reads only the service's diagnostic snapshot fields added for this
bounded ledger. Gameplay damage, attack cadence, release generation, volume,
and stream selection remain outside this change.

## Status

| Scope | Status | Basis |
| --- | --- | --- |
| Static B05-003 defect repair | `PASS` | Frontier is one entry per monster owner/event; old serials remain rejected |
| Focused Godot/native fixture | `NOT_RUN` | No engine/native execution authorized in this task |
| Android memory/frame outcome | `NOT_RUN` | Requires fixed-source device evidence |
| B05-003 full lifecycle acceptance | `NOT_RUN` | Requires the focused fixture plus long-lived owner/world lifecycle evidence |

## Root native verification

Source38 audio/scroll direct scopes, source39 formal READY HUD scope, related40 audio and multitouch positives, and source41 existing scroll regression are retained in B05_NATIVE_VERIFICATION_LEDGER.json. All final relevant cases have PASS/native0, valid framework receipts where applicable and clean exit. Original direct37/38 and related40 fixture failures remain exact evidence. No production change was made to erase those failures; fixture return fields, local coordinate routing, formal READY, authoritative binding and complete pointer lifecycle were aligned without relaxing business assertions.

DEVICE TEST: NOT_RUN. Startup audio wall-clock cost and sustained performance are not established by these behavior tests.
