# DPV2 V5.0.5 Review Candidate

This is a review candidate, not an integration merge certificate.

- MIGRATION_BASE_SHA: `342891ab884150c0e81084c932df8205484e6388`
- ORIGINAL_GAMEPLAY_BASE_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- CODE_SHA: `1ee2b0381cd72c1872ed7de7823d9880dd62adc2`
- REVIEW_BRANCH: `codex/dpv2-glm52-flash-v5-0-3-20260908`

## Source migration

- source status: `{"EXPLICIT_NON_LOOT":9,"FULL_21CQ_VERIFIED":141,"LEGACY_PRESERVED_EXTERNAL_EMPTY":2,"PROJECT_EXTENSION":1,"RUNTIME_DISABLED":3}`
- compiled slots: `7611`
- UID reused: `5889`
- added slots: `1463`
- removed legacy-only slots: `661`

## Balance

- verified book monsters: `42`
- book rules: `{"BOOK_ELITE_BOSS":325,"BOOK_ORDINARY":149}`
- Boss K status: `NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET`
- Boss K: `1`
- Woma final no-equipment: `2.13638839330004E-07`
- four-boss no-equipment before/after:
  - ID76 (沃玛教主): before `2.1363883933000385E-07` -> after `2.1363883933000385E-07`
  - ID198: before `0.6674026326662957` -> after `0.6674026326662957`
  - ID199: before `0.10577489871304631` -> after `0.10577489871304631`
  - ID225: before `0.2341400898941459` -> after `0.2341400898941459`
- armor 1/60 proofs: `6`

## Final verification (V5.0.5e, candidate at CODE_SHA)

- Godot V5 specialist: PASS (`test_dpv2_repair_v5`, passed=1 failed=0 engine_log_errors=0)
- Critical suite: passed=316 failed=2 engine_log_errors=3
  - complete_client_resource_catalog_test — FAIL on candidate AND on ffcdc76b BASE (A/B: baseline/environment; generated resource manifest missing on both)
  - combat_unit_source_priority_test — FAIL on candidate AND on ffcdc76b BASE (A/B: baseline/environment; identical assertion failure on both)
- skill_runtime_single_result_contract_test RID gate: candidate 3/3 PASS, ffcdc76b BASE 3/3 PASS — no repeatable candidate-only RID failure
- In the designated run above, the only two failures were A/B-classified as
  baseline/environment on the same machine (both also FAIL on ffcdc76b BASE).
  This is a per-run statement, not a global claim: additional intermittent
  RID-class failures in other full-suite runs have an OPEN root-cause
  attribution (see the Full-suite stability section below).

## Full-suite stability (V5.0.5f re-run record)

The official final Critical run (runner_results_critical_20260908_143024_221_8864.json)
is `passed=316 failed=2`, captured in `critical_runner.log` as a verbatim transcript
reconstructed from that run's own per-test records. During V5.0.5f docs closure the
full suite was re-run on the same clean committed candidate (CODE_SHA `1ee2b038`),
same machine / Godot / runner command:

- re-run #1: `passed=314 failed=4` — `skill_production_single_commit_test` and
  `map_runtime_release_gate_test` failed with engine-level headless dummy-renderer
  RID errors (`Attempting to initialize the wrong RID`, `texture_2d_initialize`,
  `rid_owner.h`/`texture_storage.h`); the other 2 failures were the known
  baseline/environment tests.
- re-run #2: `passed=313 failed=5` — same RID error class hit a different set of
  texture-loading tests (`enemy_snapshot_v2_production_test`,
  `map_transition_missing_arrival_test`, `unbuilt_planned_map_not_playable_test`);
  plus the same 2 baseline/environment failures.

Classification of the RID-noise failures:
- candidate standalone retry: 2/2 + 2/2 PASS (`skill_production_single_commit_test`,
  `map_runtime_release_gate_test`);
