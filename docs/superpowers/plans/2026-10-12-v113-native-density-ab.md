# v113 Native Density A/B Implementation Plan

> For agentic workers: use executing-plans for the controller's sequential work; use bounded workers only for independent files. Keep a run ledger and retain failures.

**Goal:** Determine whether a native batch kernel can reduce the complete v113 crowd CPU cost without reducing real gameplay work, with density and activation timing recorded only as scenario conditions.

**Architecture:** Measure the existing production world at 10/20/30/40 active actors. Profile contiguous candidate/geometry coverage; do not turn this into a separate density investigation. If its measured portable coverage can support the acceptance target, replace one synchronous pure-computation boundary with an equivalent native batch; retain live physics and state submission in their existing owners.

**Tech Stack:** Godot 4.7 console/headless, Windows, official godot-cpp/GDExtension, project test runner and isolated per-run userdata.

**Spec:** User-provided `HardCore_v113_CPP_群怪批量计算_PC_AB实验方案_20261012.md` in Downloads (actual filename is URL-escaped), plus the user's density report and explicit authorization to construct in the existing v113 tree. The latest user venue instruction overrides the attachment's new-worktree requirement. The attachment does not authorize APK delivery, merging, pushing, or unrelated gameplay changes.

## Global Constraints

- Venue: `C:/Users/Administrator/.codex/worktrees/milestone-v113-frozen/HardCore`, branch `codex/milestone-v113-frozen`, baseline `bd73a256493bf41f9c75c19998c84792f74e2262`.
- Main `codex/integration` source, HEAD, real index and pre-existing dirty contents are protected. No implementation or imports in main.
- Original v113 APK/tag/source archives remain preserved. Preserve the pre-experiment source ledger; clear read-only only on exact files that require an authorized experimental edit. Keep the worktree locked against removal.
- Same map `913203`, actor IDs, physics settings, RNG seed and player input policy between modes within a cell. Do not override v113 production timing/decision/budget defaults to old v107 test policies.
- Counts: 10/20/30 active with 34 total actors, background actors filling the balance; 40 active with 44 total. The primary C++ feasibility workload is clustered; scattered calibration is retained as background context.
- All designated active monsters must actually participate. Density must be measured during the window, because scattered actors can converge naturally. No overlapping or illegal initial spawns, forced sleeping, skipped collisions, reduced attacks, or cached stale world coordinates.
- Windows: 300 real physics ticks with complete gameplay work; 48 real loot nodes. Keep the sustained-alive CPU window distinct from death/drop completion regression, since deaths disable callbacks. Do not impose 10200 on background deep-sleep or death windows.
- Single-thread synchronous native computation only; no native authority for HP, movement, attacks, save state or node lifetime.
- All packing, dispatch, native entry, kernel, writeback and fallback costs belong to the complete cost ledger. Record mutually exclusive intervals; do not add nested inclusive timers.
- PC-only. APK and DEVICE TEST are NOT_RUN. Do not claim mobile fluency from headless CPU results.
- Official status field uses project PASS/FAIL/BLOCKED/NOT_RUN/MISSING. Partial or inconclusive is an explanatory classification, not a new status enum.

## Review Focus

- Scattered monsters must be active, not sleeping; validate target acquisition and actual progress.
- Clustered spawn geometry must be legal and collision-safe; quantify nearest-neighbor density without changing AI.
- Runtime convergence must be reported; reject the density comparison if both windows become equivalent in measured density.
- Central dispatch and data preparation must not vanish outside Enemy timing; record both physics and process work.
- Geometry order, contact boundaries, array precision, callback revisions and fallback preserve the original results.

## Task 1: Protection, runnable environment and v113 density fixture

**Files:** Create `outputs/native_batch_ab_v113_20261012/` receipts; create `tests/framework/native_batch_density_v113_20261012.{gd,tscn}`. Keep old fixtures unchanged.

