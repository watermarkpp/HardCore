# 2026-09-13 repair and APK acceptance

Controller: current Codex/Astra. No engineering delegation. GLM read-only scan attempted via the approved arkcli profile; returned BLOCKED (`CreateProcessWithLogonW failed: 2`) without project evidence. Controller continues targeted investigation.

## Baseline and preservation

- Original checkout: `HardCore`, `codex/m30-r3-integration`, `b3296528d7f85c7dff2c78adafaa0f5e4ec33c16`. Existing AGENTS.md edits and untracked translation/uid files preserved there.
- Sole implementation tree: `HardCore-worktrees/takeover-20260913`, `codex/takeover-20260913`.
- Latest UI candidate: `codex/r3-3-single-heading`, `e608c2c09fbe98ad2bce68344052af42c32d70b3`; inspected from Git, not the other tree's dirty test file. Integrated as `e38215978c481b988df3203410bb1dda6b5b0968`, retaining b3296528's audio missing-key and APK verification fixes, plus the verified touch activation repair.
- Bootstrap fails only because the task branch is outside its legacy route whitelist. Equivalent preflight uses `docs/agent_rules/integration.md`; required baseline, ownership and snapshot JSON files exist. Root user instructions apply to this serial cross-system integration task.
- Latest existing desktop APK: `HardCore-20260912-release-closure-v75.apk`; final delivery must preserve package/signing/save compatibility and use a newer version.
- Protected: authored maps, map geometry, monster count/stats/respawn, approved equipment base attributes, drop probabilities and retention ordering, attack ownership/cadence, latest manual UI layout. Only explicitly requested deltas (JP rolls, luck/curse, fire-wall 3x3, 0.6 height, drop cap 15, visual corrections) may change their related behavior.
- Original map trees: assets/maps `c46ea4b3146096113ae793236a87e4ceceb7812d`, map_editor_workspace `fa6c3e7a67d389e555cdf4140337f37cf0ee88f2`. Equipment master blob `fd8262dbc67bd65b978f63e38da728a84e2ecf37`. Latest UI layout must be preserved from e608c2c0, not restored from b3296528.
- Imported assets copied into independent task cache; tool binaries copied locally. dev_art_sources is a read-only-use junction to the existing local sources. No user saves copied or modified.

## Source acceptance and evidence

All source gates below are controller-reviewed working-tree evidence on the e3821597 baseline. `evidence/targeted_tests.json` records the latest result for each of 61 distinct tests: 61 PASS, zero unresolved test failures. A compact clean-HEAD gate and the isolated APK verifier will identify the final source commit separately.

| # | Implemented behavior | Evidence / limitation |
|---|---|---|
| 1 | Inclusive melee candidate pruning and bounded immutable-terrain walkability cache | Oracle, forced movement and query parity PASS. All 12 comparable CPU scenarios improve; device/GPU NOT_RUN. |
| 2 | Native-touch release commits selection exactly once; integrated latest single-heading docked detail UI and rarity names | Four input orders over reopen cycles; native level-30 weapon 99→102→99 replacement without closing; real equipment, warehouse and shop matrices; extreme body-scroll and action geometry PASS. |
| 3 | Original blessing conditional chain, exclusive effective luck/curse, omit zero lines | Exhaustive branches and 384 seeded RNG comparisons; real consume/save rollback and luck combat consumption PASS. Legacy dual-field saves retain their effective difference. |
| 4 | V2 ordinary JP supports independent DC/MC/SC maxima plus armor/helmet and formally identifiable bracelet AC/MAC maxima; binomial amounts instead of fixed +1 | 20,000 weapon samples, all 175 IDs, additive equipped stats, forged-value rejection and real save/warehouse/reload PASS. Original inner rates; single-player entry 1/10→1/2. V1 saved instances retain frozen +1 semantics. |
| 5 | Fire wall centered 3×3; flame height 0.6; world footpoint ordering for generic spells and ground/target effects | Canonical/golden snapshot and 12 fire-wall controller tests PASS; damage/tick/stacking unchanged. Existing lightning ordering retained. Device visual review NOT_RUN. |
| 6 | Weapon/body order comes from primary client WORDER[gender, action, frame] | All 37 weapons × two genders × eight run directions × six frames = 3552 poses PASS; same-direction action transition and wall/actor contract PASS. |
| 7 | Remove static-loot full-registry visual scans; prepare durable pickup bytes off the game thread; validate/promote and credit on main thread | Real gold/equipment/batch15 writes, failure/rollback, changed save authority, consecutive batches, map generation cancellation, and safe logout PASS. No speculative inventory credit. |
| 8 | Post-RNG ground cap 9→15 | Capacity generator and runtime PASS. Semantic comparison proves only two capacity values plus three hash bindings changed; probabilities, amounts, stable IDs and retention ordering are untouched. |
| 9 | Exact axes/thorns, source attack overlays, cow king MT13 and preserved actual arrow casters | 524 extracted PNG frames, per-frame source/pixel hashes, 13 live attack-overlay IDs, physical and target damage preservation PASS. Body-only source attacks remain body-only. |

