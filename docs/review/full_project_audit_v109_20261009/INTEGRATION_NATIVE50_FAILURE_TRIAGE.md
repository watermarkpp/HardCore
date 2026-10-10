# v109 related50 integration failure triage

Status: PASS for read-only diagnosis. The runner was executed against the frozen current runtime tree `15d50727638876e89e67ca7913deaf30d9d53611`; no source, fixture, data, engine, or Git changes were made here and no scenario was rerun.

Evidence root: `outputs/test_logs/v109_related50_integration_remainders/`. The raw native receipts are under `raw/<run-id>/native_result.json`; the corresponding stdout/stderr are retained under the same directories. The runs use Godot `4.7.stable.official.5b4e0cb0f` and the isolated runtime appdata `C:\Users\Administrator\Documents\HardCore\.godot\runtime_appdata\v109_related50_integration_remainders`.

## Findings

### `enemy_mass_death_batch_pipeline_test`

The functional scenario reached `ENEMY_MASS_DEATH_BATCH_PASS deaths=32 checks=235 rng_parity=1 save_commits=1`. The wrapper is nevertheless `FAIL` because stderr contains one cleanup warning group: eight leaked ObjectDB instances, a `get_path` call on a node no longer in the scene tree, and three resources still in use. There are no assertion failures, engine-log failures, or nonzero native exit.

This is a fixture cleanup problem, not evidence that the death/drop pipeline failed. The current test creates an unused `LootRuntimeScript.new()` at line 48, while `GameRoot` already owns the runtime manager; that object is a concrete first cleanup suspect. `_finish()` also frees each enemy and then the game root directly, so the `get_path` warning indicates at least one deferred child/service callback is being torn down after its parent has left the tree. The receipt does not identify all eight objects, so the remaining ownership set is unproven. Recommended action is a focused verbose cleanup pass, removing only the unused preview instance or explicitly releasing it and checking the existing GameRoot-owned manager lifecycle. Do not downgrade the 235 functional checks or call this scenario fully PASS until stderr is clean.

Evidence: raw run `0892fc4e-982f-40e7-99f7-f01c39d7515f`, `native_result.json` SHA256 `d0a9dcb784a13d09b4049ddd1cdf889813766c1247954ed31580a37bd9797bd8`; stdout contains the PASS marker; stderr is `raw/0892fc4e-982f-40e7-99f7-f01c39d7515f/enemy_mass_death_batch_pipeline_test.stderr.log`.

### `combat_epoch_delivery_test` E01

The failing assertion is at `tests/hc_monster_ai/combat_epoch_delivery_test.gd:261-263`: it expects `_pending_attack_release_record.kind == "hc_standard_melee"` after one ordinary melee physics tick. The current production source has `scripts/enemy.gd:510-513` with `ordinary_contact_instant_settle` defaulting to `true`. In `_hc_try_start` at approximately lines 9891-9896, source176 ordinary melee sets `hit_delay` to `0.0` when that flag is enabled; the record is then settled immediately at approximately line 9970, and no pending release record remains. The fixture’s `_attack_hit_delay = 0.05` therefore cannot force a delayed ordinary release in the current production mode.

This is a stale mode assumption in the fixture, not a demonstrated production regression. The same file’s E03 target-magic assertions already encode the current activation-settlement contract. If the E01 purpose remains testing committed delayed-release/epoch cancellation, the minimal fixture seam is to enter the explicitly supported test policy `EnemyActor.configure_attack_visual_policy_for_test(false, ...)` around that case and restore the production value afterward. If the intended v109 contract is instant ordinary contact, E01 must be rewritten around immediate settlement while retaining the epoch boundary check; that is a contract decision, not a reason to weaken the current assertion silently.

Evidence: raw run `3db83563-54ab-4df8-9edd-320980ee9df2`, `native_result.json` SHA256 `7eab5f99577e3d1f3c837940b3968f37c5c92f890224288a0d04fd5ff750eab4`; stdout records only `HC_TEST_FAIL E01-freeze` and `HC_COMBAT_EPOCH_DELIVERY_FAIL checks=38`, with no stderr failures.

### `monster_magic_reaction_continuation_test` formal committed-release case

The four failures are the assertions at `tests/monster_magic_reaction_continuation_test.gd:172-177`: the formal accepted record is empty, has no release id or damage, and has no pending delay. The fixture sets `enemy._attack_hit_delay = 0.1` at line 166, but then calls the real `_hc_try_start`. As above, the current default `ordinary_contact_instant_settle` makes source176 ordinary melee use zero gameplay hit delay, immediately calls `_hc_settle`, and leaves `_pending_attack_release_record` empty. The later struck/release assertions consequently cannot run against a pending record.

This is the same stale delayed-contact assumption, independently reproduced by a second fixture. It is not a random damage or target rejection: the test has already established an ordinary melee actor, and the current production branch deliberately ignores `_attack_hit_delay` for source176 ordinary contact when instant settlement is enabled. The minimal test-only repair is to select the explicit delayed-contact policy for this committed-release subcase and restore it in a `finally`-equivalent cleanup path, or to change the case to a delivery kind whose formal contract actually has a pending release. Do not make production ordinary contact delayed just to satisfy this old fixture.

Evidence: raw run `b8a2f496-c19f-4cd3-b6cd-fbbcea6bafe8`, `native_result.json` SHA256 `c911f7bcb2e6c7f7e7ddb80a9ebc1cbfd423087f0f25dbb75d78e27c4c1da03a`; stdout records the four exact errors and `MONSTER_MAGIC_REACTION_CONTINUATION_FAIL checks=91`, with no stderr failures.

## Other scenarios in this runner

The other eight raw receipts are native PASS with zero stderr failures: `player_hit_reaction_policy_test`, `release_lifecycle_test`, `player_skill_struck_chain_test`, `monster_attack_los_cache_test`, `monster_struck_runtime_test`, `special_actor_target_magic_gap_test`, `w1_exact_ranged_delivery_test`, and `monster_target_magic_attack_test`. Those results do not override the three findings above. The current run is therefore `FAIL` as a complete 11-scenario set, with two contract-mode fixture failures and one cleanup-only wrapper failure.

No production bug is proven by these three failures. The minimum next work is fixture policy alignment for the two delayed-release cases and a narrow verbose cleanup investigation for the mass-death fixture; keep the original failed receipts and do not alter load, HP, timeout, or assertions to obtain a green.
