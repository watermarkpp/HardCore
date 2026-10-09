# HardCore 109 · B03 独立审计（怪物/空间/召唤/Source176）

固定审计源码：`4e77c619249450b7c33e833c2bb3531f3f120bfc`；仓库 `watermarkpp/HardCore`；审阅分支 `codex/v108-runtime-bug-review-20261009`。审计只读，未修改正式源码/测试/配置/资料；Godot/native/APK/Android 均为 NOT_RUN。B01和B02原报告保持原样，主控另行修复的玩家暂停/位置通知/隐身换装/投射物不纳入本SHA。

**裁决：B03_REVIEW_WITH_FINDINGS_AND_EXPLICIT_PARTIAL_SCOPES，不是全项目PASS或109发布PASS。** 清单47路径；固定SHA实际读取45个，2个退役grid源文件不存在（不恢复）；8个较大文件仅审B03入口/状态/取消链，余下其它职责列在COVERAGE。其它模块B04–B07未审。

## 源码可追溯的正式合同

- **冷怪即时入战**：GameRoot._pump_passive_monster_wakeup由移动/召唤变化触发，合法Emitter和目标使用当前地图/代际/投影，处理时必要预算记账，不重新按8候选限流；Enemy.request_passive_target_wakeup在合法范围内直接现有target setter，不跑富追击、寻路或独立攻击。正常/精英/Boss 6/9/12GU的光环规则、无隐身主动触发、怪物身体不能遮挡信号都由现有来源/静态terrain LOS校验。正HP损失走Enemy._acquire_cold_damage_target，与被动光环独立（包括火墙）。
- **普通攻击/追击时序**：Enemy._physics_process_internal每physics推进已接收动作、有效移动/碰撞、受伤/死亡。Source176ActionBoundary与Enemy._hc_try_start批准当前合法普通近战后立即开始提交，不依靠旧ATTACK_START_FRAME_AB限流；300ms错峰只给可延后观察和新追击规划。旧HCDecisionBudget.begin仍有physics-epoch+necessary入口，不能对外宣称整AI绝不超时（见B03-003）。
- **AOE/飞行物**：Enemy._settle_monster_special_cell_release等合法特殊接触、line_magic、body-only area/spike使用提交的冻结位置和target集合，随后的动画不拥有HP；source target_magic也在Enemy实际提交，MonsterTargetMagicEffect仅视觉。真实flying arrow经MonsterRangedProjectileEffect的physics WORLD/target接触才扣血，可因移动躲避。ID194 TArcherGuard源资料声明“instant physical HP, flying arrow only observer”，现源码却误入物理投射物接触结算（B03-001）。
- **HP/死亡/重生唯一权**：Enemy._apply_damage_core/Enemy HP→_mark_death_pending，GameRoot死亡管线持久化/掉落为外部唯一owner；Boss阶段、额外攻击、召唤的Gameplay响应仍在Enemy/ GameRoot；视觉/Source176纯辅助不拥有第二HP。普通重生槽位沿MonsterRespawnPolicy 300/480/900/1800/3600秒。
- **坐标/避障**：RuntimeCombatSpatialIndex按map_id、bucket revision、stable combat order、当前合法身体位置维护粗相；精确真实窄相在Enemy/Projectile。Enemy.set_combat_position和正常物理移动更新索引同事务；TerrainNavigationPolicy的光环LOS只查静态墙/地形不查动态怪物。HCM30路线/neighbor将GU临时转邻接事件，不是第二套格子移动；不恢复retired grid/blocked-negative。
- **召唤物**：SummonActor自有HP/碰撞、已提交攻击、持有的真实Owner与代际；NPC召唤由Enemy.summon_requested→GameRoot→HCM30SummonQueue→Enemy child materialize，一physics最多1 birth，8 probes，上限/重复标识。Owner遥远时召唤物强制形成队形的直接坐标写入缺少正式落点验证（B03-002）。
- **视觉/资源**：MonsterVisual受击表现/动作互斥读取Enemy时间和实际移动；MonsterVisualStreamingCoordinator资源线程/释放是B01已修边界，B03只查其战斗消费者，不重复B01 source owner审计。Source176的33项SkillReactionRegistry是“玩家技能反馈分类”，不是怪物新技能目录。

