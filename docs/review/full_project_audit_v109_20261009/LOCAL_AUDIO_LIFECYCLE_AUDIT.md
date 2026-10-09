# B05 local audio lifecycle audit

## Scope and binding

This is a read-only source audit of the fixed production paths at baseline
`ed2d87121`. No Godot, native, Android, or device execution was performed.
The resource-claim handoff work is outside this review. The source paths
reviewed were:

- `scripts/audio_preferences.gd`
- `scripts/audio_runtime_service.gd`
- `scripts/town_music_controller.gd`
- `scripts/game_root.gd`
- `scripts/system_menu_panel.gd`
- `project.godot`

Earlier B05/B61 evidence already covers the repaired invalid-preference default
and the menu slider/save behavior; this note checks the current ownership and
execution chain rather than reclassifying those prior results.

## Findings

**No confirmed production correctness defect found in the fixed source.** The
following contracts are source-backed:

1. `AudioPreferences._ready()` starts from music/SFX gain `1.0`, accepts only a
   valid v2 file or backup, and calls `_apply()` before any service binding
   (`scripts/audio_preferences.gd:22-39`). `bind_sfx_service()` reapplies the
   current gain on first bind and on duplicate bind (`:56-69`). A saved zero
   therefore reaches both the SFX bus mute and the runtime player gain before
   playback (`:78-94`). Same-value `set_level()` still calls `_apply()` before
   returning (`:45-54`).

2. `AudioRuntimeService._ready()` creates the voice player, loads exact
   bindings, prewarms admitted event streams, applies SFX gain, and binds to
   `AudioPreferences` (`scripts/audio_runtime_service.gd:105-119`).
   `prewarm_runtime_streams()` excludes monster prompt/engagement and rejected
   semantics (`:367-388`), while `_play_event_internal()` rejects those paths
   before variant selection or `_stream_for()` (`:455-509`). Thus the retired
   monster-enter/ambient cues do not decode, queue, loop, or allocate a pool
   player through this service.

3. Runtime interaction is fail-closed after startup: `_stream_for()` reports a
   cache miss and returns null rather than synchronously loading a sound
   (`scripts/audio_runtime_service.gd:1109-1118`). Item sound routing is stable
   ID based (`:729-745`), and committed item audio enters from
   `GameRoot._on_item_audio_committed()` (`scripts/game_root.gd:8460-8471`).

4. World teardown has one explicit owner. `GameRoot._exit_tree()` calls
   `AudioRuntimeService.stop_all_audio("world_exited")` and
   `TownMusicController.cancel("world_exited")`
   (`scripts/game_root.gd:1810-1825`). `stop_all_audio()` stops NPC voice,
   pooled events, clears owner-release/session state, and marks monster audio
   sessions inactive (`scripts/audio_runtime_service.gd:747-760`).

5. Town BGM is loaded once into a dedicated `AudioStreamPlayer`, is explicitly
   non-looping, and starts only after a valid safe-area context plus loading
   completion and delay (`scripts/town_music_controller.gd:73-94`, `:132-171`,
   `:287-324`). Transition begins cancel the pending delay while preserving a
   track already playing; explicit `cancel()` stops it (`:132-149`, `:175-190`).

## Coverage gap requiring B05 runtime evidence

`GameRoot._notification()` handles application pause/focus-out by resetting
frame diagnostics and input state, but it does not explicitly pause, mute, or
stop `AudioRuntimeService` or `TownMusicController`
(`scripts/game_root.gd:1828-1844`). Both services use `PROCESS_MODE_ALWAYS`
(`audio_runtime_service.gd:105-107`, `town_music_controller.gd:61-75`). Whether
Godot's platform audio policy suspends output while backgrounded is therefore
not established by source. A focused B05 device/native case should verify:

- an active town track and active SFX across application pause/resume;
- no delayed town callback starts during the pause boundary;
- saved SFX `0`, then a same-value slider rebind, remains silent after resume;
- a committed potion/item event after resume uses the restored gain exactly once.

This is a `MISSING` runtime/device coverage item, not a source-confirmed bug.

## Lifecycle limitation

`stop_npc_voice()` stops playback but leaves the player’s stream reference in
place (`scripts/audio_runtime_service.gd:824-842`); the service is normally
destroyed with `GameRoot`, and replacement playback overwrites the stream. A
long-lived service reset/reload path is not shown in this fixed source, so
repeated in-process service reload ownership remains `MISSING` rather than a
confirmed leak.

## Confidence and prior evidence boundary

Source confidence is high for admission ordering, saved-volume application,
monster prompt suppression, item routing, and normal world teardown. Runtime
confidence is limited to the existing B61/B108 evidence already recorded by the
project; this audit adds no new execution evidence and does not close the
pause/background or long-lived service-reload gaps.
