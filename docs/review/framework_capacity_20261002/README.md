# Capacity increment — review only, 2026-10-02

Whole capacity admission remains **FAIL**. This checkpoint does not close P3/P6 or the reported v97 backpack defect. The main v97 tree and second tree are preserved; no integration, version change or APK publication.

The exact current native source set contains 3460 files, SHA256 `6d5ca9e1540f99dae93ec6a8e11569d71bc4d80c6ab333196287dc0bce7d4970`. Construction HEAD is `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`; compare this review increment with `d7f9b7f79d4f96c16b9327e29b0bd281e1cd3079`. Native engine SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`. Two profile-switch fixture files already present at this segment's start were outside the earlier d7f9b7f tested manifest. Their hashes stayed identical in every run; they are preserved as preexisting **NOT_RUN** context, not new work or passing tests. See PREEXISTING_UNEXECUTED_TESTS.json.

## Implemented and tested

`damage_batch.gd` exposes a non-consuming count only for valid sealed batches. `effect_runtime.gd` checks the whole buffer destination before spending its one-shot consume right. `game_root.gd` explicitly reports a failed nonempty submission; valid misses/empty releases remain no-ops. Committed base HP is never undone. No HP/death/planner/item/save authority, time domain, RNG policy, default-enabled flag, balance, map, or entity identity changes.

The original RED suite has 35 checks and 5 failures. The final atomic boundary test has 25 checks PASS: real queue capacity minus one/full/plus one, a two-receiver batch refused atomically with one slot free, later exact retry, no duplicate HP, no duplicate consume, unsealed producer rejection. Eight direct native regressions have 147 checks PASS, with the same three production-file bytes as this checkpoint. Their only later source difference is this standalone capacity test, which those eight scenes do not import. No broader current-suite PASS is claimed.

## Preserved counterexample

The final admission test has 19 checks, 3 FAIL, with no script/engine log errors. It uses the real mapped Root, Player input, canonical planner, actual HP writes, compiler-validated retained sources and real queues. Three AOE receivers each retain sixteen legal historical sources; the new distinct source is still accepted and enters cooldown. All three base HP writes complete, then derived state admission refuses capacity. No HP or occupancy counter is mocked. This is the remaining defect, not a weakened expected result.

## Architecture questions for Pro and the parent

1. The RFC locks numbers at acceptance but samples geometry/receivers at release and preserves all-intersecting AOE. A reservation needs a proved legal maximum fanout, including births/life replacement during windup. Current-target counting, arbitrary timers, truncated target lists and unbounded growth do not prove that contract. Establish the authoritative fanout/admission envelope before implementing a purported complete fix; the thirty-target P6 fixture is explicitly not a gameplay maximum.
2. Candidate lifecycle: a capacity permit owned by the existing EffectRuntime, attached to the accepted ActionConfigLease, transfers only after the base batch seals and closes after consumer drain. It could support safe release-receipt retirement once old producer capability is revoked. This has not been implemented or accepted as the final design. Persistent journal64 full rejection and old-op idempotency must remain separate; no TTL/LRU/eviction.

Full P0–P6 and known defects remain in scope. Do not reopen previously closed fire cooldown/future ownership/socket/identity scopes or enable test gem/ignite as formal gameplay. Remaining acceptance includes profile/credit narrow timing, receipt retirement, combined 90 statuses/360 periodic deliveries with deaths/drops/resources/persistence, fairness and business latency, P95/P99. Exact user historical B input MISSING; causal backpack fix NOT_RUN; GPU/APK/device NOT_RUN.

Native bytes: reconstruct the prior d7f9b7f reviewed source in an independent inspection directory, apply `NATIVE_DELTA_FROM_D7F9B7F.zip` under `source/`, then verify `TESTED_SOURCE_MANIFEST.json`. Never restore this archive over an active tree. No user save, credential, engine binary or cache is archived.
