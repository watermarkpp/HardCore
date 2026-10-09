# B02 Projectile 边界失败静态分诊

状态：**PASS（静态处置已完成；运行状态按各 receipt 分开记录）**。本轮没有重新运行 Godot/native；只复用 direct20/22/23 与 related21 的原始 receipt，并在 direct22 之后做了三个 fixture 的最小输入修正。projectile 生产源 `scripts/skill_projectile.gd`（首接触 source SHA `CA91A0545BBF80A9EBA2EE617DEE79010B6CBDABBAA3AD24B7468052D51F88EF`）未再修改。

审查对象为 `4e77c619249450b7c33e833c2bb3531f3f120bfc` review 基线对应的当前测试形状，以及当前 `scripts/runtime_combat_spatial_index.gd` 与 `scripts/skill_projectile.gd` 的正式坐标合同。related21 的三个失败不能归因于生产回归；三个 fixture 都存在可达的坐标/桶边界失配，随后已逐项修正并由 direct22/direct23 覆盖验证。

## 正式合同

`RuntimeCombatSpatialIndex` 明确使用绝对 ground GU，默认 `BUCKET_SIZE_GU = 1.0`（`scripts/runtime_combat_spatial_index.gd:18-23`，`_bucket_key` 在约 `679-683`）。`register` 保存 map、bucket、最大 footprint 和可选 live position provider；`update_actor` 先写 live position，只有 bucket 改变才迁移并增加 `index_bucket_change_count`（约 `77-157`）。

`SkillProjectile._physics_process` 每个物理步只查询当前 ground-GU segment 的 broadphase（`scripts/skill_projectile.gd:449` 起）；segment 长度由 `speed_gu_per_sec * delta` 决定，查询 envelope 只扩展 projectile radius、固定 margin 和注册 footprint。它不会为了测试“提前”扫描整个 projectile 最大射程，也不会把远处目标算作当前步 candidate。

## 三个失败的实际原因

### `projectile_spatial_index_lifecycle_test.gd`

测试从 `(0,0)` 注册后调用 `update_actor(1, Vector2(1.5, 0.5))`，却断言 same-bucket。当前默认 1-GU bucket 下，初始 bucket 为 `(0,0)`，新位置 bucket 为 `(1,0)`，因此迁移和 `index_bucket_change_count == 1` 是正式实现的正确结果；该断言与测试输入矛盾。若要覆盖 same-bucket，应选同一 bucket 内的有限移动，例如 x/y 均保持在 `[0,1)`，并另保留现有 `(6,6)` cross-bucket 断言。

其余 lifecycle 语义与实现相符：`queue_free` 后 `_exit_tree` unregister；树外 ghost 通过下一次 query 的 WeakRef stale cleanup 清除；`clear_map(2)` 清除 map partition。没有静态证据表明同 bucket 会错误 re-home。

### `projectile_snapshot_single_build_per_step_test.gd`

测试在 x=`2.0 + i*0.4` 放置 16 个目标，projectile 从 x=`0` 以 8 GU/s 前进，并断言 `candidate_count >= steps`。前若干 physics segment 仍远离第一个目标，正式 broadphase 必然允许零 candidate；projectile 到达近区后还可能在首次命中时 queue_free，实际执行步数也不等于 40。`snapshot_build_count == steps`、`query_count == steps` 是有意义合同；“每个 step 都有 candidate”不是当前场景几何能证明的合同。

这不是 snapshot 多建或 query 漏掉的证据。若要保持“每步都有 candidate”负载，目标必须覆盖 projectile 的整个实际 segment 时间窗；否则应改为断言首次进入目标 envelope 后 candidate 非空，并记录 actual candidate count，而不是用 `>= steps` 取代空间合同。

### `projectile_spatial_index_query_before_enemy_tick_test.gd`