## ID级完整索引

读取正式`assets/data/runtime/canonical_monster_catalog.json`（Git blob `785c48c7b3c89221530e19dedb29e2c5d2c76fbc`），包含**156个当前runtime_allowed怪物ID**。其中64个ID具有特殊投放/Boss资料/召唤/区域攻击/非常规交互，全部在`SPECIAL_BEHAVIOR_COVERAGE.json`逐ID保存canonical名、classification/source级别、21CQ attack/move间隔、正式delivery/area/summon/poison/Boss mechanics参数、共享代码入口、动画/逻辑时钟、失败/取消边界；剩余92个ID明确映射到普通Enemy共享模板。**64个静态接线索引不等于64只/64个技能已被原生执行**；还包括纯固定宝箱或Boss分类但无独立技能的ID。历史ID71火焰沃玛0标`retired_source_only`不得复活。
- 有专门逻辑/证据的例子：ID76沃玛教主血阶狂暴/被围传送；ID124触龙神潜伏、面积魔伤；ID160祖玛教主石化唤醒/血阶段召唤；ID180赤月恶魔、ID195千年树妖原地范围投放；ID182幻影蜘蛛召唤；ID194恶魔弓箭手视觉投射物与源伤害时序冲突；ID220/222/224牛魔系target_magic；ID226–234宝箱为固定noncombat。来源A/B/C等级如实保留，缺失原生不得冒充现场验证。

## 新发现

| ID | 分类 | 优先级 | 位置及结论 |
|---|---|---|---|
| B03-001 | 源码/正式来源合同冲突 | P1 | Enemy._launch_monster_special_cell_delivery / _emit_monster_special_delivery_descriptor / _on_guard_projectile_contact，**ID194**实时命中错误依赖之后的视觉箭飞行碰撞。需要定向对照，保留真正可闪避的物理箭。 |
| B03-002 | 条件性真实落点风险 | P2 | SummonActor._physics_process直接用owner侧偏队形位置修改global_position，远距回归时可能进入墙体；需固定地图近墙原生复现。 |
| B03-003 | 可延期AI时间口径风险 | P2 | HCDecisionBudget旧physics-epoch necessary入口仍可能在同process多物理补步重发；真实利用频次/手机峰值尚无证据。 |
| B03-004 | 召唤队列拒绝先标已接受的策略争议 | P3 | HCM30SummonQueue.enqueue先写m30_last_queued_release再检查256队列/剩余容量；可能使短暂满额请求无法同serial重试，主控需确定是否允许丢弃。 |

## 必须保护的产品与验收边界

- 不恢复主动搜索/返回出生点、怪物强制格子/退役grid，不用增加帧预算/TTL清理掩盖队列积压。
- 真实physics移动、碰撞、已提交攻击和死亡继续执行；仅可延期追击做300ms和预算管理。
- 只有原本具有真实飞行时间的投射物能靠移动闪避；提交直接法术、近战与一次性AOE不能随移动或视觉取消；火墙逐跳重算当时区域。
- 自定义Boss行为不可只测祖玛，ID表是真实资源资料→入口映射，但B03当前并未执行设备每ID战斗。
- 本批审查源固定；B01资源修复只读使用，不重跑旧套件；B02主控新patch不混入本轮报告。

**主要缺口**：各类特殊投放和召唤实体的正式自然scene测试、AOE发射时冻结且HP once、真实近墙召唤、低FPS physics补步、原始source176版本出处再验证，以及Android GPU/FPS均为NOT_RUN。B04/B05/B06/B07仍待后续审查。
