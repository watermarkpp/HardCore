# B03 本地怪物特殊行为先行审查

状态：`NOT_RUN`（只读静态审查，未运行 Godot、原生或设备验证）。

审查基线：固定提交 `ed2d87121de80c84caaa3f096c3a5acb71d4946f`。本报告以当前工作树中仍可追溯到该基线的正式登记和调用函数作定位；B01 的资源加载变更不纳入结论。证据入口为 `assets/data/boss_service_rules.json`、`assets/data/monster_behavior_profiles.json`、`scripts/enemy.gd`、`scripts/game_root.gd`，以及 source176 的 `scripts/monster_source176/` 合同文件。

## 覆盖范围

`monster_behavior_profiles.json` 的特殊投递族覆盖 33 个稳定 ID（22 个 profile family）：

| 稳定 ID | 登记族 | 正式几何/效果 | 时钟结论 |
|---|---|---|---|
| 70 | `flame_wooma` | `special_melee`，chebyshev square，`monster.flame_wooma.magic_melee.v1` | 攻击接触、命中和 magic damage 必须留在现有攻击时钟；只可把无目标/远距条件观察放入已有 owner 窗口。 |
| 124 | `touch_dragon` | `area_magic`，6 GU、轴对齐 Chebyshev square、无 LOS；同图可见 combat targets；0.6s hit delay，25% status，poison/control | 现有 `_update_area_magic_delivery`（`scripts/enemy.gd:6493-6532`）负责一次性冻结 footprint、目标集和结算；不能用 300ms 轮询替代 attack cycle 或延迟伤害/status。 |
| 50, 42, 145, 186, 150, 151, 152, 206, 207, 62, 174 | axe/archer/thorn `physical_projectile` | `monster.physical_arrow.v1`，正式投射路径 | 发射、弹道目标快照、命中和伤害必须保持投射/攻击时钟；仅候选发现可受现有目标观察节拍约束。 |
| 183 | `explosion_spider` | `self_detonation`，相邻地图格 | 自爆触发、目标快照和 damage 必须即时且 exactly-once；不能以 300ms 扫描替代死亡/接触触发。 |
| 220, 222, 224 | cow/electronic scorpion `target_magic` | `monster.target_lightning.v1`，Chebyshev square | cast eligibility、target snapshot、damage/status 必须在攻击/法术时钟；不得因观察窗错过进入条件。 |
| 18, 103, 104, 185, 146 | `directional_spit_map` | 5x5 source spit map；`TargetInSpitRange`/`SpitMap` 为正式几何 | 方向、地图格穿越、命中和效果保持攻击时钟；远距候选读取才可能降频。 |
| 46, 60, 128, 168 | `gas_adjacent` | Chebyshev square；gas attack，moth 另有 hidden reveal | gas 命中、揭隐、控制/伤害不可延迟；邻接候选可复用已有 target observation。 |
| 79 | `line_magic` | directional line cells，9-cell `MagPassThroughMagic` | 线段构建、穿透、结算保持法术时钟；不能缓存跨地图/生命代次的几何。 |
| 76, 77, 235, 236, 239, 160 | `mixed_target_tile` | Chebyshev square，mixed physical/magic target tile | 目标格、物理/魔法比例和 hit timing 必须立即；Boss 阶段维护另见下表。 |
| 194 | `guard_direct_projectile` | Manhattan diamond，guard projectile | 守卫发射与命中必须即时；只可节流未到发射条件的观察。 |

上表由 `monster_behavior_profiles.json` 的 `profileByMonsterId` 精确展开；名称不是运行时身份。`scripts/enemy.gd` 的 `_uses_*_delivery`、`_update_area_magic_delivery`、special-cell release 和 `monster_special_delivery_requested` 是实际消费者。未发现 source176 另有一套可替代这些投递的第二权威。

## Boss 状态机和维护边界

`assets/data/boss_service_rules.json` 另登记 56、89、76、124、160 五个 Boss 运行规则。56（骷髅精灵）和 89（尸王）明确 `specialSkill.enabled=false`，无专属状态机；应保留各自 attack/target-search timing，不把标准 Boss 误列为特殊行为。

