# B02 visual failure trace

## Scope and source binding

This is a read-only trace against fixed source commit
`ed2d87121de80c84caaa3f096c3a5acb71d4946f`. No native run or production/test
edit was performed. Relevant raw source SHA-256 values at that commit are:

| source | SHA-256 |
|---|---|
| `scripts/caster_skill_visual_effect.gd` | `9a8e0a411c550950933bb8c510530a28a49b9fb8aa7646f7a1d470740d530efd` |
| `scripts/caster_skill_animation_player.gd` | `365cdebbfe74104d08de7eda5558455190e8aaf5e63399dadffe269b648c1ef3` |
| `scripts/caster_skill_visual_registry.gd` | `ccd3220d6df2dc66835eac417fe8ebbd653ff73308760828b8e267ab73fabfcc` |
| `scripts/game_root.gd` | `d3ed6e93748c131106e589e84e08e01e22a94c6a8509d5219c283281f071d694` |
| `scripts/player.gd` | `01a04c3c5bab56e5507d730960531aef7aa403b08ffd788d6180d5be1162f275` |

## Failure path and actual owner

The runtime chain is:

`Player.request_skill` → `GameRoot` creates `CasterSkillVisualEffect` →
`CasterSkillVisualEffect._install_single` creates/configures
`CasterSkillAnimationPlayer` → `CasterSkillAnimationPlayer._apply_frame` calls
`CasterSkillVisualRegistry.request_animation_frame_texture` → combat misses are
queued in `_pending_warm_paths` → `GameRoot._pump_pending_warm_textures` admits
up to two requests per process with four in flight.

The relevant code is `caster_skill_visual_registry.gd:72-89, 292-309`,
`caster_skill_animation_player.gd:314-356, 387-470`,
`caster_skill_visual_effect.gd:289-329, 399-421`, and
`game_root.gd:2119-2167`.

A permanently failed frame has a confirmed retry/lifecycle hole:

1. `GameRoot._pump_pending_warm_textures` sees `THREAD_LOAD_FAILED`, calls
   `load_threaded_get` once, and erases the path at `game_root.gd:2146-2149`.
2. The registry has no terminal failed-path set or failure result. The path was
   already removed from `_pending_warm_paths` when admitted.
3. The animation player remains `_waiting_for_residency`; each `_process`
   calls `_retry_after_warm`, sees `sequence_resident == false`, and queues the
   whole sequence again at `caster_skill_animation_player.gd:448-451`.
4. The next pump can submit the same failed path again. There is no bounded
   retry count, failure generation, or explicit terminal notification.
5. A structurally accepted one-shot is not protected by the parent timeout:
   `_install_single()` appends the configured child at
   `caster_skill_visual_effect.gd:399-421`, so the parent sets
   `visual_loaded = true` at lines 292-295 even while the child is waiting for
   residency. The parent then returns at lines 314-316 when any child has
   `visual_loaded == false`, before its `not visual_loaded` timeout branch at
   lines 308-313 can run. Thus a permanently failed one-shot can also remain
   resident and retry indefinitely. A structurally rejected effect with no
   child takes the timeout branch, but that is a different case. An active
   magic-shield visual returns earlier at lines 301-307, so it has the same
   failure plus its gameplay-owned lifetime. This is the confirmed B02
   residual, distinct from ResourceLoader claim retirement.

The animation player does correctly release a sequence lease on exit or normal
completion (`caster_skill_animation_player.gd:371-384, 420-428`). The problem is
that a failed sequence never reaches a terminal animation state, so lease
release alone does not solve the repeated request or persistent visual node.

## Minimal interface and failure scope

The smallest host interface is a registry terminal-result seam, called by the
existing GameRoot pump after it performs the one terminal `get`:

- `mark_animation_frame_terminal_failure(path: String, request_generation: int) -> void`
  records the path as FAILED for that warm request and removes it from the
  retryable pending set. INVALID is recorded separately as no-claim terminal
  state.
- `animation_sequence_failure(paths: Array[String], request_generation: int) -> String`
  returns the first terminal reason for the current sequence generation, or an
  empty string while it is still waiting.
- `clear_animation_failure_generation(request_generation: int)` is called only
  when a new explicit cast/generation starts or the registry is reset for a
  map/lifecycle boundary. It is not called from every `_process` retry.

`CasterSkillAnimationPlayer._retry_after_warm()` should consume the second seam
and emit one terminal failure result. `CasterSkillVisualEffect` should consume
that result and free only its presentation child/effect node; persistent
magic-shield gameplay state remains owned by its existing buff state. The
failure record is scoped to `(path, request_generation)`, so an explicit later
cast may retry the path without a timer or an automatic same-cast loop.

## Minimal complete repair boundary

The repair belongs to the presentation ownership chain, not HP/MP, skill
submission, or the B01 ContentLayers claim service:

