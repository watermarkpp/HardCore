# 特殊装备功能连接总表

2026-10-08更新：本表以下为改动前普查与历史证据；本轮指定条目的现状以[特装/HUD最终交接](../special_equipment_20261008/FINAL_RESULT.md)为准。麻痹普通5秒/精英Boss2.5秒、复活300秒及戒指自动复活经验、隐身穿戴/脱战恢复、三个戒指独立技能/技能栏绑定、技巧项链允许池随机+1、神秘三件原资料库随机属性及穿戴需求均已实现并完成相应专项。探测只移除正式唯一掉落UID，已有物品保留。40装备清单身份范围保持；新增技巧+神秘四个正式消费者，连接普查现为29项，data_only仍探测/求婚2项，祈祷/记忆9项延期；该数量不是逐件玩法全量验收数。DEVICE TEST: NOT_RUN。

核验日期：2026-10-07。工作区 `C:/Users/Administrator/Documents/HardCore`，分支 `codex/integration`，HEAD `215f0b2f651a51e6855ee813ddd99221690311a1`，含其他工作人的未提交改动。本次只读核验并写审计文档，没有修改生产、配置或测试，没有运行 Godot。

本表核对登记身份、装备状态和正式消费者，不把装备说明或可注入的测试词条当作已完成玩法。固定特殊功能及明确相关属性共列 **40 个装备 ID**：34 件经典目录装备及 6 件合成圣物／徽章；远古圣物碎片是材料，另列不计装备。普通攻击、防御、魔法、道术基础数值不计特殊功能。只读普查时原生为NOT_RUN；后续本轮既有 `equipment_special_effects_test` 在 `special_ring_existing_current_233016_797740` **PASS**、原生退出0、源码稳定。它只覆盖该既有场景断言，不补齐麻痹真实命中生命周期，也不使下表全部功能成为PASS。其余当前专项仍 **NOT_RUN**，**DEVICE TEST: NOT_RUN**。

表中“已接源码”表示找到了正式消费者；“data_only”表示只有描述／元数据，未找到对应生产功能；“延期”表示配置明确放入 `deferredSets`。这些是连接状态，不能替代原生 PASS／FAIL。8 戒指的完整链路、断点、历史 receipt 和麻痹补测方案见 [特殊戒指连接审计](SPECIAL_RING_CONNECTION_AUDIT.md)。

## 身份与状态权威

- 经典属性权威为 `assets/data/equipment_attribute_master.json` 的 175 条 records；稳定 ID 与名称逐条核对 `assets/data/runtime/entity_registry_v1.json`。表中的 `hc.item.000xxx` 是登记结果，不是按名称推定。
- 明确运行配置：`assets/data/equipment_customization.json:5-18`（8 特戒和魔血／虹魔）；`assets/data/equipment_special_rules.json:9,51,62`（runtimeEffects、延期套装、候选公式）；`assets/data/relic_synthesis_v1.json:14-19`（6 合成装备）。特戒和魔血／虹魔映射当前仍标 `confidence:B`，不声称已逐件证明原服数据库映射。
- `scripts/game_data.gd:265,274,2322,2602` 读 merged items、应用明确 customization 并登记 catalog。customization 当前仍有名称键导入边界；正式装备实例通过 `GameData.get_item_record(instance)` 消费身份。
- `scripts/player_state.gd:3559,3604,3606,3701` 每次重算清空效果集合、跳过零耐久、解析装备记录，再注册实际运行效果；`:3177` 卸下后重算，保存失败回滚后也重算。特戒和普通套装的损坏／卸下不保留计算效果。圣物／徽章还有各自的实例校验与状态清理，见后文。

## 八种已连接特殊戒指

