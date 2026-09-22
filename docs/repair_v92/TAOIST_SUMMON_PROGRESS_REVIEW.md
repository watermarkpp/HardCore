# 道士技能与召唤物成长有界复核

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

日期：2026-09-22，采样至 17:02 +08:00。基线 HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`，当前工作树由主控继续施工。状态：PASS（只读调查与静态计算完成）；Godot 动态验证与 DEVICE TEST：NOT_RUN。本报告只提供证据及主控待裁决项，没有实施玩法变化，也不独立批准验收。

范围为道士 13 个正式技能的计划/消费路径，召唤物成长、攻击、跟随、重召、存档与人物经验对照；仅写本报告。未修改生产、测试、地图、数值源、Git 或存档，未启动 Godot。旧记忆只用于定位，下面结论均重新核对当前源码；旧“宠物不吃 AC/MAC”和“读档后属性不重算”已经有修复，不能重复当成本轮发现。

## 结论

1. **人物已大幅加速，宠物成长仍保留原阈值且只认自己最后一击。** 人物现在按两次四舍五入计算 `round(round(source / 30) × 0.70)`，约为原门槛的 `7/300`；宠物仍按被杀怪物等级加经验。代码确实没有将人物加速同步到宠物，但不能据此直接认定应给宠物乘 `300/7`。
2. 在宠物亲自补刀率 100% 时，部分真实场景宠物满级比人物升一级快得多；主人的火符、绿毒或另一只宠物抢最后一击时，这只宠物成长为零。必须把**升级阈值、补刀归属、旧宠等级上限**分开判断。
3. 两处生产消费者候选与“物理/法术分层”新要求直接相关：精神力战法未找到正式物理命中消费者；骷髅/神兽攻击都直接传原始 DC 到 EnemyActor 扣血，未计算目标 AC/MAC。已有描述符测试及宠物入伤测试不覆盖这两项。
4. 活宠出生时的技能 rank、升级上限、owner level 会冻结；提高技能/人物等级后重召、跨图、读档均保留旧值。这符合现有“重召不替换活宠、状态完全保持”的实现与测试，但会制造“当前技能 3 级，旧宠只能升到 3 级”的确定情形，需主控按用户最新要求决定是否调整合同。
5. 未找到足以证明某项改动来自 GLM 的提交证据。经验三次调整记录作者均为 `Codex <codex@local>`；可确认代码/日期/作用范围，不能把作者模型或疏漏意图当成事实。

## 权威源与当前覆写层

| 内容 | 当前权威及消费者 |
| --- | --- |
| 道士成员、原公式与目标合同 | `assets/data/source_priority_policy.json:165` 的 skills lane；`assets/data/vanilla_176/skills_source_of_truth_v1.json:2938` 起的 13 项；`scripts/skills/skill_data_loader.gd` 校验其固定来源身份。 |
| 项目技能成长 | `scripts/skills/skill_progression_service.gd:9`，`skills.progression.hardcore.v2`：第一本书直接 rank 1，第三本 rank 3，装备加有效等级，熟练度停产。不能用 SOT 的旧 2000/4000/8000 熟练度要求解释当前升级慢。 |
| 宠物属性与原始成长 | `assets/data/vanilla_176/taoist_summon_baseline.json:3` 的 `skills.taoist_summon.original_database_binary_verified.v1`；`:19` growth_contract；`scripts/taoist_combat_math.gd:93,147,158,182` 消费。基础属性为用户明确权威覆写，不能用其他服务数据替换。 |
| 原始成长源码 | `dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:2268` 的 GainSlaveExp；`M2Share.pas:1640` 默认 `nMonUpLvNeedKillBase=100`、`nMonUpLvRate=16`、level_extra。原源码 `ObjBase.pas:20847` 给 `m_ExpHitter` 的宠物经验；该指针的归属规则不能不经调查便等同本项目最后一击规则。 |
| 人物经验 | `assets/data/service_reference.json` 的 `serviceRuntimeExpTableLevel1To60` → `scripts/game_data.gd:3790` → `scripts/player_state.gd:2240` 与 `:2252` 两段缩放。 |
| 怪物经验/等级 | `assets/data/runtime/canonical_monster_catalog.json` 精确 `monster_id` 的 `combat.stats.exp/level`。`EnemyActor.setup:578,582` 将 canonical level 写入成员及 `monster_data.level`；不是名称回退或来访 payload 提供的值。 |
| 项目运行覆盖 | 同时存在材料免费、双宠按 summon_id 共存、同类活宠召回、双防御一次施法等已实施项目合同。不可照抄旧 SOT 单组限制、消耗符纸或旧熟练度测试名恢复旧玩法。 |

## 全部道士技能路径

共 13 个稳定 ID，当前 `TaoistSkillRuntime.execute:45` 逐一明确分派。表中行号是采样时刻，后续主控改动应以符号定位。

| 稳定 skill_id / 名称 | 计划与真实生产消费 | 已有覆盖与边界 |
| --- | --- | --- |
| `taoist.healing` 治愈术 | runtime `:106` 单体选择；`TaoistSupportPolicy:116` 选择 9 GU 内血量缺失比例最高的活友方；GameRoot `:8804` → `_apply_canonical_friendly_heal`。满血施法附 3 次、每 0.8s 的持续恢复。 | support policy/runtime/production integration PASS；满血持续恢复并非负伤害。 |
| `taoist.spiritual_warfare` 精神力战法 | runtime `:56` 生成 accuracy modifier，rank 0～3 为 0/3/5/8；SOT `:3127` 限定物理近战命中。 | 描述符/语义检查 PASS；正式物理命中消费缺口见 T01。 |
| `taoist.poison` 施毒术 | runtime `:185` 同次生成绿毒 DOT 与红毒 AC/MAC 降低；GameRoot `:9041` → `_apply_canonical_poison:10582`；EnemyActor `:6334` DOT 走 `causes_struck=false`。 | canonical/support 与毒/硬直相关现有测试；毒死亡没有宠物成长 credit，见 T03。 |
| `taoist.soul_fire_talisman` 灵魂火符 | runtime `:238` 输出 `talisman_projectile_damage`，明确 `spirit_magic/MAC`，进入 canonical projectile descriptor 和正式延迟释放链。 | soul_fire_launch_timing、projectile async/origin/stealth-buff visual 在 critical PASS。 |
| `taoist.summon_skeleton` 召唤骷髅 | runtime `:259` → main_pet_spawn/recall descriptor → GameRoot `_apply_canonical_summon_descriptor` → SummonActor；独立 skeleton 槽。 | canonical_summon_integration PASS；新攻击出伤与成长证据边界见后文。 |
| `taoist.invisibility` 隐身术 | runtime `:309` → GameRoot `:8956` → player.apply_stealth；隐藏仇恨，不是无敌/不可选中；项目覆写任何攻击/施法打破。 | canonical/support 测试 PASS；反隐能力由敌方权威消费。 |
| `taoist.mass_invisibility` 集体隐身术 | runtime `:332` 3×3 友方区域，GameRoot `:8960` 按友方实例 ID 施加；活主人及自有召唤物可受益。 | production support / summon projectile stealth visual PASS；宠物攻击开始即破隐。 |
| `taoist.magic_defense` 幽灵盾 | runtime `:404/511` 的友方 MAC；与 AC 组合时用一个资源事务；GameRoot `:8989` 按 stat 分派。 | dual_defense_contract 和 support production PASS；不应与物理 AC 混算。 |
| `taoist.defense` 神圣战甲术 | 同入口的 AC，独立于 MAC；bonus 为 `floor(target_level/7)`、最低 1（runtime `:602`）。 | 宠物的 target_level 当前取冻结 owner_level，不取宠物等级；这是现有明确测试合同。 |
| `taoist.revelation` 心灵启示 | runtime `:618` → hp_information_reveal；GameRoot `:9071` 检查 frozen snapshot 相交后显示正式目标血量。 | canonical/语义覆盖，不是造成伤害的技能。 |
| `taoist.entrapment` 困魔咒 | runtime `:651` → monster_boundary_control；GameRoot `:9086` 将实例身份和严格 snapshot 交给 EnemyActor.apply_entrapment。 | entrapment_boundary_production PASS；宠物攻击被困怪由 `EnemyActor.accepts_external_attack_from:6576` 拒绝，不是宠物卡死的通用证据。 |
| `taoist.mass_healing` 群体治疗术 | runtime `:758` → dedicated_area_heal，GameRoot `:8836` 逐友方恢复并注册持续 tick；友方池为当前主人与其活宠。 | support production PASS；友方实例死亡/被替换后 `_tick_ongoing_heals:10824` 丢弃该实例的剩余 tick。 |
| `taoist.summon_divine_beast` 召唤神兽 | 与骷髅相同正式生成/召回结构，独立 divine_beast 槽；攻击标签 fire。 | 双宠共存、单槽死亡、重召/跨图恢复 PASS；标签 fire 不证明实际 MAC 出伤，见 T02。 |

本表是生产路径定位，不是本子任务逐个运行技能的证明；20 项相关 critical PASS 只证明实际被执行的断言。

## 人物与宠物升级的精确对照

人物生产死亡奖励来源：GameRoot `_build_enemy_death_runtime_snapshot:5074` 固定 canonical `exp`，`_on_enemy_died:12562` 排队，`:13095` 调 PlayerState `record_kills_and_experience_batch`，后者 `:2159` 加完整经验并按当前缩放门槛循环升级。没有在该死亡奖励链找到额外经验乘数。

人物阈值：`T(level)=max(1,round(max(1,round(source(level)/30))*0.70))`。不能把两次取整合并成一次。19/26/35/40 级分别为 2800/16333/93333/280000。当前六个比奇任务奖励仅 gold/items（`bich_quest_chain.json` 与 `PlayerState.claim_quest:2642`），没有任务经验可用来解释人物额外加速。

已核对历史：`0abc83e9`（2026-09-05）人物门槛降至原 10%；`36bfb5f8`（2026-09-06）改为原 1/30；`191958ea`（2026-09-13）在前值上再乘 0.70。宠物 `gain_growth_from_kill` 最早记录为 `cd7cefd2`（2026-08-09），当前仍无这两项人物缩放常量。历史可证明两套公式演变不同，不能证明提交者实际用了哪个模型。

宠物公式：每次本宠亲自完成最后一击，`pet_growth_exp += max(0,killed_monster_level)`；只有累计值 **严格大于** 阈值才升级，减去阈值、保留余数，每次最多一级。骷髅基准 monster_level=15，神兽=32；阈值如下。

| 当前宠物等级 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 骷髅阈值 | 325 | 325 | 375 | 425 | 525 | 625 | 925 |
| 神兽阈值 | 580 | 580 | 630 | 680 | 780 | 880 | 1180 |

下表按**新召宠物成长经验为 0、无装备额外技能等级、每只怪都由该宠补刀**精确循环计算。宠物列为到达后续各等级的累计击杀数，已计入余数，不是各级分别取整后相加；人物列为从该级 0 XP 升下一级所需同种怪数量。没有把战斗耗时、Boss 刷新等待或两宠分摊假设成事实。

| 人物/技能条件 | 怪物精确 ID；怪物 level/exp | 宠物升级累计击杀数 | 人物升 1 级所需击杀 |
| --- | --- | --- | ---: |
| 19 级、骷髅 rank1，宠物1→3 | 110 蜈蚣；26 / 230 | 到2：13；到3：27 | 13 |
| 19 级、骷髅 rank1，宠物1→3 | 118 钳虫；31 / 250 | 到2：11；到3：23 | 12 |
| 26 级、骷髅 rank3，宠物3→7 | 110 蜈蚣；26 / 230 | 到4/5/6/7：17 / 37 / 61 / 97 | 72 |
| 26 级、骷髅 rank3，宠物3→7 | 118 钳虫；31 / 250 | 14 / 31 / 51 / 81 | 66 |
| 35 级、神兽 rank1，宠物1→3 | 168 月魔蜘蛛；52 / 700 | 到2：12；到3：24 | 134 |
| 35 级、神兽 rank1，宠物1→3 | 176 天狼蜘蛛；43 / 500 | 到2：14；到3：29 | 187 |
| 40 级、神兽 rank3，宠物3→7 | 168 月魔蜘蛛；52 / 700 | 14 / 29 / 46 / 68 | 400 |
| 40 级、神兽 rank3，宠物3→7 | 180 赤月恶魔；60 / 5000 | 12 / 25 / 40 / 59 | 56 |

因此当前“慢”不具有统一倍率结论。若同一场战斗神兽只补到每 20 只中的 1 只月魔，3→7 的 68 次补刀需要总共 1360 只；若始终由玩家绿毒/火符击杀，宠物经验永远 0，调整阈值也不能解决。这个 1/20 是说明归属影响的确定性场景条件，不是测得的玩家平均补刀率。

## 召唤物状态生命周期

- **生成/重召：** `TaoistSkillRuntime:267` 检查同一 summon_id 是否存在；活宠只 recall，resource_commit=false；GameRoot `:11149` 只更新位置与释放 footprint。同类不替换，不恢复 HP、不清成长；另一类可共存。死宠重召是新的实例和初始 rank，成长经验从 0 开始。
- **目标/释放：** `SummonActor._nearest_enemy:863` 消费公共 spatial index，缺失索引 fail closed；`:707` 清除死/queued/不接受攻击目标，`:719` 检查主人 leash；`:765` 开始攻击并冻结 snapshot，`:800` 在释放帧重新检查身份/存活/外部攻击许可/相交。
- **主人传送/跨图：** GameRoot `_load_zone:4206` 先抓取两槽，再删除旧 zone_content，`:4270` 恢复；`_relocate_main_pets_after_map_arrival:11208` 根据最终主人落点选合法宠物位置。`summon_owner_teleport_runtime_test` 已通过，覆盖旧攻击/目标状态清理，不能误说只改坐标。
- **距离过远的自行回跟：** SummonActor `:698` 直接设置 `_owner_formation_anchor_screen_px()`；本次未动态验证窄角落的碰撞合法性，不把该静态分支单独定性为本次设备故障。
- **死亡：** 主人无效/HP≤0 或寿命耗尽使宠物 expire（`:684`）；宠物 DEAD/EXPIRED 信号由 GameRoot `:10701` 清除相应存档槽。另一只宠物状态保留。
- **持久化：** `persistence_snapshot:1800` 保存 rank、owner level、HP、pet level、cap、growth XP、寿命与独立 AC/MAC/隐身状态；PlayerState `:4914,4981,5452,5975` 按明确合同及 typed slot 保存/恢复；旧单槽兼容只做确定身份转换。
- **恢复属性已修复：** `restore_persistence_snapshot:1835` 恢复等级后 `:1881` 调 `_apply_growth_stats_preserving_current_hp`，重新导出 HP/DC/AC/MAC/accuracy/agility；不再信任存档 max_hp。此旧问题不是本轮当前缺陷。
- **入伤已分层：** SummonActor `:1272` 物理扣 AC；`:1320` 魔法扣 MAC；`:1332` direct spell 接口；`:1290` 混合伤害原子结算，毒 tick 使用无 struck 分支。`summon_incoming_damage_runtime_test` 的真实宠物入伤验证已 PASS。这不能推出宠物对外攻击也正确。

## 主控待裁决的具体候选

### T01：精神力战法描述符未进入人物正式物理命中

状态：MISSING（正式消费者未找到）；动态反例 NOT_RUN。建议优先级 P1。

证据：SOT `:3127` 与 Taoist runtime `:56` 明确 rank3 应加 8，且只作用 `physical_melee_hit_checks`。GameRoot `:7223` 的正式近战入口只调用 `resolve_warrior_melee_modifiers`，传 basic_sword/slaying；router `:214` 也只处理这两项。`PlayerState.recalculate_stats` 的 accuracy 来源是人物基础、装备和套装，未消费道士 passive。对 scripts 的 stable ID、中文名、`passive_stat_modifier` 与 `flat_accuracy_bonus` 引用核对未找到额外消费者。

现有 `taoist_canonical_runtime_test:40` 仅断言 effect.value=8；`taoist_skill_semantic_contracts:115` 只检查描述符及 affects。不能证明实际攻击命中改变。

最窄反例：真实道士、同装备与目标，比较未学/学 rank3 时同一个正式普攻释放的 hit-check 输入；选基准命中 5、加成后 13、目标 agility 大于 13，并使用位于两阈值之间的确定 roll，证明实际 MISS→HIT。再验证火符、施毒、神兽的命中规则没有获得该人物近战加成。不要通过给全部 computed accuracy 或法术概率统一加 8 来修。

### T02：宠物对外攻击绕过目标防御，神兽与骷髅分层不完整

状态：FAIL（静态消费链与源规则不一致）；动态反例 NOT_RUN。建议优先级 P1。

`SummonActor._release_pending_attack:815` 对两种宠物均调用 `target.take_damage(_rng.randi_range(attack_min,attack_max),self)`；EnemyActor `take_damage:6193` → `_apply_damage_core:6238` 直接扣传入 HP，未计算防御。宠物这一调用之前也没有目标 AC/MAC 计算；`_attack_hit_succeeds:821` 只为 physical 做 accuracy/agility roll，fire 返回 true。

因此当前骷髅伤害绕过目标 AC；神兽 fire 绕过 MAC 且命中必成。红毒的 AC/MAC 降低不会经这条原始扣血调用增加宠物伤害。名字/attack_type 标签本身不构成完整的伤害规则。

原始源佐证：`ObjMon.pas:219` 的 `TElfWarriorMonster = class(TSpitSpider)`；`:674` SpitAttack 使用 DC，`:698` 做 accuracy/agility 命中，`:701` 调 `GetMagStruckDamage`。这也说明不能把“法术层”简单实现为一律无敏捷命中：具体神兽 primary 规则需主控确认后统一投递，不能把人物技能附加给宠物。

最窄反例：真实 canonical 高 AC/MAC 怪物、保留真实目标类，只固定宠物攻击 roll。骷髅对高 AC/低 MAC 与低 AC/高 MAC 的同 raw DC 应仅受 AC 差异影响；神兽应按已确认规则仅受 MAC 差异影响。另分别验证确定命中/落空、红毒前后、struck 只触发一次、成长只在真实击杀后一次结算。不得把测试替身的 take_damage 内部减防当成生产证明。

### T03：人物/毒/另一宠补刀可使本宠长期 0 成长

状态：PASS（当前行为和唯一调用点已确认）；是否改变是玩法裁决，新增匹配要求的动态验收 NOT_RUN。

scripts 范围唯一生产 `gain_growth_from_kill` 调用为 `summon_actor.gd:817`。它仅包围本宠 `_release_pending_attack` 的 `hp_before>0 && hp_after<=0`；GameRoot 的死亡经验队列没有宠物 credit；绿毒 `EnemyActor:6335` 用 null attacker，另一个宠物仅给自己记分。

确定反例：神兽已累计至下一阈值、主人火符或绿毒完成 10 只真实怪击杀，人物得到 10 份 canonical exp，神兽 pet_growth_exp/level 完全不变；由神兽补最后一击的对照才升级。两只宠物同时存在时分别记录 typed slot，不将另一宠的 credit 混用。

与用户“宠物升级匹配人物”最相关的产品选择是归属是否继续限本宠补刀、还是将符合明确资格的主人击杀也授予成长；只调阈值无法修复零 credit。没有已批准的新数值，报告不自行设倍率、半径、共享比例或补发经验。

### T04：提高技能等级后活宠继续被旧 cap 封顶

状态：PASS（可由赋值/召回/恢复路径确定）；是否属于需修缺陷由主控按最新要求裁决。动态反例 NOT_RUN。

rank1 召唤得到 level1/cap3；长大到 level3 后 `gain_growth_from_kill:1037` 直接 return false。人物后续读书将技能升 rank3，PlayerState 只更新技能/角色并保存；SummonActor 的 skill_level/cap 只在 `setup:258` 和 `restore:1845` 赋值。重召 `GameRoot:11149` 只移位；跨图恢复使用旧 snapshot 的 rank/cap，因此仍 cap3，无法继续到7。现有 `canonical_summon_integration_test:146` 要求同类重召完整 snapshot 不变，但未覆盖期间技能等级改变。

最窄反例：真实 rank1 宠到3 → 正式学书至 rank3 → 同类召回 → 击杀 → 跨图/存档恢复，记录旧 cap 的持续性。主控若决定动态提高 cap，应明确学习、装备加/减技能等级和存档兼容边界，保留同实例/HP/成长 XP，不以杀宠或重建清零解决。宠物属性不随主人等级增加目前也是明文合同（TaoistCombatMath `:102`），不能将人物加速自动映射成宠物属性倍率。

### T05：成长专项的旧 fixture 无法证明真实生产路径

状态：MISSING（本轮未有该场景正式通过证据）；NOT_RUN。

`tests/taoist_summon_growth_contract_test.gd:78` 使用无 monster_id 的旧 name/hp/level 字典创建 EnemyActor，当前 `EnemyActor.setup:529` 要求精确 canonical ID，拒绝后不会接受这些测试数值；测试还未配置当前正式 spatial index。该场景不在 16:47 critical 的 429 项结果中。因此不能把现有成长单元断言、旧测试文件存在或整个 critical 的大多数 PASS 当成真实宠物击杀成长通过。

最窄修正应由主控使用 `GameData.get_monster_by_id` 与真实 GameRoot 生成/索引，将目标 current_hp 作为测试前置状态设为确定可杀，保留 canonical level。覆盖骷髅/神兽、自身/主人/毒/另一宠最后一击、3→7 连续成长、封顶、死亡重召和读档后属性重算。不能恢复名称 fallback，也不能删严格阈值/余数/HP 保持断言。

## 验证和证据身份

本子任务用只读 Python 对当前 canonical 字段按源码整数逻辑独立重算上述表，PASS；没有运行游戏，不能称为真实战斗耗时测试。读取的完整 critical 汇总为 `outputs/test_logs/runner_results_critical_20260922_164713_635_6132.json`，其中 20 项名称含 taoist/summon/progression/experience 的相关场景 PASS；它们不包含 T01/T02 的正式出伤/命中反例或成长专项。

已有生产测试覆盖：`canonical_summon_integration_test` 的双类型共存、同类召回、单类死亡替换、双槽跨图恢复和幂等；`summon_owner_teleport_runtime_test` 的最终主人落点重定位及攻击/目标清理；`summon_incoming_damage_runtime_test` 的入伤 AC/MAC；道士 support/canonical/dual-defense/entrapment/火符时序及投射物视觉。以上已证明部分不要求因报告而无意义重跑，后续受改动影响范围由主控决定。

采样 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `scripts/player_state.gd` | `e8e956810196c49088c719e3f70a03485d37ebad2a58ab1c15d42350d2522563` |
| `scripts/summon_actor.gd` | `6d2dbc4f73d361d173428a7671b8be721e61405a0f7794833c882a059a04da6e` |
| `scripts/taoist_combat_math.gd` | `32405428c027e60e9cc691119a576712a735e6844abcfe25f319a31ab8ca5b19` |
| `scripts/skills/runtimes/taoist_skill_runtime.gd` | `4cf271301008687433b1e425a6c458c28f15fe7ad6d40f88db596513867be04f` |
| `scripts/skills/skill_progression_service.gd` | `bc6f75f8e9ca05e96a56db36dfae1a30f86e854cfb839e2abca02df86671b0dc` |
| `assets/data/vanilla_176/taoist_summon_baseline.json` | `3b9d46288053540250930c94ffcd93282fe5d88e22b0f6caa40617b5a63207a3` |

稳定 ID 无新增/删除/改名；本报告不选择新宠物经验倍率，不修改 primary/source-of-truth，不对旧 AGENTS 禁代理限制作新的扩大解释。最终玩法、实现、动态验证、集成与设备验收均由主控承担。
