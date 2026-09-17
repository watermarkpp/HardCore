# Monster Struck R1 — Remote Review Results & R1.1 Continuation Plan

- Date: 2026-09-17 (review received; work resumes next session)
- Reviewed commit: `191683a01990f9cbec7b667e70120a5ef4142d56` (branch `codex/monster-struck-r1`, pushed to origin, base `4cbc5a93`)
- Reviewer verdict: **R1 gameplay core accepted. Full vanilla action-queue semantics not yet closed. Do NOT merge to integration yet.**

## 1. Review verdict table (final)

| Item | Verdict |
| --- | --- |
| Remote delivery authenticity (18 files, 1 commit over base) | PASS |
| Ordinary STRUCK attack tick `150 - min(130, level*4)` | PASS |
| `_attack_timer` negative deadline semantics | PASS |
| Committed attack not cancelled by STRUCK | PASS |
| Ordinary STRUCK does not lock movement / no control_time / cadence untouched | PASS |
| Dynamic ActStruck duration (`frame_count("hit") x max(80, 200 - level*5)`) | PASS |
| Direct magic walk delay 800..1799 ms, MAC=0 boundary, anti-magic miss boundary, Lv50 boundary | PASS |
| FireWall = MAGSTRUCK_MINE (no walk delay) | PASS |
| Poison HP-only, no STRUCK | PASS |
| Backlog >= 2 countdown at 1.5x; death clears queue; 255 cap | PASS |
| Walk-delay RNG drawn from target gameplay `_rng` | ACCEPTED (no rework; matches vanilla server-side `Random(1000)` stream ownership) |
| `source_exempt` runtime wiring | **P2 not closed** (dead parameter, hardwired `false` at call site) |
| Poison increments `hit_animation_requests` | **P2 small bug** |
| STRUCK started -> next attack presentation overwrites it | **P1 FAIL** |
| Re-validation against latest integration | **NOT_RUN** |

Baseline failure agreed: `monster_world_integration_test` (V505 loot profile) is pre-existing on clean `4cbc5a93`, not an R1 blocker.

## 2. P1 — STRUCK started can be stolen by the next attack presentation

Root cause in current code:

- `MonsterVisual.play_attack()` sets `_attack_remaining = duration` without checking `_hit_remaining > 0`.
- Visual priority is death > attack > hit > walk, so a newly started attack covers an in-flight STRUCK.
- `_hit_remaining` keeps counting down in the background while covered, so the remaining STRUCK silently burns away — exactly the "burning in the background behind a higher-priority action" defect R1 set out to remove, now on the struck->attack direction (the attack->struck direction is fixed).

Vanilla evidence: the client Actor loop `while (m_nCurrentAction = 0) and GetMessage(@Msg)` consumes the next message only when the current action finished (idle = `m_nCurrentAction = 0 AND m_MsgList.Count = 0`). So once STRUCK is the current action, the following attack message waits.

### Required fix shape (R1.1 Visual Action Queue Closure)

- Presentation only. Do NOT touch gameplay authority: `_attack_timer`, `_pending_attack_damage`, `_pending_attack_release`, `_pending_attack_time`, WalkTick, `walk_count`, `walk_wait_locked` must stay exactly as they are.
- Split `play_attack()` into `request_attack_visual()` (O(1) pending slot when `_hit_remaining > 0`) and `_start_attack_visual()` (actual assignment). STRUCK finish (in `_try_start_pending_struck` / timer expiry path) then starts the pending attack presentation.
- Never implement this as AI denial ("STRUCK period -> monster cannot attack/move") — that would recreate the rejected gameplay-stun semantics. Attack logic stays Ready; only the visual waits for the action queue.

## 3. New tests required for closure

1. Reverse case in `tests/monster_struck_visual_queue_test.gd`: idle -> `queue_struck` -> struck actually started -> `play_attack()` (or the new request API) while `_hit_remaining > 0`. Assert: hit stays the current presentation action; `_hit_remaining` does not burn in the background; attack presentation does NOT preempt hit; after hit finishes the attack presentation starts.
2. Boundary check (P1 verification item, presentation layer only): STRUCK started -> WalkCadence grants the next step. Confirm no "recoil pose sliding on the ground" appears. If it does slide, fix at presentation layer only. Ordinary STRUCK must never add `WalkTick += hit_duration` (no movement hard-stun).

## 4. P2 fixes

1. `enemy.gd` `_apply_damage_core()`: gate the legacy counter so a poison/DOT tick does not claim a hit animation:

   ```gdscript
   if causes_struck and visual != null and current_hp > 0:
       _record_performance_counter(&"hit_animation_requests")
   ```

2. `source_exempt` decision (choose one, do not leave a dead parameter):
   - Option A: wire the real exemption authority into the runtime call (`direct_magic_can_delay_walk(int(raw_level), source_exempt)` from an actual source).
   - Option B: documented Evidence Note that every known exempt monster (vanilla `TCowKingMonster.Create -> bo2BF := True`; 牛魔王 Level = 60) is already blocked by the `Level < 50` gate, and remove/justify the parameter instead of leaving it hardwired `false`.

## 5. Next session work order

1. Rebuild the task branch on the advanced integration base `095a4d7c87e3e72482b69dc69225191c31f8e16e` (`codex/integration` moved +4 commits: player STRUCK implementation, FireWall 3x3 SOT test fixes; note `game_root.gd` conflicts are possible — its `_apply_canonical_ground_tick()` there still lacks the `MAGSTRUCK_MINE` argument). Rebase or cherry-pick `191683a0`, resolve `game_root.gd` deliberately.
2. Implement R1.1 P1 (attack presentation pending slot) + both P2 fixes.
3. Add the two new tests (attack-after-struck closure; movement boundary observation).
4. Re-run: monster suite, player struck suite (player/enemy interaction), fire wall suite, direct spell parity suite.
5. Push updated branch for re-review. Only after P1 closed and suites green may integration merging be discussed.

## 6. Session-local facts (do not put in AGENTS.md)

- Worktree: `C:\Users\Administrator\Documents\hc-monster-struck-r1` (Junction `tools/godot-4.7` -> main worktree; per-tree `.godot`; runner worktree mutex).
- Pre-existing flaky tests (documented, NOT R1 regressions): `monster_special_delivery_runtime_test` and `classic_boss_order_test` fail ~10-25% (player computed anti_magic_points=1 / 10% magic evasion vs deterministic assertions; failed assert skips `queue_free` cleanup, residual player joins `combat_targets` group and pollutes later frozen sets). Baseline 20-run sample: 3 fails. `safe_zone_spatial_runtime_test` occasionally times out under suite load (loads `main.tscn`, waits up to 1800 frames); isolated runs PASS.
- `monster_world_integration_test` fails on clean base (V505 loot profile) — pre-existing.
- RuntimeDiagnostics counters used by the struck tests require `RuntimeDiagnostics.set_device_lab_performance_enabled(true)` in the test.