| 稳定 ID | 名称 | 当前正式行为／触发 | 限制、边界与证据 |
|---|---|---|---|
| `hc.item.000252` | 麻痹戒指 | **已接源码**。正式 melee 物理伤害成功提交后，概率 `1/max(1,目标 anti_poison+5)`，基础 20%，控制 5 秒。 | `scripts/game_root.gd:12881` → `scripts/equipment_rules.gd:414` → `scripts/enemy.gd:7446`。该处没有专属冷却／Boss 免疫门。现有专项只测概率 helper，真实玩家动作→HP 提交→控制计时的完整专项不足。 |
| `hc.item.000253` | 隐身戒指 | **已接源码**。有效装备可隐身，攻击／技能提交会打破；反隐身怪可识别。 | `scripts/player.gd:1920,1803`；`scripts/enemy.gd:2972` 等正式感知入口。打破后的 actor latch 未发现装备变化复位；同 actor 重新穿戴是否应恢复需规格决定。 |
| `hc.item.000254` | 传送戒指 | **已接源码**。“特装”沿朝向尝试 5.625→1.125 GU 的五档短距离，原生 `test_move` 全段通过才位移。 | `scripts/game_root.gd:7885,7927`。无该 helper 专属 MP／冷却／禁传地图检查；当前行为不是说明中的坐标／命令传送，规格差异待决定。死亡／切图时 UI 可触发性未证。 |
| `hc.item.000255` | 防御戒指 | **已接源码**。“特装”花 5 MP，自疗 `max(12,int(level/2)+tao_max*2)`。 | `scripts/game_root.gd:7918`；`scripts/player.gd:1647` 拒绝死者回血。该 handler 无专属冷却；不是自动防御 buff 或完整技能学习入口。 |
| `hc.item.000256` | 复活戒指 | **已接源码**。致死 HP=0 且距上次触发 ≥60 秒，原地满 HP、耗 1 显示点耐久，条件符合时必触发。 | `scripts/player.gd:1074-1086`。同 actor 记忆冷却，不入存档；重建 actor 可重置。自动复活未清毒，正常死亡分支才清毒；已有 poison=0 断言没有先种毒，不能证明带毒复活正确。 |
| `hc.item.000257` | 护身戒指 | **已接源码**。最终伤害以 `round(damage*1.5)` MP 抵偿，不足则耗尽 MP 并把欠付部分换回 HP 伤害。 | `scripts/player.gd:1038` 正式受伤结算。无随机／专属冷却，不是降低基础伤害公式。 |
| `hc.item.000258` | 超负载戒指 | **已接源码**。穿戴、手持、背包三项负重上限各 ×2。 | `scripts/player_state.gd:3713`。重复同效果不会逐戒指叠乘；零耐久失效。 |
| `hc.item.000259` | 火焰戒指 | **已接源码**。“特装”花 5 MP，以 magic_min/max 掷伤害并生成正式火球投射物、使用火球射程。 | `scripts/game_root.gd:7890`。该 handler 无专属冷却；没有通过 canonical 学习／技能 action 的完整入口，不能把“生成火球”表述成已学火球。 |

等级需求：隐身／传送 12，其余六种 16；无职业／性别锁。属性主表起始行依次为 9907、9971、10029、10087、10151、10220、10284、10348。当前所有本轮专项 **NOT_RUN**，麻痹端到端证据尤其不足。

## 项链、神秘与求婚装备

| 稳定 ID | 名称 | 主表位置／功能登记 | 连接结论、限制或缺口 |
|---|---|---|---|
| `hc.item.000250` | 技巧项链 | `equipment_attribute_master.json:9791`；`skill_training_boost`；16 级 | **data_only**。未找到训练倍率消费者。`scripts/skills/skill_progression_service.gd:104,113` 正式熟练度事件明确返回 `proficiency_disabled`；当前禁用熟练度体系，不能自动启用以补这条描述。 |
| `hc.item.000251` | 探测项链 | 主表 `:9849`；`player_coordinate_detection`；1 级 | **data_only**。未找到同地图玩家坐标探测的生产消费者、目标选择或结果 UI。触发率、冷却、目标规则尚未落可执行规格。 |
| `hc.item.000218` | 神秘头盔 | 主表 `:7796`；`mystery_random_stats`；18 级 | **data_only**。未找到神秘专用随机实例属性、诅咒锁装备／神水解除链路。普通掉落小极品系统不能代替这项专属功能。 |
| `hc.item.000219` | 神秘腰带 | 主表 `:7855`；同上；18 级 | **data_only**，同上。 |
| `hc.item.000220` | 神秘戒指 | 主表 `:7914`；同上；18 级 | **data_only**，同上。 |
| `hc.item.000260` | 求婚戒指 | 主表 `:10412`；`marriage_proposal`；1 级 | **data_only**。未找到婚姻／求婚业务消费者，无战斗效果消费者；不能因佩戴成功就称求婚功能可用。 |
| **MISSING** | 用户所称“幸运项链” | 当前 master／registry 无该独立登记名称或稳定 ID | 不猜测身份、不分配 ID。通用幸运字段已有消费者；现有命名装备“幸运守护”是圣物 `hc.item.950103`，不是项链。白色虎齿／灯笼是闪避项链，本次记录未给它们基础 luck。 |

