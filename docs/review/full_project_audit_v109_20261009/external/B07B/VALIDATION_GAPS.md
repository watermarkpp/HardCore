# B07-B 源码/原生证据未闭合职责

fixed_source_sha: b09ac5c2c41517ed516f11b91d09e435813465f2

## 状态区分
- STATIC_FIXED_OBJECT: PASS for 3,255/3,279 manifest files; 24 local retired grid files absent; 34 new test .gd/.tscn added to review inventory.
- Raw historical evidence: 164/164 sha256 and byte length PASS; stage50/51/52 original native FAIL/positive dispositions retained; stage50 custom checks MISSING not reconstructible.
- Godot/Android/109 build/current-phone: NOT_RUN. 8,223 function entries indexed and 41 targeted static-reviewed; complete semantic coverage MISSING.

## 逐职责具体未审入口
- tools/run_godot_tests.ps1 (1,756 lines): Windows Get-WorktreeGodotProcesses/Get-NewGodotProcesses/Stop-NewGodotProcesses/Stop-TestProcessTree cross-tree ownership; Linux subreaper and pipe-drain; dynamic top-level suite matrix and negative fixture admission; stdout/stderr/engine logs allowlisted warning classification; 30/60/90s deadline; appdata/log physical link checks and metadata producer binding. Source found conditional risks, no engine repro.
- tools/test_framework_receipt.ps1 / tests/framework/helpers/check_receipt.gd / tests/framework/helpers/native_producer_gate.gd: static counter/run/scene/producer checks traced, but Windows missing fingerprint and actual native handoff negative cannot be declared PASS.
- tests/hc_monster_ai/test_support.gd: check/finish output truncation confirmed; per-attempt immutable receipt capture needs isolated validation; 50 itemized list remains MISSING, cannot rerun a different source and call it old evidence.
- tests/helpers/formal_initial_ready.gd: four-part READY predicate traced, not 60-second startup SLA acceptance. tests/helpers/formal_world_skill_fixture.gd publish_targets/prepare/wait partially traced; map publication cancellation, target set, scene cleanup and resource async branches still need full semantic review.
- tests/helpers/map_runtime_transaction_test_fixtures.gd reset/write/read seams targeted; make_document, mutate_and_bake, make_entry and failure path recovery not fully traced; B06 headless != process kill durability.
- tests/helpers/loot_runtime_pre_slice_20261009.gd (842 lines/29 funcs): differential old roll/select/shuffle/overflow stages must be separately compared against authoritative production UserLootSheet/GameData, not used to create fallback.
- tests/source176_r3/helpers/cadence_reference_r2.gd (465 lines/19 funcs): frozen historical oracle, evaluate/grant/reset/postpone branches need comparison scope proof. Do not restore obsolete grid experiments or 300ms attack delay.
- tests/hc_monster_ai/m30_sampling_copy.gd (1,066 lines/75 funcs): fixture samples and results are not true current 30-monster CPU performance evidence; time windows, loads and output receipts not reviewed function-by-function.
- tests/wall_atomic_foreground_occlusion_runtime_test.gd (1,349 lines/31 funcs), tests/equipment_helmet_mapping_editor_test.gd (1,307/10), tests/ui_layout_calibration_workbench.gd (1,256/45), tests/framework/natural_sustained_chain_test.gd (1,101/30): entire remaining functions/fixture scene dependencies and cleanup still unreviewed.
- tools/tests/test_suite_registration.ps1 (1,212 top-level lines): static expected membership content is not an executed suite; each dynamic member/duplicate/retired registration still must be confirmed.
- tests/enemy_mass_death_batch_pipeline_test.gd: overrides initial map bootstrap and ground placement; positive real roll+RNG vs queue settle proved only in scoped ledger, full world placement missing.
- tests/monster_magic_reaction_continuation_test.gd: delayed policy diagnostic on explicit subcase restored; timing and high HP are fixture prerequisites not dropped monster load. tests/hc_monster_ai/combat_epoch_delivery_test.gd: deterministic E03 hit seed, not forged damage/evasion. Other 11 fixtures must not be amalgamated across stage50/51/52.
- tests/diag_activation_probe.tscn, tests/diag_bounded_probe.tscn, tests/r2_measure/qa_latency_driver.tscn: missing script ext_resources; their dormant status must be resolved before formally invoking them.
- 1,629 scene resources, 1,506 GDScript files and 69 Python test paths: individual runtime entry, real owner, assertions, data/world/map/epoch, fake vs production, teardown and native proof not all semantically completed. Per-path and per-function gap entries are enumerated in COVERAGE.json.

## Verification policy
Do not substitute original 8 stage50 passes for newly changed scopes, or overwrite negative stage50/51 evidence. Java helper/probe same byte identity can reuse original native preflight/restore evidence; actual 109 export needs its own current build checks in B08.
6/9/12 LOS, 300ms optional planning, attack/AOE/drop unique authority, oil 5x/JP 3x and bat127 pending user selection remain unchanged.