- ffcdc76b BASE standalone: both PASS;
- all such tests PASSED in the official 143024 run on the same candidate code.

Evidence-bounded stability statement (per author post-merge review F03):
- What the records SUPPORT: the RID-class errors are intermittent on this
  machine/Godot/runner (three full-suite runs on the SAME candidate commit gave
  `316/2`, `314/4`, `313/5` with 2-3 different texture-loading tests each);
  they are not a repeatable deterministic assertion regression; the Godot
  specialist and one full suite passed the major checks.
- What the records do NOT prove: that the root cause is entirely engine-side
  and unrelated to the candidate changes; that the candidate adds no
  race/load-related failure mode; that every unfavorable run may be replaced by
  the best run.
- Therefore this candidate carries an OPEN item: intermittent stability risk
  with root-cause attribution INCOMPLETE. A full BASE-vs-candidate comparison at
  the same run scale/order, or direct root-cause evidence, is required before
  claiming the RID errors are proven engine-only. "BASE standalone PASS" does not
  substitute for "BASE under the same full-suite load".
- All full-suite run records are preserved verbatim (unfavorable runs are NOT
  overwritten): `docs/drop/v5/test_logs/runner_results_critical_20260908_031303_847_12564.json`,
  `..._143024_221_8864.json` (official 316/2),
  `..._153322_961_24628.json` (314/4), `..._162805_045_24652.json` (313/5).
  `critical_runner.log` records the official 316/2 transcript with a provenance
  header auditable against `..._143024_221_8864.json`.

## Post-merge review closure (author post-merge independent review F01-F04)

- F01 — stale simulation evidence: CLOSED. `docs/drop/v5/simulation.json` was
  re-run against the current committed V505 data (ID76=108 slots, ID141 book
  slots 5/141 + 1/28; previously the same blob as the pre-migration candidate).
  Full close-condition acceptance: `docs/drop/v5/V505_ACCEPTANCE_RUN.json`
  (schema `hardcore.dpv2.v505.acceptance_run.v2`), bound to
  `data_commit=275eef8b9455c7f3ef63daaf59dfff3c06e26069`, to the SHA256 of every
  input file (effective/classification/authority/baseline/policy/catalog), and
  to `tool_sha256` of the acceptance tool itself (tool and data commits are
  recorded separately). Coverage is a HARD completeness condition (R03): the
  expected drop-enabled identity set (144) and per-identity slot UID sets are
  taken from the independent baseline and must EQUAL the effective ledger
  (missing/extra identity, missing/duplicate slot UID, NO_AUTHORITY_ROW,
  origin-count drift 7352/190/69, and per-UID item/base mirror all fail);
  source_status distribution 141/2/1 recorded. High-risk monsters (bosses
  76/198/199/225, new clothes 235-240, all book monsters, legacy 75/123):
  per-slot hits/selected/discarded + always_retained. Per-slot invariants for
  ALL slots: 0<=selected<=hits<=trials, hits==selected+discarded,
  always_retained -> discarded==0. Book per-kill distributions are per-row-rule
  (R01): total books (policy book_ids), BOOK_ELITE_BOSS books by the row's own
  rule, and explicit-high books (policy explicit_high_book_ids) as a separate
  identity set; a monster with zero BOOK_ELITE_BOSS slots must have that
  distribution exactly {0: trials}. New clothes (R02): the six targets are
  locked from policy.armor_targets by (monster_id, source_item_id) — unique,
  UID-bound, rule ARMOR_BASE_1_OVER_60, actual draw Fraction EXACTLY 1/60,
  then the retention boundary is ENFORCED as a failure condition:
  always_retained must be True, selected==hits, discarded==0
  (`ARMOR_TARGET_NOT_ALWAYS_RETAINED` / `ARMOR_TARGET_RETENTION_LOSS`),
  followed by the 6-sigma Monte-Carlo stage (sigma 0.08-1.15);
  missing/duplicate/wrong-item/wrong-probability/extra-target/retention-loss
  all fail. Female-to-male clothing output mapping (author ruling 2026-09-09):
  the draw stays on the source identity at 1/60 and the output identity is
  mapped once (`loot_runtime_service.gd
  FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID`: 238:141→140 天魔神甲,
  239:145→144 天尊道袍, 240:143→142 法神披风; the 235/236/237 pairs are
  unchanged identities). The tool validates the exact
  (source_item_id -> output_item_id) pairs against the approved table
  (`armor_output_mapping`); unexpected pairs or a wrong pair count FAIL — the
  mapping is not double-draw and does not double any boss probability.
  top_slots (R04) are sorted numerically by the draw Fraction actually used in
  the simulation, with effective_probability reported separately and labelled.
  Result: **failures=0**. The tool ships with negative tests
  (`tools/test_dpv2_repair_v505_acceptance.py`, 13 cases: correct fixture
  passes; wrong cloth probability 1/61, wrong cloth item id, missing target,
  duplicate target, missing monster, missing slot, BOOK-subclass pollution,
  fraction sorting, 9 higher-priority competitors, 9 same-priority
  competitors, 9 lower-priority competitors (positive), and unexpected
  female-to-male output mapping are all exercised — malformed inputs are
  rejected). The old simulation.json `failures=[]` is no longer the
  acceptance basis; this run is.
