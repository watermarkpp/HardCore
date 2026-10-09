# v108 handset failures: fixed-source consultation

This initial consultation snapshot is retained as history. Later local repairs and current native evidence are in [CURRENT_RESULT.md](CURRENT_RESULT.md): necessary synchronous halo/damage activation, successful persistence state transition, drop quantum wall-budget servicing, menu-local errors and audio defaults. The existing user-named ChatGPT conversation returned a model quota message for this initial request, not a current analysis. Do not interpret the historical findings below as the current source status.

Date: 2026-10-09. This is an in-progress diagnostic snapshot, not an accepted repair or a new APK.

## Source binding

The consultation commit is based on the actual v108 APK source snapshot `92c6eeb93af9546b891ea0a1a15dd4f8c600502b`, parent `215f0b2f651a51e6855ee813ddd99221690311a1`. The root production paths in this snapshot contain the v108 implementation; do not treat them as stock107. The APK tested by the user is versionCode 108, package `com.personal.mafaoffline`, SHA256 `3652f72c6fffe1d27ef9a08acc21dc3a3550bd2f878a616bfe3d540c28d32753`.

The only production change after v108 in this consultation snapshot is `scripts/audio_preferences.gd`. New diagnostic tests and this evidence are added. MAIN's dirty files, staged index and branch are preserved. No new build was made.

## User observations and required behavior

1. Ten monsters stay clustered within the player's activation halo. Initially one engages; after a while another one or two engage. Some never move, even while firewall reduces their HP until death. The player is not invisible and continuously keeps the monsters in range. All eligible monsters must activate without AI scheduling delay. Terrain/walls should block the signal; other monsters must not block it.
2. All monsters appear to have zero ground drops. XP gain was not observed. Do not redesign probabilities or restore a retired fallback as a workaround; repair the existing formal death-to-ground chain.
3. Clicking Save and Exit has no visible effect and no visible error. Preserve durable settlement/save safety while fixing the failure and its feedback.
4. Startup has no sound. Moving an audio slider restores it.

## Findings, limitations and retained failures

### Activation: confirmed scheduling delay; permanent handset starvation still under investigation

`GameRoot._pump_passive_monster_wakeup()` requires optional FrameBudget admission for the query and for each candidate, caps candidates at eight per process epoch, and additionally stops when the shared 1200us optional budget is exhausted. `Enemy.request_passive_target_wakeup()` checks typed identity/range/static terrain LOS, records a witness and leaves sleep, but does not assign the target. Ordinary retarget then needs the 300ms owner-window/FIFO optional lease. Positive firewall damage independently reaches `_apply_damage_core`, leaves sleep, records threat and `_hc_damage_dirty`; it still leaves target selection behind optional admission.

The natural main-scene test keeps real GameRoot and enemy processing enabled, uses 12 registered non-hidden ordinary monsters and formal projection/terrain. The older generous observation window found all targets only at process frame index 13, and damage wake only at index 26. This proves eventual completion on this PC fixture, not immediate activation or handset acceptance. The strict test is FAIL: `halo_not_immediate:0/12`, `ground_tick_not_immediate:0/12`; later damage recovery is index 20. The process_frame signal is before Node._process callbacks, so interpret the first halo observation boundary carefully; the synchronous ground-damage assertion is unambiguous. Do not call the generous test PASS a product fix.

Dynamic monster bodies are not queried by the static initial-acquisition LOS path. There is no current source evidence that monster-on-monster LOS blocking causes this failure. Terrain context and runtime world/map identity still require checking.

### Death/drop: formal asynchronous natural path fails, unlike old synchronous fixtures

The existing roll-slicing fixtures disable GameRoot/manager/player processing and manually pump death jobs with `test_mode=true`. They do not establish that production prepared persistence finishes naturally.

New `death_natural_process_repair_20261009` first had a fixture error: creating a character in test_mode and flipping it to false left world snapshot sequence -1, resulting in `death_baseline_unavailable`. That result is retained but is not attributed to the real handset.

The corrected test creates and selects an actual isolated character with `test_mode=false`, verifies successful load and snapshot sequence >=0, keeps GameRoot and pickup manager processing on, and enters through Enemy's actual died signal. A fixed-seed known-producing monster profile 76 is previewed with the existing LootRuntime authority; no probability override is used. The corrected test still FAILS: after 1800 natural frames no terminal job exists, no pickup is registered, and `death_work` remains pending but unrunnable for 1800 frames. The head appears to be waiting in prepared persistence; the failure receipt currently lacks enough detail about the outstanding prepared plan, writer response and coordinator phase to prove the exact defect. Please inspect this connection first. No production drop fix has been made.

Source points: GameRoot `_poll_prepared_enemy_death_settlement`, `_settle_pending_enemy_death_batch`, `_refresh_death_budget_owner`; PlayerState `prepare_death_settlement`, `finish_prepared_death_settlement`, `_complete_background_death`; JsonPersistenceService `pump`, `_complete`, `finish`; FrameBudget owner eligibility/fairness.

The user sheet has some profile gaps, but these cannot by themselves explain every monster dropping nothing or a prepared death remaining unfinished. Do not fill arbitrary profiles as the all-zero repair.

### Save/exit: diagnostic coverage and visibility gap

`_prepare_safe_logout()` drains pickup/death work and refuses failed/pending durable settlement. A terminal death failure latches `_last_death_logout_failure`; do not bypass this protection and lose rewards. The menu emits the save-and-exit signal into GameRoot normally. On failure GameRoot displays a HUD notice, while the paused system menu remains at CanvasLayer 200. The HUD notice is below that layer regardless of its child z-index. This can hide an actual failure message. A visible menu-local error is planned, not implemented in this snapshot.

### Audio: isolated cold-start defect reproduced and repaired locally

Without a valid v2 preference file, AudioPreferences inferred intended volume from temporary AudioServer mute bits. A cold muted bus therefore became volume 0; the slider later reapplied gain/mute. The snapshot fixes this by using explicit defaults 1.0 when no valid main/backup preference exists and reapplies settings even for an equal-value slider request. Valid saved zero still stays muted; nonzero values and backup validation remain authoritative.

The new cold-start real-service test was FAIL before and PASS after with native exit 0 and no engine errors. Handset verification is NOT_RUN. The old strict-config test still calls the removed `_initial_level()` helper and needs its malformed-config expected defaults updated to the new contract; this is a known follow-up, not a passing full regression claim.

## Requested review

Read the fixed source and evidence, then identify concrete root defects with source locations and minimum complete repairs. Prioritize: (1) separating necessary acquisition/damage entry from optional pursuit planning without adding a second clock/HP/target owner or a long-frame burst; (2) why the real prepared death never reaches ground materialization; (3) safe exit including visible paused-menu feedback; (4) audio initialization review. Preserve 300ms AI planning and per-frame collision/committed combat semantics. Do not propose arbitrary delays, bigger budgets, TTL resets, restore old fallbacks or weaken save/identity gates. Distinguish source proof from hypotheses and recommend narrow missing diagnostics/tests.

Evidence is under `evidence/`; trace reports are read-only analyses, not acceptance. Tests may intentionally FAIL. Current gameplay repair is incomplete.
