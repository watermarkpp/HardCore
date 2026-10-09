# v108 cold-start audio trace

Scope: MAIN dirty v108 source at the `92c6eeb93af9546b891ea0a1a15dd4f8c600502b` build boundary. This is a source trace only; no engine or device run was performed here.

## Observed failure shape

“No audio on entering the game; moving a sound slider immediately restores it” matches a bus-mute state captured too early and then reapplied. The affected state is global `AudioServer` bus state, so both the town music player and SFX players can be silent even though their streams and player nodes exist.

## Startup order and failure mechanism

1. `project.godot:29-45` registers `AudioPreferences` as an autoload. Its `_ready()` runs before `GameRoot` creates the runtime audio service.
2. `scripts/audio_preferences.gd:17-31` derives initial user levels from `_initial_level(&"Music")` and `_initial_level(&"SFX")`, then immediately calls `_apply()`.
3. `scripts/audio_preferences.gd:33-35` returns `0.0` whenever a bus already exists and `AudioServer.is_bus_mute(index)` is true. This treats the current engine/device bus mute bit as a persisted user preference. It does not distinguish a cold Android audio-device/focus mute from an intentional saved mute.
4. `_apply()` at `scripts/audio_preferences.gd:75-90` then preserves that sampled zero: it mutes the bus and pushes `set_sfx_enabled(false)` to any already-bound SFX services. The value is not marked dirty, so there is no corrective write or later retry.
5. `GameRoot._ready()` creates `TownMusicController` and `AudioRuntimeService` at `scripts/game_root.gd:1729-1735`. `TownMusicController._ready()` creates the Music bus/player at `scripts/town_music_controller.gd:49-76`; `AudioRuntimeService._ready()` creates/uses SFX and calls `sync_sfx_enabled_from_bus()` at `scripts/audio_runtime_service.gd:105-119`.
6. The service sync at `scripts/audio_runtime_service.gd:235-239` reads the same possibly transient SFX mute bit, and `_apply_sfx_gain()` at `:199-205` turns every pooled player to `-80 dB` when disabled. Town music keeps its player but its Music bus can remain muted from the earlier preference apply.
7. A slider event takes a different path: `scripts/system_menu_panel.gd:469-488` emits the new level, `scripts/game_root.gd:2706-2715` calls `AudioPreferences.set_level()`, and `scripts/audio_preferences.gd:40-53,75-90` immediately sets the bus mute bit and re-applies the SFX service gain. That explains recovery without any stream reload.

The exact device-side initial mute transition is not retained in this source tree, so the final Android trigger is `MISSING` here. The ordering defect is source-backed and is sufficient to explain the observed symptom: startup trusts a live bus mute bit before the audio services own and normalize the buses, while the slider is the first guaranteed re-application.

## Minimal repair boundary

Make the saved v2 file the authority when it is valid. When there is no valid preference file, initialize the Music/SFX levels to explicit defaults (`1.0`) and explicitly normalize both buses after the services/buses exist; do not infer a first-run user level from `AudioServer.is_bus_mute()`. If migration of an intentional legacy mute is required, it needs an explicit versioned migration signal, rather than the current bus-bit heuristic.

The smallest safe production ordering is:

- let `AudioPreferences` load/validate persisted values without sampling a transient bus mute;
- let `GameRoot` create Music/SFX and `AudioRuntimeService`;
- perform one authoritative preferences apply after both buses and the SFX service are present;
- keep the existing slider path and `AudioRuntimeService` project scale (`0.5`) unchanged.

Do not fix this by replaying streams, adding a timer, or changing event mappings. The recovery action already proves that bus/gain re-application is the relevant seam.

## Why the existing checks missed it

- `tests/audio_runtime_service_test.gd:11-22` creates `AudioRuntimeService` directly and checks routing, mappings, pools, and gains. It does not boot `project.godot` autoloads through `startup_loading.tscn` and `scenes/main.tscn`, nor does it begin with a pre-existing muted bus.
- `tests/ui_r5_audio_config_strict_test.gd:89-110` tests malformed preferences, but its fallback assertion compares values to `_initial_level()` itself. That preserves the current bus-snapshot behavior instead of asserting a cold-start default and explicit unmute.
- `tests/town_music_runtime_test.gd` verifies controller creation/routing, not the first real startup transition or a persisted/invalid `user://audio_preferences_v2.cfg` case.
- The retained audio evidence covers event mapping and service behavior, but does not retain Android cold-start bus state before and after the first slider interaction. That device boundary remains `NOT_RUN` in this trace.

## Required regression case

Add one isolated real-scene startup case using the actual autoload set and `startup_loading.tscn -> scenes/main.tscn` transition. Before `GameRoot` creates its services, force the SFX and Music bus mute bits to true as a cold-device control; boot with (a) no preference file, (b) a valid v2 file with nonzero levels, and (c) a valid v2 file with zero levels. At the first post-ready boundary assert:

- case (a): both buses are explicitly unmuted and the service reports SFX enabled;
- case (b): exact saved levels are applied;
- case (c): both buses remain intentionally muted;
- changing one slider changes only that channel and is the only allowed recovery path for an intentionally muted configuration;
- the first actual mapped SFX and town-music player have the expected bus and finite gain before any slider event.

The test must retain the initial bus state, autoload order, preference-file variant, first audio event result, and native exit. A service-only test or a test that calls `_apply()` manually is insufficient.