| ID | 特殊行为及参数 | 正式调用链 | 300ms 可做的部分 | 必须即时/原时钟的部分 |
|---|---|---|---|---|
| 76 | `healthStageRage`：7 stages、8s、速度×1.8、attack interval 0.5s；`surroundedRelocation`：10s、5 blocking neighbors、4-cell radius | 受击进入 `_apply_damage_core`，在 `scripts/enemy.gd:7622-7625` 调 `_apply_health_stage_rage_on_damage`（8093-8109）；世界维护在 `scripts/game_root.gd:6396-6414`，发出 `relocation_requested` 后由 6462-6477 落点 | 10s 邻居数量/阻塞条件扫描可按正式 owner deadline 观察，前提是地图代次、生命和目标仍有效；7 段阶段的“是否达到阈值”可在既有受击边界或合法 action/search 边界检查 | rage 是实际 HP 提交后的反应，速度和 0.5s attack interval 必须在该次受击后立即生效；relocation 一旦获准必须立即走合法落点/碰撞验证，不能让移动或地图迁移等待下一次扫描。 |
| 124 | `burrowAmbush`：stationary、emergeRange 128、出土满血；同时 `area_magic` | `scripts/enemy.gd:3266-3286` 负责距离、出土、满血和可见性；普通攻击路径 3348 起转入 area magic | 出土前的远距条件可由已有目标观察节拍维护 | 到达范围后的 `burrowed=false`、满血、可见性和随后攻击必须同一合法 physics/attack 路径；area magic 不能降频。 |
| 160 | `stoneWake`：64 GU；`healthStageSummon`：5 stages、4-7、maxActive15，子 ID 156/153/150/128 | dormant wake 在 `scripts/enemy.gd:3320-3339`；无目标 stage service 在 8375-8391，due 判定 8112-8118，召唤阶段 8641-8647 → `_apply_health_stage_mechanics` 8065-8090 → `summon_requested`；GameRoot 5420 接线，6449-6458 做 map/life/transition gate 后入正式 summon queue | `_boss_stage_search_due` 的 1s/8s 观察、无目标 health-stage 扫描可用 300ms owner deadline；stone wake 的远距检查也可低频观察 | crossing 后 `_boss_health_stage` 只能消费一次；随机 child IDs、summon queue admission、maxActive、map generation/life 校验和实际 spawn 不能延迟或重复。目标进入 wake range 后应保持原 physics 行为。 |

`_apply_health_stage_mechanics` 的阶段消费只发生在 formal target-search boundary（源码 8641-8647 注释也明确了这一点），damage callback 不直接召唤。这个顺序是重要合同：不能为了降频把 damage callback 改成另一个召唤权威。

## 已核对的取消、死亡和地图边界

- 召唤 warning 在 `scripts/enemy.gd:7147-7179` 先检查 dying/death/current HP、control/charm/dormant/burrow，并在释放前校验生命代次和 target；其 `summon_requested` 由 GameRoot 5420 接收，6449-6458 再校验对象、HP、map、zone generation、transition。该链覆盖了死亡、控制、地图切换和 exactly-once serial，但尚缺本轮 B03 的自然跨帧专项证据。
- 160 阶段召唤使用 `_boss_health_stage -= 1` 后生成随机子 ID；若 spawn service 拒绝，阶段不会在下次重复同一 stage。这是应保留的退役边界，不应用 300ms 轮询重放。
- 76 relocation 在 GameRoot 每帧只维护一个 10s remaining counter，但邻居枚举和投影发生在 due 点；对象无效、非 Boss、地图代次变化由 6399-6406、6462-6476 过滤。落点失败时保持原位，不能把失败当成功推进状态。
- 124 burrow 出土前实际仍是 `dormant`/`_burrowed`，受击唤醒路径 7531-7546 只在正伤害、有效 attacker、非死亡时解除 dormant；该路径和距离出土路径不是同一触发，不能合并为单个 300ms target scan。
- 特殊伤害均最终经过正式 `take_damage`/状态方法；任何节流方案必须保留受击、死亡、safe-zone、目标生命代次和 map generation 的现有短路顺序。

## 静态风险和证据缺口

1. **证据缺口（不判定为生产 bug）**：76 的两个机制来源置信度为 C（`suprcode_crystal WoomaTaurus.cs`），而 124/160 的来源置信度为 A。需要后续 B03 专项把 76 的 stage threshold、relocation failed/accepted 和攻击间隔变化做固定输入自然运行验证；本报告没有替换 C 级资料。
2. **需重点回归的边界**：`_update_boss_world_mechanics` 在 `game_root.gd:6396-6414` 是独立 Boss cache sweep；Boss owner-window 在 `enemy.gd:8375-8391`、`8400-8426` 又有 stage-search 服务。二者职责不同：前者只处理 76 relocation，后者只处理 160 health-stage search。若后续合并为一个“Boss 300ms”服务，必须证明不会重复读/重复推进两个时钟。
3. **几何风险（待专项验证）**：124 area magic 使用独立 `_create_area_magic_footprint_snapshot` 和 `_area_magic_targets`（6493-6532、6535 起），而普通 melee 的 `_hc_tick_melee` 在 10106 起拥有另一套接触几何。不能用普通 target acquisition 的范围或 owner300 deadline 替换 area magic 的 6-GU square。
4. **行为选择与事实分开**：将 160 的无目标 stage search、76 的 10s surrounded check、124 的远距 burrow 条件放进 300ms 观察窗是性能产品选择；攻击、命中、HP、召唤/迁移提交仍须原时钟，这是由当前调用链和状态所有权推导出的安全边界，不是已完成 B03 性能证明。
5. **尚未覆盖**：本次没有运行 50/62/70/79/146/150-152/160/168/174/183/194/206/207/220/222/224 等特殊投递的完整自然场景，也没有证明玩家隐身、safe zone、地图切换、死亡中 warning、召唤上限和特殊 projectile 的跨帧取消。状态统一为 `NOT_RUN`，不能写作 B03 PASS。

## 最小后续专项

先用固定 seed 分别覆盖 76 rage/relocation、124 burrow+area magic、160 wake+每个 health stage，再覆盖代表性投递族 70/124/183/220/224/79/194。每个场景同时记录目标几何、攻击/效果提交、HP/状态、生命代次、map generation、取消原因和队列完成量；对 300ms 试验只比较非急观察读取，不能减少特殊攻击负载，也不能以延迟结算制造性能结果。