**Interfaces:** Environment `HARDCORE_NATIVE_AB_ACTIVE` (10/20/30/40), `HARDCORE_NATIVE_AB_DENSITY` (scattered/clustered), `HARDCORE_NATIVE_AB_LABEL`, `HARDCORE_NATIVE_AB_PROFILE` (0/1). Produce per-run workload, time series, density, counter and source-bound JSON plus framework receipt.

- [ ] Record HEAD/status/index, pre-existing line-ending-only dirty entry and main-file hashes. Record bootstrap's old branch whitelist failure; perform equivalent protection checks without modifying the gate.
- [ ] Prepare a physical imported-resource cache in v113 and isolated test userdata; shared engine is read-only. Verify the unchanged tracked baseline hashes.
- [ ] Build the dedicated fixture using existing formal world/map/player/monster/loot APIs; retain production policies. Run layout checks and preserve any failure.
- [ ] Observe initial 10 scattered/clustered and 30 clustered windows; confirm legal workload and distinct measured density before collecting acceptance runs.

## Task 2: Continuous batch coverage and stop decision

**Files:** Controller's aggregation/report in `outputs/native_batch_ab_v113_20261012/`. No gameplay source edit for initial attribution.

**Consumes:** Task 1 production counters and residual phase snapshot. **Produces:** one named candidate boundary with measured share and a coverage decision.

- [ ] Run one diagnostic pair using existing counters: neighbor candidates/query, motion candidates/clear call, body/polygon checks, pool refill/revision misses, batch queries and residual phases.
- [ ] Obtain same-source B0 repeated windows, warmup excluded; preserve per-run timings and actual work. Detailed instrumentation results remain diagnostic.
- [ ] If portable contiguous work cannot reach 20% Enemy reduction even at infinite kernel speed, report FAIL for the requested target and stop native expansion. Explain lower achievable benefit separately.

## Task 3: Minimal native boundary, conditional on coverage

**Files:** New `research/native/crowd_batch_v113/`, new bridge under `scripts/monster_ai_package/`, new ABI contract fixture. Modify exact production consumer only after RED ABI evidence and source backup.

**Consumes:** A current synchronous numeric candidate batch. **Produces:** stable candidate masks/indices/order, no world state write.

- [ ] RED: missing native entry/ABI test fails for the intended reason; retain receipt.
- [ ] Pin SDK/API/engine/compiler/precision; build one optimized Windows library. Use Packed-array pointer access inside C++ and caller-owned output buffers where legal.
- [ ] GREEN: geometry/order/bounds/NaN/Inf/revision/fallback contract checks with real original results.
- [ ] Retain a same-algorithm GDScript batch control. Connect one current synchronous boundary; no multi-monster stale snapshot or physics replacement.

## Task 4: Full CPU A/B acceptance

**Files:** mode runner/summary under `outputs/native_batch_ab_v113_20261012/`; exact tested changes only.

**Consumes:** B0 original, B1 native-off apparatus, N1 native-on, optional GDScript batch control. **Produces:** repeatable complete-cost and behavior comparisons.

- [ ] Freeze inputs and source per run; use formal runner, ordinary 30-second timeout or the known-heavy 60-second whole-world fixture, tracked scene gate and unique run/invocation.
- [ ] 30 active clustered: minimum 5 complete effective runs/mode plus warmup. Rotate mode order. B0/B1 unexplained overhead over 3% invalidates apparatus.
- [ ] B1/N1 establishes native attribution; B0/N1 must meet final >=20% complete Enemy and >=10% complete physical work reduction, with P95 not worse and process/queue work not displaced.
- [ ] Extend the same-source load ladder to 10/20/30 and valid 40-active case. Record density and activation; do not add a separate density experiment.
- [ ] Death/drop and behavior regression remain separate valid load phases. Retain failures and explain irreducible differences instead of selecting favorable runs.

## Task 5: Review and disposition

- [ ] Source/protection/diff review, full receipts and per-mode comparison. Do not overwrite a failure with a retry.
- [ ] Record PASS/FAIL with missing/unrun scope, achieved reduction and density dependence. Preserve original milestone and main tree.
- [ ] No automatic APK, merge, push, or new-game integration. Experimental code remains identified as research unless separately accepted.