No Android device is attached (`adb devices -l`, empty). Functional headless PASS does not imply a verified 60-FPS device package or visual human acceptance.

The JP scope above is the current ordinary primary-stat affix system. Original secondary byte lanes (weapon holy/speed/accuracy, accessory recovery/resistance/luck and random durability) are not included in this rollout; this is not a complete reproduction of every original `RandomUpgradeItem` byte. Exact per-item legacy StdMode is missing from the approved formal catalog; an unapproved candidate DB was not allowed to replace the equipment master. This remaining original-rule coverage must be reported explicitly, not hidden behind the distribution PASS.

## Final measurements and transaction review

- Identical fixture, seed, layouts, real actor counts 10/20/30, WORLD bodies and 150 sampled physics waits. All twelve P95 gates PASS; `evidence/performance_comparison.json` binds before/after measurements. Thirty-monster P95: open 21.047→16.047 ms, sustained attacks 24.908→19.920 ms, obstacles 19.278→13.822 ms, dense crowd 107.981→19.266 ms. The pathological dense case stops the physics catch-up amplification (297→150 sampled ticks). These are desktop headless CPU observations, not Android frame-rate claims.
- The initial synchronous save change still cost about 11 ms. Final ordinary pickup preflight averages about 1.4 ms; main-thread completion peaks around 2.7–4.1 ms across 24 real gold/equipment/15-item writes. Temporary write/flush/readback runs in a WorkerThreadPool task. It holds only validated bytes and a uniquely owned temporary path.
- The main thread rejects prepared results after a newer save, inventory/gold change, profile change or map/generation/path invalidation. It promotes validated bytes, checks the whole promoted file, then emits inventory/gold/UI feedback. A valid-but-different post-promotion document is quarantined and the previous good main restored. Normal save, shared warehouse and safe logout retain the same promotion gate.
- Final self-review exposed a second-batch scheduling edge: a deferred flush arriving during an active write left the queued flag set. A new real-ground reproduction failed before the fix and passes afterward; completion now schedules the pending cohort. Evidence: `async_consecutive_before.log` and final loot lifecycle runner 025455 (under outputs).
- New spell resources use at most two threaded load requests, a 48-MiB estimated RGBA resident cache, direction-local prefetch and priority for the currently drawn frame. Combat never joins a texture loader. The full 524-frame/real-actor source test passes after the cache change.

## Source and frozen review

- `evidence/preservation.json`: maps, manual map workspace, canonical monster catalog, equipment master, all UI image assets, latest manual UI geometry and rarity table match their baselines. No monster quantity, timing, AI behavior, base attributes or map collision edits.
- Firewall source JSON is UTF-16 and appears binary to Git. Semantic review finds only five fields on `wizard.fire_wall`: width, height, center policy, override note and required-test name. No other skill fields change.
- Primary client WORDER table extracted from `original_gameofmir/MirClient/Actor.pas`. Axes/thorns come from primary Mon3.wil. Seven overlay profiles use primary client archives. Cow king's exact auxiliary Mon21 fallback records primary archive absence and the primary commented-out MT13 construction/dispatch, then cites the compatible auxiliary client branch and archive hashes.
- All seven focused Python source/generation checks PASS; generators preserve every non-target source field and never regenerate approved item or map attributes.
- Fixed legacy test issues were classified: extreme UI test referenced nonexistent catalog identities and wrong owner coordinates; shop-only portrait assertion predated the current W≤1.3H shop contract; SPB census constants predated the already accepted V5.0.5 baseline. Source authority was inspected before correcting tests. No weakened durability, damage, identity or failure assertion.

