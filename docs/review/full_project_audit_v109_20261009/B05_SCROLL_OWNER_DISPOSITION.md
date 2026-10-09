# B05-002 scroll owner disposition

## Scope

This is the B05-002 implementation against the published source contract `dfcfb9cda1b88d71d7cca3b432ba812831d93c23`. Only `scripts/touch_scroll_support.gd`, the focused contract test and its scene are in scope. No layout, click coordinate, long-press policy or production control was changed. Godot/native validation is `NOT_RUN` pending root's frozen-source run.

## Preimage and change

The preimage is preserved at `B05_SCROLL_OWNER_DISPOSITION.preimage.gd` with SHA256 `A438234411BC0D1329467FA0F4879C875EEE11A13263BBA03DBD5AA7514A543F`.

The previous `_begin_drag_candidate` accepted every new pointer except a repeated DOWN from the current pointer. That let pointer B replace A's `_active_control`, `_active_touch_index`, press position and drag state. The repair first checks whether the existing owner is still a visible, valid registered scroll control with a scrollable vertical bar. While that owner is live, a second DOWN returns without changing A's state. If the owner is destroyed, hidden, detached from a usable scroll state, or otherwise no longer valid, the input boundary ends the existing owner before processing the event, and the new pointer may be considered.

The existing active-pointer UP/CANCEL path still calls `_end_drag`, restores button state for a real drag, and preserves the existing release guard. The new owner check does not consume B's independent button input; it only prevents B from replacing the scroll service's A owner. Hidden-control exit is handled by the same validity check on the next DOWN, while A's later drag is ignored after the owner has been revoked.

## Contract coverage

`tests/framework/touch_scroll_pointer_owner_contract_20261010_test.gd` creates a real `ScrollContainer`, overflowing content, and an independent `Button`, then exercises:

- A single-pointer drag and actual `VScrollBar` movement;
- B DOWN/tap on the independent button while A owns the scroll, with A's owner identity preserved and B's button press delivered once through viewport input routing;
- A continuing to scroll after B's tap;
- A release revoking ownership and retaining the existing anti-click guard;
- hidden scroll control revoking ownership before a new pointer is considered;
- A CANCEL clearing active ownership and drag state;
- single-pointer non-drag tap cleanup.

Source hashes after the edit:

- `scripts/touch_scroll_support.gd`: `A78589B60C2D3EDBF0DEE809537D4DD4A730E44317C686BF14B6C1BF5FCD2819`
- `tests/framework/touch_scroll_pointer_owner_contract_20261010_test.gd`: `F37541CF24E8A71E6D9C348522CF1710F2F86FAB8F725216FF6F915335AC88AF`
- `tests/framework/touch_scroll_pointer_owner_contract_20261010_test.tscn`: `7A825D760E35860A98292A6875B68E9BF923A88674F33594B1A625E27D40F3BD`

Static `git diff --check` is required before root's run. No stage, commit, push, or test execution was performed.


## Root native verification

Source38 audio/scroll direct scopes, source39 formal READY HUD scope, related40 audio and multitouch positives, and source41 existing scroll regression are retained in B05_NATIVE_VERIFICATION_LEDGER.json. All final relevant cases have PASS/native0, valid framework receipts where applicable and clean exit. Original direct37/38 and related40 fixture failures remain exact evidence. No production change was made to erase those failures; fixture return fields, local coordinate routing, formal READY, authoritative binding and complete pointer lifecycle were aligned without relaxing business assertions.

DEVICE TEST: NOT_RUN. Startup audio wall-clock cost and sustained performance are not established by these behavior tests.