1. Add one terminal failure record per admitted frame path in
   `CasterSkillVisualRegistry`, completed by the GameRoot pump after the single
   FAILED `load_threaded_get`. INVALID remains a no-get terminal state. The
   record must be generation/cast scoped so a later explicit cast can request a
   fresh path without a per-frame retry loop.
2. Make `sequence_resident`/the animation player distinguish “waiting” from
   “terminal sequence failure.” `_retry_after_warm` must stop requeueing a
   sequence once any required frame is terminally failed and emit/record one
   animation-failed result.
3. Have `CasterSkillVisualEffect` consume that result. A failed normal effect
   may queue-free through its existing visual owner path. A failed persistent
   magic-shield visual must release its player/lease and remove only the visual
   node; the gameplay shield remains owned by the buff state and is not changed.
   This avoids inventing a TTL or silently changing combat semantics.
4. Keep the existing one `load_threaded_get` for FAILED and no `get` for
   INVALID. A retry, if product policy requires it, must be an explicit new
   cast/generation action, not an automatic timer or repeated process retry.

No new loader, fallback synchronous decode, HP/MP change, skill cancellation,
or arbitrary timeout is required.

## Confirmed source hygiene issue

`caster_skill_animation_player.gd:251-283` contains two identical
`elif (_desired_axis_extent > 0.0 and not _fit_axis_world.is_zero_approx())`
branches. The first branch at lines 251-279 always consumes the condition; the
second branch at lines 280-289 is unreachable. It is redundant configuration
logic and should be removed or merged as a separate source cleanup. It is not
the failure cause above, but it can make the intended fallback scaling policy
look active when it is not.

## Required focused validation

A bounded regression should use a real ResourceLoader request that reaches
`THREAD_LOAD_FAILED` (not a synchronously rejected path), then verify:

- exactly one terminal `get` for the failed accepted request;
- no repeated request after the failure record is published;
- normal one-shot visual reaches its existing owner cleanup;
- active magic-shield visual releases its animation player/lease and leaves no
  visual child while the gameplay shield remains active;
- a later explicit cast/generation can retry the same path once;
- successful first-frame and mid-sequence warming retain existing frame-index,
  lease, and completion behavior.

The existing B01 positive claim-retirement evidence does not cover this path;
its INVALID and accepted-terminal ownership contract must remain separate.
The test must retain native exit, engine error, and terminal claim diagnostics,
and distinguish `THREAD_LOAD_FAILED` from `THREAD_LOAD_INVALID_RESOURCE`.
## Review of the proposed single-cache lifetime boundary

A `_terminal_failed_paths` dictionary is sufficient as the single cache authority
only if the cache exposes every terminal outcome to it. The current fixed code
has two additional exits that the host must wire:

- `ResourceLoader.load_threaded_request` can return a non-OK error at
  `game_root.gd:2166`; the path has already been removed from the registry
  pending list and is not inserted into `_frame_texture_threaded`.
- A tracked request can report LOADED but cast to a non-`Texture2D` at
  `game_root.gd:2143-2145`; `retain_loaded_texture` currently returns on null
  (`caster_skill_visual_registry.gd:109-112`) without publishing failure.

Both cases need the same explicit registry terminal-failure method as FAILED
and INVALID, otherwise the retry loop remains possible.

Clearing `_terminal_failed_paths` in `clear_frame_texture_cache()` is a sound
cache reset boundary, and clearing a path in `retain_loaded_texture()` is the
correct recovery boundary after a real successful load. However, the fixed
source has no production caller of `clear_frame_texture_cache()`; its callers
are tests. If the intended policy is “a later explicit cast may recover,” the
new design must either add a real cache/lifecycle reset owner or scope the
failure to an explicit cast admission. Simply retaining a permanent path
failure with no production reset makes a transient failed path unrecoverable.
`set_loading_window_active(true)` should remain unrelated to failure clearing,
as proposed.

The animation-player terminal result must be checked before the residency wait
returns, and the visual effect must check it before both its child-wait return
and its persistent-shield early return. That ordering is necessary to remove
both one-shot and persistent failed visuals without changing the gameplay buff.

## Frozen-candidate correction (2026-10-10)

The earlier sections describe the pre-repair design seam. The frozen current
candidate implements that seam with a monotonic registry failure serial,
explicit-admission clearing, automatic-retry rejection, and signal-based
parent cleanup. See `B02_VISUAL_FINAL_SOURCE_REVIEW.md` for the current source
fingerprints and exact evidence boundary. The duplicate axis-scaling branch
listed above has also been removed.

Direct25's internal receipt is 35/35 with native exit 0. Its wrapper remains
`FAIL` solely because the intentionally malformed test-owned `.res` produces
two expected ResourceLoader errors. Related26's three existing positive lease
tests are native PASS with clean stderr/engine logs. Neither result is a full
production PNG-corruption-to-HP/damage E2E test; that scope remains NOT_RUN.
