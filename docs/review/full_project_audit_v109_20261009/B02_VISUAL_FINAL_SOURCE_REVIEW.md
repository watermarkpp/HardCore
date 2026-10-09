# B02 visual terminal-failure final source review

Date: 2026-10-10

This review is bound to the frozen current candidate, not the earlier fixed
`ed2d87121de80c84caaa3f096c3a5acb71d4946f` audit snapshot. Current source
SHA-256 fingerprints are:

| Source | SHA-256 |
|---|---|
| `scripts/caster_skill_visual_registry.gd` | `C9A17F569F4B4BD4263BCDE067CA7C1A26EEB184277FAF814EF20BEF34A862FE` |
| `scripts/caster_skill_animation_player.gd` | `54F6CD40974B81B25544CBDC5B15A7EDEABCFAD5B700C98AA94F44C731BC888B` |
| `scripts/caster_skill_visual_effect.gd` | `017BA6A1E1AEE80ACEFF025E068BF29281D8AA6133FDD32516365DA0C9EC4F55` |
| `scripts/game_root.gd` | `2EA2DC8E90239E8C1DB9260CABBB57A7991EC14B82999C89B2035661E90E5C93` |

## Static source findings

`CasterSkillVisualRegistry` maintains a current terminal map and a monotonic
per-path history. `mark_frame_texture_terminal_failure()` increments the
serial and records the reason. `queue_sequence_warm(paths, true)` is the
explicit new-admission boundary and clears only the current block. Automatic
retry calls `queue_sequence_warm(paths, false)` and refuses a currently failed
path. `sequence_terminal_failure_after()` checks both current state and the
history serial, so an old waiter remains terminal after a later explicit
admission clears the current state. Successful retention clears the current
failure in both `retain_loaded_texture()` and `_retain_frame_texture()`, while
the history remains available to old owners. Cache clearing removes history
but deliberately leaves the serial monotonic.

`GameRoot` now closes every warm-request outcome in one registry authority:
LOADED consumes one `load_threaded_get()` and retains a `Texture2D`; FAILED
consumes one get and records `failed`; INVALID records `invalid` without get;
LOADED with a non-texture records `wrong_resource_type`; and a non-OK request
records `request_rejected_*`. ERR_BUSY is requeued because this owner never
accepted a claim. The normal pump removes its own tracking entry before
publishing each terminal outcome. `_retire_pending_warm_textures()` applies
the same ownership rule at the final owner boundary.

`CasterSkillAnimationPlayer` captures the current failure serial before its
explicit queue admission. Its three automatic retry/mid-sequence paths check
the sequence history before requeueing. `_set_terminal_failure()` stops
processing, clears residency waiting, releases only its held sequence lease,
and emits `animation_terminal_failure` once. This leaves the explicit later
configuration path available.

`CasterSkillVisualEffect` binds that signal once when each real animation
child is installed. Both the ordinary single-child path and every Hellfire
child use `_bind_animation_failure()`, which prevents duplicate connections.
The callback is idempotent and queues the presentation parent for deletion.
There is no per-frame reflective child scan. The callback does not alter
player HP/MP, cooldowns, shield state, or skill submission.

The duplicate unreachable axis-scaling branch identified in the earlier trace
has been removed from the current animation-player source.

## Evidence boundary

Direct25 is the focused native negative/repair fixture:

`outputs/wake_drop_v108_review_followup_20261009/direct25_visual_typed_input/evidence/fe927ed0-790f-4cdd-be6d-ee4b65796f73/native_result.json`

The internal fixture receipt reports 35/35 checks and native exit 0. It
verified the actual accepted malformed user resource, Root terminal transfer,
old-waiter/new-admission serial behavior, same-path valid repair, real
one-shot and shield effect construction, terminal child handling, lease
release, parent retirement, unchanged shield snapshot, and retrieval-claim
cleanup. The wrapper result is correctly retained as `FAIL` because the two
expected malformed `.res` ResourceLoader errors remain in stderr/engine logs;
they are not suppressed or reclassified as a clean engine run.

The related26 positive evidence is retained separately and reports native
exit 0, stderr 0, and engine-error 0 for the existing sequence-lease,
production-caller lease, and workset lease tests. These are positive cache and
lease regressions; they do not convert the direct25 malformed-resource
negative into a general asset-corruption pass.

## Final status

| Scope | Status | Boundary |
|---|---|---|
| Current-source static review | PASS | Four frozen production sources above |
| Terminal registry/Root outcome ownership | PASS | Direct25 checks plus current host source |
| Old waiter versus explicit retry | PASS | Direct25 serial assertions |
| One-shot/persistent presentation cleanup | PASS | Direct25 component fixture; presentation scope |
| Existing positive lease/cache regressions | PASS | Related26 native receipts |
| Full production PNG/art corruption through a real spell damage event | NOT_RUN | No claim made from injected component path |
| Android/device audio/visual behavior | NOT_RUN | Outside this B02 source/native scope |

The component fixture injects the test-owned failed path into an already
constructed animation child to isolate terminal ownership. It is evidence for
the component seam, not an end-to-end proof that a production PNG failure
propagates through a real HP/damage spell cast.