## 套装：逐件 ID 与实际消费者

| 套装 | 每个稳定 ID → 名称 | 连接结论与当前行为 |
|---|---|---|
| 祈祷 | `hc.item.000223` → 祈祷之刃；`hc.item.000224` → 祈祷头盔；`hc.item.000225` → 祈祷项链；`hc.item.000226` → 祈祷手镯；`hc.item.000227` → 祈祷戒指 | **延期／data_only**。`equipment_special_rules.json:51-56` 明确 deferred。主表四件登记 `prayer_pet_rebellion`，但未找到宠物叛变、整套识别、随机消失一件的生产消费者。祈祷之刃没有该主表 specialEffectId，却确实被 deferred 集合登记，不能漏列或声称单刀触发。 |
| 记忆 | `hc.item.000228` → 记忆头盔；`hc.item.000229` → 记忆项链；`hc.item.000230` → 记忆手镯；`hc.item.000231` → 记忆戒指 | **延期／data_only**。`equipment_special_rules.json:57-60` 明确 deferred，主表 `memory_group_recall`。未找到组队召回、同意权限／地图限制、冷却或目标集合的正式消费者。 |
| 魔血 | `hc.item.000244` → 魔血戒指；`hc.item.000245` → 魔血手镯；`hc.item.000246` → 魔血项链 | **已接源码**。`equipment_customization.json:13-15` 每件 power 25；`scripts/player_state.gd:3717` 将 MP 上限转 HP 上限，项链／手镯／戒指三个不同部件类型齐全额外 +50。总转量封顶 `max_mp-1`，不是按百分比或回血 proc。多件同类型计 power，但不能补齐另一部件类型。零耐久／卸下重算失效。 |
| 虹魔 | `hc.item.000247` → 虹魔戒指；`hc.item.000248` → 虹魔手镯；`hc.item.000249` → 虹魔项链 | **已接源码**。`equipment_customization.json:16-18` 项链／手镯／戒指分别 4%／3%／2%；`scripts/player_state.gd:3725` 汇总，三类型齐全准确 +2。`scripts/game_root.gd:12877` 成功 melee 伤害提交后按传入 damage 计算整数回血，结果 ≥2 才回血；用的是传入伤害值，尚不是按目标实际 HP 减量计算。没有该分支专属概率／冷却，生命恢复遵守正式上限和死者限制。 |

主表 ID 行：祈祷之刃 1199；祈祷四件 8099/8169/8234/8299；记忆四件 8364/8429/8494/8559；魔血三件 9382/9461/9526；虹魔三件 9596/9661/9726。魔血／虹魔现有 `equipment_special_phase2_test` 覆盖转换、真实 `_apply_physical_hit` 吸血、零耐久撤销；本轮 **NOT_RUN**。祈祷／记忆没有对应完整玩法专项可据此声明通过。

## 其他固定战斗特殊属性

| 稳定 ID | 名称 | 正式属性及消费者 | 证据范围／限制 |
|---|---|---|---|
| `hc.item.000159` | 白色虎齿项链 | 主表 `:4275,4331`：20% 魔法闪避／内部 2 点。`scripts/player_state.gd:3669` → `scripts/player.gd:901,936` → `scripts/combat_resolution_rules.gd:99` 正式闪避门。 | **已接源码**。0..9 的 roll<points 成功；点数总量限制 0..10。属于闪避门，不是魔防。需求 max_sc≥11。专项用注入 stats／真实投射接触验证算法，但不足以证明这件自然掉落→穿戴→命中全链。 |
| `hc.item.000164` | 灯笼项链 | 主表 `:4582,4647`：10% 魔法闪避／内部 1 点；同上正式消费者。 | **已接源码**，18 级需求。代码区分魔法／远程与物理近战，不能笼统声称所有攻击闪避。 |
| `hc.item.000221` | 狂风项链 | 主表 `:7973,8033`：attackSpeedTier +2。`scripts/player_state.gd:3677` → `scripts/player.gd:1960`。 | **已接源码**，19 级。物理间隔 `max(0,900-60*tier)` ms；法师／道士还按同间隔比例缩放施法时序（900→780 ms 对应比例），战士仍走物理速度。无随机触发／独立 CD。 |
| `hc.item.000222` | 狂风戒指 | 主表 `:8036,8096`：attackSpeedTier +1；同上。 | **已接源码**，16 级。900→840 ms；`equipment_spell_speed_test` 现有专项验证穿卸、自然技能提交／释放与重施法锁，但本轮 **NOT_RUN**。 |
| `hc.item.000115` | 逍遥扇 | registry `:575`；当前正式加载的 `assets/data/runtime/merged_game_database.json:10100,10117` 为基础 luck +1。`scripts/equipment_rules.gd:320` → `scripts/player_state.gd:3661` → `scripts/game_root.gd:12310`。 | **已接源码，但来源边界需区分**：master 属性记录 `:1862` 没有 luck 字段；这项来自当前 merged catalog 的兼容字段，不能称 master 已明确 authoring 幸运。现有 `equipment_luck_test.gd:117-122` 验证该武器基础 luck 与实例幸运／诅咒不重复计算。 |

