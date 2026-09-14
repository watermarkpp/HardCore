# v82 performance-only scope

- Controller-owned branch: `codex/performance-v82-20260914`.
- Baseline: `643d4185cfb3c67f86c0821d5c2393ba0c1581e2` (accepted v81).
- User request: remove BGM-start, crowd and AOE stutters; preserve gameplay and all accepted content.
- Serial ownership: controller handles shared performance infrastructure, then targeted consumers and tests; no parallel engineering writers.
- Frozen: `assets/**`, map authoring, UI layout/presentation/text, all numeric gameplay data, combat cadence/reach/targeting, snapshots, damage/tick/stacking rules, save compatibility. Android version code alone advances for install compatibility at release.
- Preserve pre-existing user `AGENTS.md` changes and 68 untracked UID/translation files. Original AGENTS SHA256: `B1512F2A8C91C2AE499944000FC15F27ED373542483D3EF9476845A703AFBCC9`.
- Read-only GLM scan in existing Harness (actual model GLM-5.3-Flash, view-only mode); candidate locations only. CLI sandbox failed before reads; stopped that invocation. No DeepSeek model or engineering delegation.

## Measurement and change gates

1. M30 production actor fixture: same seed, 30 actors, pursuit/close-combat/crowding; real elapsed frame intervals and timed physics segments. Headless CPU evidence is not device/GPU acceptance.
2. Component probe: real fire animation frame progression, six fields worth of visuals (54 cells), dense exact-phase plus nonlethal EnemyActor damage; separate temporal-claim parity tests. Component times are not game FPS.
3. BGM source load and playback startup measurement, then lifecycle checks if changed. No timing, volume, track or city-rule changes.
4. Only proven hot paths receive production edits. Preserve exact outputs, test cache/lifecycle invalidation and run affected formal regressions.
5. Final diff/frozen-tree review, commit, isolated APK build, signature/version/source verification, desktop delivery. Device acceptance reported separately.

## Initial evidence

- Existing M30 probe had stale `_apply_attack_damage` override missing final `ranged` parameter; repaired test forwarding only.
- `rev07_v82_baseline_30_r1.json`: 30-actor frame P95 pursuit 15.021 ms, close 18.401 ms, crowd 17.341 ms.
- `component_baseline_r1.json`: 54-cell configuration 38.339 ms; 360 animation updates average 86.391 ms; first texture no longer retained after advancement. Dense 30-target exact + damage batch average 0.603 ms (120 batches).
- BGM resource load 15.527 ms; first `AudioStreamPlayer.play()` 0.934 ms, subsequent about 0.4 ms (Dummy driver).
- Raw local evidence: `outputs/performance_v82/`, `outputs/hc_monster_ai_package/`, runner receipts under `outputs/test_logs/`.
