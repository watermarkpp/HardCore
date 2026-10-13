# v113 crowd computation implementation plan

Date: 2026-10-13. Authorized by the user's three approved directions: remove proved redundant work, evaluate independent worker computation, and reduce preparation/object/commit overhead.

## Global constraints

- Work only in the v113 maintenance worktree, HEAD bd73a256493bf41f9c75c19998c84792f74e2262. Main tree is protected. No commit, push, APK or version change in this task.
- Preserve production gameplay, actor order, live collision, movement, combat cadence, owner budgets, attack/HP/save authority and workload. Do not revive the rejected occupancy-grid experiment.
- Preserve all pre-existing dirty/untracked files and original native density fixture/wrapper bytes. Protection baseline: outputs/crowd_compute_optimization_v113_20261013/PRECHECK.json.
- Use scoped backups before clearing readonly flags. New tests use an isolated temporary Git index and isolated per-invocation APPDATA through tools/run_godot_tests.ps1. Production source freezes during every engine invocation. Normal test timeout 30 seconds; known 300-tick workload 60 seconds.
- Evidence must distinguish exact scalar correctness, actual live workload, PC CPU/frame interval, worker overhead, and device acceptance. No claim of a 50% reduction or guaranteed absence of stutter.
- Existing source-matched evidence is reused; new tests are justified by changed dependencies or missing contracts. Original failures remain archived.

## Task 1: exact duplicate and candidate-cache changes

Read outputs/crowd_compute_optimization_v113_20261013/DUPLICATE_ANALYSIS.md. Own scripts/monster_ai_package/policy.gd, scripts/runtime_combat_spatial_index.gd, scripts/enemy.gd and new direct contract tests only.

Move the pure after-distance expression into its existing short-circuit branch. Add a fixed 128-event, seven-int64 mutation journal to the existing index, covering all six mutation paths. Preserve the global revision fast path; use enemy_bucket_pool_unchanged_since(map, Rect2i, revision) only to prove unrelated mutations cannot affect a cached full-bucket identity pool. Max-bounds growth, map clear, local membership change, missing/overwritten history and invalid revisions must conservatively refill. Positions and eligibility remain live.

First run meaningful new API tests against unchanged production (expected missing API), then implement and freeze for checks. Test geometric boundary/degenerate/random exact equality against the frozen original function, local/remote/other-map mutation, live same-bucket movement, replacement/clear/lazy cleanup, bounds growth, bounded memory and int64 revisions. Extend evidence with reference complete-bucket query comparisons; do not use the new predicate as its own oracle.

## Task 2: same-source measurement and integration validation

Read HARNESS_REUSE.md in the same evidence directory. Copy the old density fixture and wrapper into new names, preserving exact load/input/layout and initialization order. CONTROL/CANDIDATE/SHADOW use the same source and object/preload allocation. Candidate defaults to the accepted production path; control/shadow hooks are test-only. Shadow checks full original candidates/results at the same live call; shadow time is not performance evidence.

Record source and engine fingerprints, exact commands, native exits/receipts/userdata, counters and completed work. Run direct affected regression scenes and 30/40 clustered shadow; then an interleaved control/candidate pair each. Add repetitions only if the result remains uncertain/noisy, recording why. Report actual work differences and do not equate the same seed with strict frame-by-frame identity. Reject changes whose overhead outweighs measured benefit.

## Task 3: independent static geometry worker probe

Read PARALLEL_ANALYSIS.md. Record real static footprint queries from the retained 30/40 workload, preserving exact numeric inputs and one immutable map snapshot. Replay the same complete requests serially and with WorkerThreadPool using private numeric data and pure SAT geometry. Record capture/preparation, dispatch, worker CPU, waiting/join, output assembly, batch sizes and memory. Compare every result exactly.

This is an experimental kernel replay until a real production scheduling boundary demonstrates useful overlap and lower total main-thread cost. Do not move live Node/physics/state queries off-thread, delay their consumption, or install a slower worker path just to use more cores. Preserve negative results and explain any excluded production route.

## Task 4: review and disposition