通用 luck 为装备 catalog `luck-curse` 加武器实例 `weapon_luck-weapon_curse`；零耐久禁用，修复后恢复，不清除实例存档字段。`scripts/warrior_combat_math.gd:78` 对 DC/MC/SC 主属性采用正幸运上端、负幸运下端概率偏向；总幸运 +9／-9 在正跨度分别锁上／下限，独立技能成功率不自动随幸运改变。未找到已登记“幸运项链”的生产实例，测试对普通古铜戒指人为注入 luck 只证明通用聚合，不能当作正式幸运项链。

## 正式合成圣物与徽章

6 件均在 `relic_synthesis_v1.json:14-19` 和 registry 登记，运行装备槽分别为 `hc.slot.relic`、`hc.slot.badge`。每件实例随机一条技能 +1；合法技能按 stable skill ID 的职业池抽取（战士 5、法师 6、道士 6）。圣物配方可选职业池，徽章固定其对应职业池；跨职业穿戴时不适用的技能加成被过滤，未学技能不会被装备启用。`scripts/layers/rules/relic_synthesis_rules.gd:76,109,232` 严格校验实例，`scripts/player_state.gd:3639,3917` 处理职业／未学习边界。

| 稳定 ID | 名称 | 常驻效果 | 主动／周期效果与限制 |
|---|---|---|---|
| `hc.item.950101` | 魔龙之眼 | 随机技能 +1；attackSpeedTier +1 | **已接源码**。合法攻击／技能释放有 20% 触发额外 attackSpeedTier +2，持续 10 秒，结束后冷却 15 秒；相对未佩戴的本件合计常驻 +1、触发期间 +3。 |
| `hc.item.950102` | 魔龙之心 | 随机技能 +1；新合成实例 attack/magic/tao 的 max 各 +5 | **已接源码**。同 20%／10 秒／结束后 15 秒，期间 DC/MC/SC 六个 min/max 各 `round(value*1.15)`。旧合法实例的 maxima 3..5 仍被校验兼容，不把历史值重写成 +5。 |
| `hc.item.950103` | 幸运守护 | 随机技能 +1；luck +1 | **已接源码**。同 20%／10 秒／结束后 15 秒，触发额外 luck +2；本件触发期间合计 +3，进入上述正式主属性 roll。不是“幸运项链”。 |
| `hc.item.950201` | 勇气徽章 | 战士池随机技能 +1 | **已接源码**。每累计 1 秒恢复 `round(max_hp*1%)` HP，存活／有缺口才恢复；无随机触发／15 秒 proc 冷却。 |
| `hc.item.950202` | 智慧徽章 | 法师池随机技能 +1 | **已接源码**。每累计 1 秒恢复 `round(max_mp*1%)` MP，同上。 |
| `hc.item.950203` | 信仰徽章 | 道士池随机技能 +1 | **已接源码**。每累计 1 秒恢复 `round(max_mp*1%)` MP，同上。 |

合成成本为 4 个 `hc.item.950001` **远古圣物碎片**和 400000 金币，成功率 100%。35 级是生成 catalog 的装备需求（`relic_synthesis_rules.gd:231`），不能据此声称合成服务有 35 级合成门：`scripts/layers/runtime/relic_synthesis_service.gd:89-116` 检查配方、四个不同材料格、材料身份／数量和金币，没有玩家等级检查。报价和提交会校验材料及报价是否变化并走正式保存；所有六件 `relicNoWear:true`，`:4304` 耐久损耗跳过合成装备。

圣物触发入口 `scripts/game_root.gd:7334-7343,8011` 在正式 release 身份／目标合法性门后，触发不要求本次真的打掉目标 HP；合法空挥也可触发。状态由 `scripts/player_state.gd:3836,3862,3877,3900` 所有，active／cooldown 不叠加。当前计时是 **10 秒生效 + 15 秒休息**，不是从触发起总共 15 秒。装备实例变化／卸下会清 active 和 cooldown；重新换装可重置冷却，这是否符合产品规格待用户决定。

