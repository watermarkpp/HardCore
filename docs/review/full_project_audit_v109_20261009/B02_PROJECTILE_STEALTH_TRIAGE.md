# B02-002 / B02-004 定向分流审查

后续处置：以下正文保留修改前的只读分诊。B02-004 已按既定真实脱战合同修复并发布，见 B02_PLAYER_NATIVE_LEDGER.md；B02-002 已实施首次物理接触选取并完成必要专项，见 B02_PROJECTILE_NATIVE_LEDGER.md。原始失败和分阶段证据保留，正文的 OPEN/NOT_RUN 不代表后续结果。没有改变提交即破隐或装备吸血合同。

状态：`NOT_RUN`。本文件是固定源码上的只读分流，不修改生产、测试或原生文件，也没有运行 Godot/native。

审查基线：`ed2d87121de80c84caaa3f096c3a5acb71d4946f`。外部审计原始证据保留在 `docs/review/full_project_audit_v109_20261009/external/B02/`。

## B02-002：投射物首次物理接触

当前链条与外部报告一致：

`SkillProjectile._physics_process`（`scripts/skill_projectile.gd:374-492`）固定本 physics segment 的起点/终点和 swept footprint（399-418），通过 `RuntimeCombatSpatialIndex.query_segment_candidates` 查询候选（448-455），按 `stable_combat_order` 排序后逐个做 `_swept_segment_intersects_enemy_footprint`（461-480），第一个精确相交者立即 `_apply_hit`、发 impact audio 并 `queue_free`（481-484）。

这保证了“候选集稳定、一次命中、同一段运动可躲避”，但没有计算候选在 segment 上的最早接触参数。`_swept_segment_intersects_enemy_footprint`（534-574）只返回 `bool`；`RuntimeCombatSpatialIndex` 的排序实现（`scripts/runtime_combat_spatial_index.gd:642-647`）只按 stable order。因而在一条 physics segment 同时穿过近、远两个合法怪物时，若远端 stable order 较小，远端可能先受伤。这是一个有明确代码证据的 **source-derived ordering risk**，但是否必须修改仍取决于正式合同是否是“首个物理接触优先”。

最小修复方向（仅在首接触合同确认后）：保持同一 frozen segment、候选查询、资格短路、一次 `_apply_hit` 和 stable-order tie-break；为同一精确 footprint 增加返回最早 segment 参数 `t` 的几何入口，选择最小 `t`，只在 `t` 相等时按 stable order。不要扩大 broadphase，不增加第二碰撞权威，也不要把 projectile 固定在目标或禁用移动来“证明”命中。需要的最小验证是：近/远共线且交换出生/stable order、切线接触、相等接触参数、实际移动躲避；当前为 `NOT_RUN`。

## B02-004：装备隐身被战斗打断后的换装

当前隐身状态有两个明确所有者：

- `Player.break_stealth`（`scripts/player.gd:1872-1880`）设置 `_stealth_break_override=true`、清空临时 `stealth_time`，不删除装备效果。
- `GameRoot._recover_equipment_stealth_if_out_of_combat`（`scripts/game_root.gd:8410-8415`）只有在 `_player_combat_enemy_ids` 为空、玩家未死亡、没有 pending combat action、没有 attack action timer 时，才调用 `recover_equipment_stealth_after_combat_exit`（`player.gd:1883-1895`）。敌人目标变化由 `game_root.gd:8399-8408` 维护该集合。

外部报告指出的风险真实存在于 `_apply_profile_stats`（`scripts/player.gd:2026-2034`）：当装备隐身活动状态改变时，它无条件执行 `_stealth_break_override = false`（2031）。因此正式复现链为：

`Player.break_stealth` → `_stealth_break_override=true` → 战斗仍由 `_player_combat_enemy_ids` 标记 → PlayerState profile/equipment change → `_apply_profile_stats` 发现 `_equipment_stealth_active` 改变并清 override → `is_stealthed`（`player.gd:2000-2004`）重新依赖装备效果，可能在真实脱战前恢复。

这与用户指定的“装备隐身在穿戴时生效；战斗打断后只在真正脱战恢复”冲突。最小单所有者修复是：在 `_apply_profile_stats` 更新装备活动标志时，不清除一个已经由战斗设置的 `_stealth_break_override`；仅在没有活动战斗、或由现有唯一的 `recover_equipment_stealth_after_combat_exit` 处理的合法边界清除。不能新增第二个 combat/stealth authority，也不能通过重新写 `stealth_time` 伪造恢复。

必须保留的边界：

1. 战斗中换下再穿上、同统计 profile 改动：仍不可见，直到 `_player_combat_enemy_ids` 真正清空且现有退出门禁允许恢复。
2. 和平状态首次穿戴、新角色、复活后合法装备状态：仍可按现有 `PlayerState.has_special_effect("stealth")` 生效。
3. 召唤物造成或保持战斗时，按现有 enemy-target 集合合同判断，不凭玩家可见性重置。
4. 玩家主动提交攻击/技能导致的 `break_stealth` 保持原语义。`player.gd:489-491` 和 `599-616` 都有明确注释：用户选择的是“submission breaks stealth uniformly”，即使后续世界 preflight 拒绝，也不能在本分流中改成“只成功 cast 才破隐”。

## 相关但不扩大本任务的结论

生命偷取不是本次两个 finding 的修复项。现有 B02 资料显示 legacy equipment lifesteal 以 incoming/raw resolved damage 计算，而 feature lane 使用 `actual_loss`；用户已明确装备生命偷取按 incoming damage 保持。后续若改动，只能保留现有装备 lane 的 incoming-damage 语义，并单独验证一次命中、治疗上限和 overkill，不能把它改成 actual HP delta，也不能借本报告合并两条权威。

## 结论与证据缺口

- **B02-002：OPEN / 需要合同确认与专项运行验证。** 代码确实按 stable order 而不是最早 segment 接触选择目标；只有正式规则确认“首个物理接触”后才应施工。
- **B02-004：OPEN / source-derived lifecycle risk。** `_apply_profile_stats` 无条件清 override 与“真正脱战恢复”边界直接冲突；最小修复应留在该现有 profile 更新点，并继续由 GameRoot 的唯一脱战门禁恢复。需要固定源码实际换装、持续 live target、脱战和再穿戴专项验证。
- 两条均未运行，不能报告为 B02 PASS；B02-005 的提交即破隐选择也不应被这两个 finding 顺手改写。

## B02-002 后续授权候选（仍未运行）

在本报告结论基础上，已按首接触合同实施最小候选：`scripts/skill_projectile.gd` 继续使用原候选查询、原 `_swept_segment_intersects_enemy_footprint` 资格门和同一 frozen segment，只对通过资格门的候选计算解析 segment 参数，取最小参数；等参数保持原 stable-order 查询顺序。没有增加 group scan、第二 query、地图加载或新的 damage authority。新增纯参数边界及真实 `EnemyActor`/`RuntimeCombatSpatialIndex` fixture 位于 `tests/framework/projectile_first_contact_order_20261009_test.gd/.tscn`，覆盖近/远逆 stable order、重合等参数、切线、初始重叠、零长度及实际移动躲避。当前仍为 `NOT_RUN`，需 root 后续冻结后执行专项 native/headless 验证。