Fresh Astra review of the scoped diff and complete evidence; fix material defects and rerun only covering checks. Compare protected before/after files, original fixture hashes and real index. Review full relevant diff/stat/status/check. Leave proven beneficial changes reviewable in v113; archive/revert only this task's rejected changes from its own backups. Provide measured outcomes, remaining limits, files and evidence paths. Device test remains NOT_RUN without a new device run.

## Task 5: added all-monster obstacle navigation repair

The user authorized fixing monster 236 around the central rock of map 918005 and checking all monsters for the same defect. Native RED now confirms small body 64 finds a clear detour while large bodies 89/236/224 return UNSUPPORTED_POLYGON_RADIUS. The global inventory covers 156 admitted identities and all 67 implemented maps. Preserve exact formal body conversion: the large radius prints as 0.5 but its actual binary key from Godot is ffffffffffffdf3f; do not round to a decimal approximation.

Correct the generator's obsolete radius source using current ActorBodyPolicy and the formal spatial conversion; retain legitimate existing extra profiles. Reject missing/malformed body inventory and insufficient profiles at the formal candidate/publication boundary. Rebuild only navigation through official MapEditor BuildService APIs from each unchanged latest editor document. Never invoke obsolete spawn canonicalization. Explicit per-map manifests/backups and the dedicated publication wrapper protect source, collision geometry, spawn/NPC/portal data, ground and visual content, and sibling maps. All publication jobs retain bounded timeouts, native receipts, and protected real index.

After map 918005 passes the real central-rock route, publish the remaining proven-missing profiles, verify all 156 by 67 combinations and related polygon/build contracts, then validate an actual formally spawned boss pursuit. Static/direct path success is distinct from an actor or device result.

## Current performance disposition

Task1 direct 4227-check PASS plus live 30/40 shadow and affected regressions support KEEP. User explicitly retains the measured local collision-query improvement. Two alternating A/B pairs per load preserve actual workload variation and do not claim a stable whole-frame improvement.

Task3 has two completed native replay stages, using the same exact recorded corpora. Immutable shared ranges remove avoidable transfer copies, but actual per-tick work still loses at 30 and is only about 1.26% better at 40 with overlapping intervals. Do not promote this narrow kernel to production. Preserve both reusable experiment stages and all negative results. Phone design targets user-confirmed Honor REA-AN00 with initially 1/2 in-flight jobs, never ten actors as a hard rule or desktop core count. Production-safe batching and phone performance remain NOT_RUN.

## Added real readiness observation and final disposition

User clarified that useful parallelism requires earlier input preparation and overlap with ordinary main-thread work, rather than immediate waiting after dispatch. The controlled ASYNC_DEPENDENCY_30_01/40_01 windows observe actual committed-leg ready events and original consumption; both native runs PASS with their own complete source/receipt/trace bindings. They preserve the real 300-tick workload and original synchronous answers. Real candidate-region advance windows exist, but the entire covered original kernel wall totals only7.253/8.811ms per300ticks; that is an upper accounting envelope, not measured removable cost. Actual polygon path submit/service counts are1/1 and0/0. Do not promote a production worker on this evidence. The larger movement/state/engine work still lacks an established equivalent independent packet boundary. No frame-rate or 50% reduction claim is justified.

All67 navigation targets are formally published. Final coverage11142/11142 PASS includes156×67 identities/profiles and67 formal runtime/visual loads. Actual boss236 pursuit around the stone35/35 PASS; navigation API recovery30/30 PASS. The original failing legacy fixture and missing uniform receipts remain explicit.

Temporary production observers are restored byte-for-byte. Capture-only scene copies requiring those observers have been precisely archived and retired; reusable numeric replay remains available. See `outputs/crowd_compute_optimization_v113_20261013/EXPERIMENT_REUSE.md`. Final results, retained measured gains, negative thread results and evidence gaps are in `RESULTS.md` and `FINAL_SCOPE_AUDIT.json`. Main metadata remains unchanged; full initial dirty-file byte proof is missing. The initial v113 index-byte discrepancy remains unclassified despite unchanged staged semantics and protected native windows. No commit/push/APK/device acceptance occurred.