徽章恢复由 `scripts/player.gd:1669` 消费正式 HP／MP，死者／HP≤0、卸下或装备变化清累计时间，不创造另一套资源权威。round 可能让非常低的最大资源恢复量为 0，当前公式未加最小 1。圣物状态重算保留当前 HP／MP，不因增益偷偷补满。以上边界只记录，没有自动修玩法。

## 通用装备词条：有消费者不等于已有对应命名装备

| 生产通道 | 当前连接与限制 | 固定 ID／生成状态 |
|---|---|---|
| 技能等级 +N（单技能／职业／全部） | `scripts/player_state.gd:3648,3710,3917` 聚合，正式 action configuration 使用有效技能等级；未学技能不可启用。6 合成装备有固定 +1 生产实例来源。 | 通用 `assets/data/equipment_skill_level_affix_rollout_v1.json:3-4` 当前 `enabled:false`、eligible IDs 空；不能把 rollout 专项注入 policy 视为自然掉落已打开。当前小极品 V4 施工另外审计，基础数值随机不冒充神秘装备功能。 |
| 暴击率／暴击倍率 | `scripts/player_state.gd:3684` 聚合；`scripts/player.gd:477` 在正式普通攻击伤害 roll 后消费。 | 未发现当前固定经典装备 catalog 非空配置或 customization 命名装备。`equipment_future_modifiers_test` 对木剑注入词条，只能证明通道。 |
| cast_speed_percent | `scripts/player_state.gd:3690` 聚合，`scripts/player.gd:1526,1962` 按 `clamp(1+value,0.2,6)` 缩放。 | 同上，无另一个可声称现成命名装备的稳定 ID。 |
| attack_speed_percent | `scripts/player_state.gd:3689` 聚合及详情展示；当前 actor 实际速度用 attack_speed_tier。 | **连接不完整**。检索未找到正式 actor 对 attack_speed_percent 的消费，不能宣称这条百分比攻速生效。 |
| 抗魔点、速度档、life_steal_percent、条件 modifier、锻造 modifier | `scripts/player_state.gd:3680-3699` 支持合法词条及锻造属性聚合；抗魔／速度档／吸血消费者见前表。 | `ModifierEffectRuntime` 的 generic set/trigger helper 自身不是生产装备登记或业务接入证明。只统计前述已登记固定项，不能从 schema 能力推定更多隐含套装玩法。 |

## 现有专项及本轮验证状态

只读普查时仅列可复用场景；随后主控已执行下表标PASS的两项，未改场景内部业务期限。普通30秒，已知完整正式主世界fixture使用60秒；60秒仅是已知重场景runner外部截止，不能替代内部正式READY／动作期限。

| Exact scene | Runner deadline | 覆盖与证据界限 | 本轮 |
|---|---:|---|---|
| `tests/equipment_special_effects_test.tscn` | 60 秒 | 正式主世界；8 效果配置、护身／隐身／负重零耐久撤销、复活冷却／死亡；麻痹只有 helper roll。 | **PASS**：special_ring_existing_current_233016_797740 |
| `tests/equipment_special_phase2_test.tscn` | 30 秒 | 魔血／虹魔、主动三特戒、HUD 及零耐久；只等两帧后读 enemies，当前异步 boot fixture 适配未证。 | **NOT_RUN** |
| `tests/hc_monster_combat_r2/revival_durability_test.tscn` | 30 秒 | 致死物理击真实复活耐久；没有先种毒，不覆盖带毒复活。 | **NOT_RUN** |
| `tests/relic_synthesis_runtime_test.tscn` | 30 秒 | 正式报价／提交／托盘、保存失败回滚、身份及 proc 状态；受控 RNG／计时部分不等于自然战斗验收。 | **NOT_RUN** |
| `tests/relic_equipped_actor_test.tscn` | 30 秒 | 六件真实 Player actor，存读、未学／已学技能、proc 属性同步／资源保持、徽章恢复／死者／卸下。 | **NOT_RUN** |
| `tests/relic_combat_entry_test.tscn` | 60 秒 | 完整主世界，自然 request_attack／request_skill 释放到 proc＋呈现，拒绝动作不触发。内部正式世界准备截止保持原值。 | **NOT_RUN** |
| `tests/equipment_luck_test.tscn` | 30 秒 | 基础／实例幸运、祝福油、损坏／修复／保存；普通戒指注入不代表幸运项链生产登记。 | **PASS**：sale_luck_related_fixed_225915_541985 |
| `tests/combat_luck_primary_stat_test.tscn` | 30 秒 | DC/MC/SC 幸运端点及独立成功门、自然玩家攻击发射值；不是命名项链专测。 | **NOT_RUN** |
| `tests/repair_20260913/equipment_spell_speed_test.tscn` | 30 秒 | 狂风戒指、真实技能时间／释放及卸下。 | **NOT_RUN** |
| `tests/repair_20260913/ranged_magic_evasion_test.tscn` | 30 秒 | 正式魔法／远程及投射接触、物理近战排除；部分探针／注入 stats，非两件项链完整装备链。 | **NOT_RUN** |
| `tests/equipment_skill_level_affix_test.tscn`、`tests/equipment_skill_level_affix_rollout_test.tscn`、`tests/equipment_future_modifiers_test.tscn` | 各 30 秒 | 通用技能／扩展词条与关闭 rollout；区分 fixture 注入和正式随机产出。 | **NOT_RUN** |