测试将敌人放在 x=`2.0`，projectile 速度为 8 GU/s，却只调用一次 `_physics_process(1/60)`, 当前 segment 只有约 `0.133 GU`。即使 enemy 已在 `set_combat_position` 中同步调用 `_spatial_index_update`，本步 broadphase envelope 仍不覆盖 x=2；`exact_test_count >= 1` 因而不成立。该用例实际测试的是“已同步注册但相距约 2 GU 的目标”，不是“query-before-enemy-tick”。

`Enemy.set_combat_position`（`scripts/enemy.gd:3680-3697`）明确把位置写入和 index update 放在同一事务；只要把目标放到本步 segment/footprint 可达范围内，或让 projectile 以正式速度跨过目标，再在 enemy physics tick 前查询，才是在验证该合同。不能通过扩大 index query 到全图来迁就当前输入。

## 运行处置 ledger

原始证据已整理到 `docs/review/full_project_audit_v109_20261009/evidence/B02_projectile/`，完整 byte SHA 清单见 `docs/review/full_project_audit_v109_20261009/evidence/B02_projectile/SHA256_MANIFEST.json`（SHA256 `5D6838A76EB0A6EBAF21597544A019ADA2D6469487BD5AA28C2EE55D61C9A1CC`）。

| 阶段 | 状态 | 范围与解释 |
|---|---|---|
| direct19 | FAIL | 首接触场景解析/早期脚本错误；原始 runner、stderr、stdout 和 native handoff 保留，不能作为生产行为证据。 |
| direct20 | PASS | 同一首接触场景修复后通过；实际 framework receipt `3b4187c1-ee1b-4534-9c74-6d14a1559e7d` 已原样保留。首接触使用当前 projectile footprint gate、连续 swept segment 和稳定 tie order；root 已确认该物理合同。 |
| related21 | FAIL | 12 场景中 9 PASS、3 FAIL；失败是当时三个旧 fixture 的 bucket/segment/body 输入失配，原始 runner 和全部 raw evidence 保留。 |
| direct22 | FAIL | lifecycle、query-before-enemy-tick PASS；snapshot 仍因入树前 `.25` 半径与 canonical body radius 不一致而失败。该原始失败保留。 |
| direct23 | PASS | 修正 canonical body radius 登记及横向间隔后，snapshot 16 敌/40 steps 通过。runner 中另一个 `caster_visual_terminal_failure_contract` FAIL 属于 visual scope，明确排除 projectile 结论。 |

当前可复用的专项结果是 related21 的 9 个旧 PASS，加上 direct22 已通过的 lifecycle/query 两项和 direct23 snapshot 修复 PASS；不能合并为“同一 tree 的 12 场景全 PASS”。首接触与 snapshot/lifecycle/query 的修复测试源 SHA、每阶段 source-content SHA、准确 runner 命令和 raw byte 证据见 manifest；实际执行工具为 `tools/run_godot_tests.ps1`，各阶段均保留 30 秒超时和隔离 runtime_appdata。性能、FPS、Android/device：**NOT_RUN**。

换装隐身 Player 的修复属于独立 ledger，不并入本 projectile 结论。

## 分诊结论

三个 related21 失败已标为 **FIXTURE_CONTRACT_MISMATCH**，保留原始失败证据；实际修正只改变 fixture 坐标和 canonical body radius 登记，使原断言落在正式合同内：same-bucket 使用真实同桶坐标，query-before-tick 将目标放入第一步实际 envelope，snapshot 使用入树后真实 body radius 并保持 16 敌/40 steps/HP 不变。没有降低负载、移除 exact query、改变正式 BUCKET_SIZE 或引入全图 fallback。

本报告没有证明 projectile 生产代码无其他问题；它只证明这三个失败的当前断言不能作为生产回归证据。三个旧失败的 fixture 处置已完成，但 related21 原始 3 FAIL 仍需保留为历史证据；direct22/direct23 的后续 PASS 只覆盖对应修正场景。不得将不同阶段合并成全套 PASS，也不得把 visual negative 失败归入 projectile。
