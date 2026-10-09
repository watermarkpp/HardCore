# B05 non-monotonic audio release scope

Date: 2026-10-10

This note covers production callers outside the strict Enemy attack owner
contract. It does not repeat the Enemy owner/frontier review or the direct37
fixture run. Current source hashes are:

| Path | SHA256 |
| --- | --- |
| `scripts/audio_runtime_service.gd` | `68A482A7F0908D39358D7EF564856286C4322435C2E594351D6F9A2294AE01D2` |
| `scripts/enemy.gd` | `4B1C3AB263CBE13CEB3BE5353D9B061A821A213B9A477E25FE7523622CCE7EAE` |
| `scripts/summon_actor.gd` | `5108E330504BF7CA9E4A6DFB41295424747DB8C92E60DE8FDD2965F1930B0664` |
| `scripts/game_root.gd` | `B1DBD187310D5764289BA266E0948BBCC2B6EEFEE254BF1E1D51C242F4E28EAC` |
| `scripts/caster_skill_visual_effect.gd` | `017BA6A1E1AEE80ACEFF025E068BF29281D8AA6133FDD32516365DA0C9EC4F55` |
| `scripts/caster_skill_runtime.gd` | `98191C61D63953312D64F81E2D5D7EF129F240731953ED730759CB343B6E2F67` |

## Callers with audio owner and release identity

The only production caller currently supplying both `audio_owner_key`/`owner_key`
and a release or session identity to `AudioRuntimeService.play_event()` is the
Enemy path in `scripts/enemy.gd::_audio_context()` (`:1011-1042`). That path is
the strict `source=enemy_actor` contract documented in the companion B05
ledger. The current owner key is canonical `monster:<monster_id>:<instance>`;
attack releases use `attack:<serial>`, and the service now retires those keys
with the cached Enemy owner lifecycle.

`scripts/summon_actor.gd::_audio_context()` (`:465-476`) supplies
`source=summon_actor`, `summon_id`, `skill_id`, `runtime_map_id`, and semantic
event, but no `audio_owner_key`, `owner_key`, `release_id`, or `session_id`.
`_emit_summon_audio()` (`:478-496`) calls `play_monster_event()` with that
context. It therefore cannot populate `_owner_release_seen` through a
release identity and is not a non-monotonic ledger producer. Its lifecycle is
the normal summon audio lookup and node lifetime, outside B05-003's owner
frontier.

`scripts/game_root.gd::_play_skill_audio_phase()` (`:8500-8505`) calls
`play_event()` with only `gender` and `map_id`. The committed item path
`_on_item_audio_committed()` (`:8493-8498`) and the loot currency path around
`:15283` call `play_item_event()` with stable item/service identity and map
context, but no owner key or release/session identity. `play_item_event()` then
adds only `stable_item_key` and `item_semantic_event` before calling
`play_event()` (`scripts/audio_runtime_service.gd:735-744`). These paths do not
enter `_owner_release_key()` with a usable key.

`scripts/caster_skill_visual_effect.gd` (`:814-827`) and
`scripts/caster_skill_runtime.gd` (`:150`, `:218-433`) carry release IDs for
damage/visual lineage, but neither file calls `AudioRuntimeService`. Their
release IDs therefore do not create audio ledger entries. GameRoot's skill
audio call intentionally omits the combat release ID.

## Service compatibility surfaces

`AudioRuntimeService._owner_release_key()` (`:1047-1055`) falls back from
`audio_owner_key` to `owner_key` and from `release_id` to `session_id`. In the
current production caller inventory, that fallback is reachable only from
Enemy-originated contexts or explicit service/test/synthetic calls; no
non-Enemy production caller supplies both fields. The disabled combat-prompt
compatibility methods (`:605-641`) do not allocate a session or play a stream,
so they do not grow `_monster_sessions` from ordinary pursuit.

The exact-key dictionary remains intentionally conservative for future
non-monotonic producers: it is not expired on `AudioStreamPlayer.finished`,
and no TTL or UUID heuristic has been introduced. Current non-Enemy production
scope is therefore `NONE` for an unbounded owner/release producer. A future
feature that adds both fields must add a real owner-retirement boundary or use
an explicit bounded lifecycle contract before routing through `play_event()`.

One adjacent boundary is worth retaining for review: Enemy-originated
non-attack events can carry the now-enriched `_audio_context()` and may use
exact release IDs in their damage/physical-contact paths. If such an event is
accepted before that Enemy owner has registered its attack frontier, its exact
key is not associated with a live-owner record and remains until world stop.
That is an Enemy-side compatibility scope, not a non-Enemy caller, and was not
changed in this read-only audit.

## Disposition

| Scope | Status | Evidence |
| --- | --- | --- |
| Non-Enemy production owner+release caller found | `PASS` | Summon/GameRoot/caster call-site inventory above; none supplies both fields to audio |
| Non-Enemy unbounded `_owner_release_seen` growth proven | `PASS` | No reachable non-Enemy owner/release pair in current source |
| Future UUID producer lifecycle contract | `NOT_RUN` | No such current production caller exists |
| Device/audio memory validation | `NOT_RUN` | Static source scope only; no engine/native run |