- F02 — reward-caliber balance data: PRODUCED (no balance change). The
  acceptance run records per-monster reward profiles (slots_by_reward_kind,
  equipment/book/gold slot counts, top slots, per-slot probabilities and
  drawn-vs-retained discard). Selected readings: ID76 沃玛教主 any-equipment
  100%, any-book 22.2% (7 BOOK_ELITE_BOSS slots); ID198 恶灵尸王 any-equipment
  33.5% (66.5% no-equipment, consistent with balance.json) BUT any-book 34.4%
  across 28 BOOK_ELITE_BOSS slots — book value must be included when judging
  its reward; ID89 尸王 any-book 99.5% (29 book slots, up to 9 books/kill);
  ID141 any-book 10.3% (冰咆哮 5/141 + 2× 1/28). K remains 1; old K=1.761644 is
  NOT restored. Any individual target adjustment (e.g. 198) requires a separate
  author balance ruling.
- F03 — stability attribution: REWRITTEN with evidence-bounded phrasing (see
  above). All four full-suite run records preserved verbatim in
  `docs/drop/v5/test_logs/`. Open item: intermittent stability risk,
  root-cause attribution incomplete.
- F04 — Android/real-drop boundary: OPEN (recorded). APK build, device test,
  world item node creation performance, duplicate-death award test, and
  Android drop spawn/pickup smoke are NOT_RUN / NOT_CONNECTED
  (`EXECUTION_STATUS.json`). Python RNG/selection acceptance does not replace
  ground-node spawn/pickup/save/device evidence. 1/60 data and selector
  retention proofs are separate from ground generation chain correctness.

## Hotfix chain applied on top of migration

- V5.0.5b.1: runtime classification closure (canonical-authority 233 + drop subset 231)
- V5.0.5c: JSON numeric-array integer-aware membership (book/boss contract IDs)
- V5.0.5d: post-loop ceiling_count closure constant (2203 -> 1435)
- V5.0.5e: Critical test contract migration (ID76 source-driven 108 rows, ID89 80 rows)

## SHA semantics

A Git commit cannot contain its own final SHA without changing that SHA. The
actual FINAL_SHA and independently verified REMOTE_HEAD_SHA are recorded in the
post-push receipt (`V505_PUSH_RECEIPT.json`) outside the repository, after the
docs-only closure commit (V5.0.5f). They must be equal, verified via
`git ls-remote origin refs/heads/codex/dpv2-glm52-flash-v5-0-3-20260908`.