历史 epoch 单列：八戒指专项在 2026-10-03、复活耐久在 2026-10-04 的旧 HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 有绑定 receipt 的原生 PASS；phase2 的 2026-10-02 stdout 有 PASS，但完整 receipt 绑定 **MISSING**。详见戒指审计。这里没有追加寻找圣物／其他专项的历史 PASS，不能借旧日志充当当前测试。

## 源码证据指纹与后续边界

下列 SHA256 是此次读审计时的源码快照，不是 parent 后续冻结或测试指纹；共享源码如再变动，应以本轮 native receipt 的冻结清单为准。文档写入不改变受测 source/test。

| 文件 | SHA256 |
|---|---|
| `assets/data/equipment_attribute_master.json` | `223C96DF954077AA8970A277EFE229D9DBC16609D2503A0033E60197F7E00701` |
| `assets/data/equipment_customization.json` | `24B6B3D9E645A331FDC69898393AED33690983585C0BCBA41E8E9DE8004049FE` |
| `assets/data/equipment_special_rules.json` | `2B9E2F24FDB6DC19C2C2E963D203D820F17BAD233F99BC124AD080D25B86C9F6` |
| `assets/data/relic_synthesis_v1.json` | `9D7CB4F2B09C80F7DBE63782D757CE1532A0CE99C7AE32D3CFAF1FE45FBFD5DF` |
| `scripts/player_state.gd` | `755B90B08D10A6C1DD619586BC865A7926E77989BF8F3396478339CC898346B9` |
| `scripts/player.gd` | `95FDFBD24567982540E81C6F1E8A1D27CF50117D6E9DCC9F7DC3A0F950DCFC70` |
| `scripts/game_root.gd` | `BC7433CE5B5E8B79BC059787E5D665294FAADD3009F2CC1E43D58E9A06EC98CA` |
| `scripts/equipment_rules.gd` | `63697CDEBB698C97279A7A7C3522886CAC421142B3B1391CF785595EF2BFCED9` |
| `scripts/layers/rules/relic_synthesis_rules.gd` | `1C8F6CCF3E4B56B3A2DA0C2B90D2D3FF273999AF146EC88DB2A70FD4158B6A1B` |
| `scripts/layers/runtime/relic_synthesis_service.gd` | `88BE15D9D38758936A00AE3ED8DA337E9EC8BAF9E7E32643F0714640DFB9A6B3` |

需要规格决定的事项包括复活清毒／actor 冷却持久化、隐身重穿恢复、传送规格及状态门、主动特戒技能／冷却、虹魔按实际 HP 减量吸血、圣物换装冷却重置、徽章最小恢复量；此审计没有授权修改它们。未接消费者的技巧／探测／求婚／神秘／祈祷／记忆，也不能自动补功能。

麻痹可复用 `tests/framework/feature_melee_ticket_paths_test.gd:23,58` 的真实 melee fixture：`FormalWorldSkillFixture.prepare_target` 发布稳定 spawn slot，`request_attack_toward(..., lease)` 走正式 action 配置、伤害提交和 HP。建议以后补 4–6 个 proc／未触发／自然控制结束／卸下／损坏／已提交动作边界，用真实可复现 RNG，保持当前内部 3 秒动作／5 秒发布等期限；一组新的 .gd/.tscn，正式主世界 runner 60 秒即可。当前仅给入口及成本，没有新建测试或运行基准。
