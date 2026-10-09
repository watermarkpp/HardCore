# B05-001 input-cancel disposition

## Scope and source binding

This disposition covers only B05-001 from `external/B05/FINDINGS.json`: a
quick-item pointer can remain live across the GameRoot system-menu pause and
later emit a use on an old release or long-press timeout. B05-002, B05-003,
and B05-004 remain outside this change. The production preimages were saved
before editing:

- `outputs/release_v108_20261009/B05_input_cancel/preimage/hud.gd`
- `outputs/release_v108_20261009/B05_input_cancel/preimage/game_root.gd`

Preimage SHA256: `hud.gd` `F556951C17D71A573DB99AC62DB5D18F3E3E4172504DF2AA58ECB5C4DF24F84A`;
`game_root.gd` `AF3982647F1FE4EDF72C877026317A4866E8D83307C1B3B39E56F75044DA4D66`.
Post-edit hashes are reported with the delivery handoff; this file is not a
native-test result.

## Minimal repair

`GameHUD.cancel_item_slot_input_boundary(reason)` is now the single public
boundary for transient quick-slot input. It calls the existing
`_cancel_all_item_slot_presses()`, which clears pointer state and stops the
one shared long-press Timer. It does not clear `item_quick_slots`, emit a
synthetic UP, or touch an already accepted item transaction.

`GameRoot._cancel_player_input_boundary()` calls that method alongside the
existing attack and skill cancellation. Therefore system-menu open/close and
the application interruption notification close the same input ownership
boundary. Map transition continues through the existing
`cancel_movement_input()` path, which now uses the same HUD boundary. No
movement, attack, item binding, UI geometry, or B05-004 two-slot policy was
changed.

## Contract fixture

`tests/framework/hud_quick_slot_cancel_contract_20261010_test.gd/.tscn`
uses the formal `lease_probe_root.gd` and its live HUD. It drives real screen
touch DOWN/UP events and checks three production boundaries: system-menu
pause/resume, application focus interruption, and map-transition movement
cancel. It verifies that old UP and timer expiry produce no use, that the
shared timer and pointer map are empty, that the slot binding remains intact,
and that a new DOWN/UP emits exactly one use. The receipt/marker is present,
and its cleanup now defers receipt writing until after the formal Root teardown
callback is queued, avoiding a suspended `_finish` continuation at
`SceneTree.quit()`. The fixture has not been run in this turn:
`NATIVE TEST: NOT_RUN`.

## Remaining validation

The required root-controlled native run must bind the fixed production source,
engine, scene and receipt. It should retain the old failure evidence, include
the pause duration beyond the long-press threshold, and cover Android/menu
input as a separate device concern. This static repair does not establish
device behavior or B05-004 policy.

## Root native verification

Source38 audio/scroll direct scopes, source39 formal READY HUD scope, related40 audio and multitouch positives, and source41 existing scroll regression are retained in B05_NATIVE_VERIFICATION_LEDGER.json. All final relevant cases have PASS/native0, valid framework receipts where applicable and clean exit. Original direct37/38 and related40 fixture failures remain exact evidence. No production change was made to erase those failures; fixture return fields, local coordinate routing, formal READY, authoritative binding and complete pointer lifecycle were aligned without relaxing business assertions.

DEVICE TEST: NOT_RUN. Startup audio wall-clock cost and sustained performance are not established by these behavior tests.