## Build and delivery gate

Version code 76 / name `1.23.1-repair-20260913`, package `com.personal.mafaoffline`. Preserve v75 signing identity and save paths. Build only from the final committed source via `tools/build_android_isolated.ps1`, using the existing v75 desktop APK as signature/version baseline. `verify_android_build.ps1` must verify the source build-info, bytecode, package, signature, embedded content and version. Final desktop review report records APK SHA256, source commit, exact-HEAD gate and build result. APK build and device review were still NOT_RUN when this source evidence was committed.

## Retrieved requirements

Read current task plus ChatGPT project conversations: `UI修改方案`, `制定GLM修复方案`, `核对装备与武器问题`, `审查优化并打包`. Treat historical assistant diagnoses as candidates, not proof. Preserve docked details, title/body sizes 20/14, rarity names, music/SFX sliders with save-on-close, blank-tap dismissal without breaking function controls, no residual selection border, static ground drops, and no discarded-item success popup. Latest long-text contract permits body-only vertical scroll after legal geometry is exhausted. Weapon report also describes level-30 炼狱→井中月 replacement failing until re-entry; verify the real UI transaction while retaining item requirements.

## Verified intermediate repairs

- UI: simulated mouse-up can arrive before native touch-up on Android. The old guard rejected `BaseButton.pressed` before its authoritative touch release, then received no second pressed event. `UIActivationOnce._end` commits a validated native touch release using the existing serial reservation. All 5 input/activation/scroll regression scenes passed (`runner_results_adhoc_20260913_005538_945_19048.json`). Before/after evidence is in `outputs/takeover_20260913/ui_real_input_*.log`.
- Monster queries: unordered melee queries now exclude indexed positions outside the inclusive expanded segment bounds; ordered victim/damage queries retain their prior behavior. Batch output keeps single-query parity. Static cell walkability is memoized only for immutable terrain, keyed by context identity, exact radius and cell with bounded storage. Dynamic terrain, extra blockers, WORLD checks and actors stay live. The new oracle exercises real blocker preservation, context rebuild, radius edges and same-frame moves; 4 query/teleport/knockback scenes passed (`runner_results_adhoc_20260913_010913_239_14304.json`), plus batch and real melee runtime gates.
- Desktop headless comparison, same 12 scenarios/counts and production physics: dense 30 baseline P95 107.98 ms / 297 physics ticks / 4861 ms inclusive enemy CPU versus query patch 19.73 ms / 150 ticks / 1300 ms. Other 30-monster P95: open 21.05→16.76, sustained attacks 24.91→20.43, obstacles 19.28→14.41 ms. Files: `performance_baseline_e3821597.json` and `outputs/hc_monster_ai_package/rev07_takeover_query_after.json`. This is CPU evidence, not GPU or Android acceptance. Temporary profiling wrappers were removed after diagnosis; a measured sequential-query alternative was slower and was not retained.
- Loot: fixed-position icons are initialized at construction, so the 30-Hz full registry visual scan is removed. Updated tests assert zero visual work while retaining registered items, icon anchors, identity, collection/retry clocks and visibility behavior.
- Atomic saves: validate the serialized JSON representation once, then compare the complete temporary and promoted files to those exact bytes. Still validate the old main document, protect future versions, quarantine invalid mains and retain backup/rollback behavior. Real writes with 64 equipment records averaged about 12.0 ms before and 10.8–11.3 ms after for gold/single equipment/15-item batches. Remaining synchronous I/O must not be presented as eliminated. Seven loot/persistence/recovery/shared-warehouse gates passed (`runner_results_adhoc_20260913_012010_996_3880.json`); real save/persistence/batch transaction tests also passed.
- Capacity generator: `py -3.12 tools/dpv2_ground_capacity.py --write` then `--check`. Updates only two capacity numbers to 15 and three baseline hash bindings. The active V5.0.5 builder and runtime activation builder consume the same constant. Historical balance calibration remains frozen; no re-solving of probabilities or priorities.

All intermediate measurements above are identified patch-tree evidence, not final clean-HEAD/APK evidence. Remaining requested work continues in this same task.
