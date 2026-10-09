# 特殊装备正式链本地先行审计

核查范围：固定运行源码 `ba97849bfe3a9fe11f12904bfa26b41fc8c7f06a`；该提交的运行代码与审计绑定 `dbd78d3301c2af6cfd9e070abe8cc847e6353175` 等同。未运行 Godot、未修改生产文件或测试。当前工作树仍有其他协作者的 dirty 内容；`scripts/player.gd`、`scripts/game_root.gd`、`scripts/equipment_rules.gd`、面板文件、特技巧规则文件和 `assets/data/equipment_special_rules.json` 与固定提交字节相同；初查把 `scripts/player_state.gd`、`scripts/mystery_equipment_instance_rules.gd` 的 Git index／换行差异误认为内容不同。主控私有 index 对照证实二者忽略行尾后语义差异为0，神秘规则正式 Git blob 一致；证据 `outputs/wake_drop_v108_review_followup_20261009/EQUIPMENT_SOURCE_IDENTITY.json`。以下判断仍绑定固定提交，未发现这些改动丢失。

## 结论标记

- **静态链闭合**：能从正式入口追到唯一状态所有者和消费者，但不等于当前源码阶段的原生或设备 PASS。
- **需运行核验**：静态链存在，仍缺异步时序、自然输入、重载或边界证据。
- **覆盖缺口**：在固定源码中未找到足够的正式消费者或关键合同证据。
- **已证实 BUG**：本轮没有把历史报告或脏工作树差异升级为此级别。

## 唯一状态所有者与共用变更边界

装备实例、槽位、耐久、装备交易 revision、技能栏绑定和 `computed_special_effects` 的唯一权威是 `PlayerState`。`equip_inventory_index()` 从背包记录解析 catalog、校验职业/性别/需求/神秘实例、写入槽位，随后 `recalculate_stats()`、`_commit_save()`，保存失败回滚原 inventory/equipment/cursor/bindings，再发 `inventory_changed`、`equipment_changed`、`profile_changed`（固定源码 `scripts/player_state.gd:3060-3155`）。`unequip_slot()` 对称执行并在成功后发同一组信号（`:3158-3206`）。这使特殊效果不会只在 UI 中改变；但异步保存失败、重入观察者和重新选择角色仍应由专项运行证据确认。

存档加载在 `scripts/player_state.gd:6964-7135` 校验 profile、身份、物品文档、共享仓库、背包与 `migrate_equipment_slots()`，恢复 equipment、inventory、skill progression、技能栏和 quick item slots；加载尾部还需确认固定提交是否完成一次 stats projection（固定实现的效果最终由正常启动/选择角色链重算）。装备效果本身不应写进 learned progression：`has_special_effect()`（`:3931-3932`）只读重算投影；`equipment_granted_skill_ids()`（`:3950-3972`）只从当前有效穿戴实例派生；`_prune_unavailable_equipment_skill_bindings()`（`:3998-4010`）负责卸下/损坏后的绑定清理。

## 分项核查

### 1. 复活戒指：300 秒、经验与正常死亡

**静态链闭合；关键时序需运行核验。** `assets/data/equipment_special_rules.json` 的 `rules.revivalCooldownMs=300000`，`EquipmentRules.revival_cooldown_ms()` 在 `scripts/equipment_rules.gd:431-433` 读取。致死结算在固定 `scripts/player.gd:1114-1129`：只有 HP 已为 0、`has_special_effect("revival")` 且当前 actor 的 `_last_revival_at_ms` 已过 300 秒才原地恢复满 HP，并消耗 `PlayerState.damage_special_effect_item("revival")`；该字段是 actor 内存状态（`:164`、`:1126`），不是存档字段。

正常死亡分支在 `player.gd:1130-1158` 设置 `_dead`、死亡 lifecycle generation、清 poison、关闭已提交动作；正式死亡通知由 `scripts/game_root.gd:6891-6904` 接收并调用 `PlayerState.apply_death_experience_penalty()`（`player_state.gd:2992-3006`）。因此“戒指自动复活不扣经验、普通死亡照旧”在源码分支上成立：经验扣除只在自动复活分支失败后到达 death boundary。GameRoot 的 UI 城镇复活另走 `game_root.gd:6948-7006`，不是戒指复活。

**风险/缺口：** `_last_revival_at_ms` 随 actor 重建回到 `-300000`，未见持久化；死亡/换图/重建后是否应保留 300 秒是产品边界而非可静态推断。自动复活分支不执行普通死亡分支的清毒；已有历史测试未先种毒，不能证明“带毒时复活后的毒状态”。

**最小验证：** 同一固定输入依次覆盖无戒指致死（经验下降）、有戒指首次致死（HP/死亡状态/经验/耐久）、300 秒内第二次致死（不得再次戒指复活）、超过 300 秒再次致死、存档重载/actor 重建，以及带 poison 的自动复活。断言 committed hit 仍只消费一次耐久，死亡通知不得跨 lifecycle generation。

### 2. 麻痹戒指：普通 5 秒、精英/Boss 2.5 秒

**静态链闭合；真实命中生命周期需运行核验。** `game_root.gd:13340` 在成功 melee 伤害提交后检查 `PlayerState.has_special_effect("paralysis")` 和 `EquipmentRules.paralysis_succeeds()`，随后调用目标 `enemy.apply_control(EquipmentRules.paralysis_duration_for_classification(...))`。固定规则 `equipment_rules.gd:436-450` 明确 ordinary=5.0、elite=2.5、boss=2.5，并按 `anti_poison` 与随机 roll 决定成功。

**风险/缺口：** 静态未见 Boss 免疫或专属新冷却；卸下/零耐久只会阻止新触发，已提交的 control timer 是否按合同继续自然结束需运行确认。现有历史覆盖主要是概率纯函数，不等价于“装备→真实攻击→HP 提交→控制递减→卸下”的完整链。

**最小验证：** 用普通、精英、Boss 三个真实分类，固定 RNG 覆盖成功/失败；检查 `control_time` 初值和逐物理帧递减、已提交控制在卸下后不被撤回、零耐久不再产生新控制、目标反毒属性改变分母但不改变分类时长。

### 3. 传送/防御/火焰戒指：授予、移除与快捷栏

**静态链闭合；异步保存和真实输入需运行核验。** `PlayerState.recalculate_stats()`（固定 `player_state.gd:3569-3748`）每次从有效正耐久装备重建 `computed_special_effects`；`equipment_granted_skill_ids()`（`:3950-3972`）只输出当前有效的登记装备技能，未写入 learned skills。装备/卸下事务和保存回滚见 `player_state.gd:3060-3206`。技能面板 `scripts/skill_panel.gd:523-565` 依据 `available_skill_ids()` 重建装备赋予行；绑定清理由 `player_state.gd:3998-4010` 和技能栏恢复链负责。传送/防御/火焰的正式动作消费者在 `game_root.gd` 的特装 action handlers：传送走连续 `test_move` 碰撞路径，防御走正式 `restore_health`，火焰走正式火球投射物/MP 路径。

**风险/缺口：** 这些 handler 的存在不等于 UI、死亡态、换图态和保存失败重入均已核验；特别是“赋予技能”与“旧特装按钮”是两条边界，不能仅凭有火球生成就称 canonical learned skill 已改变。快捷栏需验证卸下/零耐久后绑定清空且不会在 save/reload 再出现。

**最小验证：** 每件装备分别穿戴→确认 `equipment_granted_skill_ids()`/技能面板/快捷栏→释放正式动作→卸下→零耐久→重载；断言 available skill 与绑定同步消失，learned skills 不变，保存失败回滚不留下半套槽位/绑定，传送碰撞、治疗公式、火焰投射物与 MP 消耗保持原合同。

### 4. 隐身戒指：破隐、脱战恢复与卸下

**静态链闭合；combat-set 异步边界需运行核验。** `Player.apply_stealth()`/`break_stealth()`/`is_stealthed()` 位于固定 `scripts/player.gd:1851-1889,2000-2004`。攻击提交（约 `player.gd:489`）和技能提交（约 `:612`）调用 `break_stealth()`，只设置 `_stealth_break_override`，不删除装备效果。GameRoot 每 `_process` 调用 `_recover_equipment_stealth_if_out_of_combat()`（`game_root.gd:8376-8381`），仅在敌方 target 集合为空、玩家未死亡、无 pending action/attack timer 时调用 `recover_equipment_stealth_after_combat_exit()`；装备已卸下时清除 override/time，否则重新启用装备隐身。`recalculate_stats()` 的正耐久/卸下/损坏投影是该链的状态源。

**风险/缺口：** 真实 target 集合的最后一个成员何时移除、死亡/换图/tree-exit 是否与恢复调用同帧，属于异步时序；不能用一个 `stealth_time` 单元测试替代。卸下不应清掉其他来源的有效 stealth，这是需要明确断言的边界。

**最小验证：** 穿戴立即隐身；攻击和技能分别破隐；target 集合含一个/最后一个敌人时分别不得/应恢复；卸下、零耐久、死亡、换图、tree exit、重新穿戴逐项检查；恢复期间新 target 或 pending action 必须阻止恢复，恢复后不产生第二个战斗时钟。

### 5. 技巧项链：随机允许技能 +1

**静态链闭合；自然掉落与存读需运行核验。** 固定 `scripts/equipment_random_special_instance_rules.gd:5-119` 将 item 250 绑定到固定 contract、17 技能池、稳定 drop key digest；`validate_technique_instance()` 拒绝错误 item/count/roll/skill/value，`technique_skill_level_modifiers()` 只产生对应 `skill:<id>` 的 +1。`player_state.gd:3659-3660` 仅在有效正耐久装备且 validator 通过时加入 modifier；`effective_skill_level()`（`:3935-3945`）又要求技能已经 learned，装备不会教会未学技能。详情展示在 `item_detail_presenter.gd:468-478`。

**风险/缺口：** legacy 无 roll 实例按规则仍可加载兼容；这不是新掉落“已随机”的证据。需区分 17 池固定映射、旧存档兼容和跨职业/未学习过滤，不能把面板文本当运行效果。

**最小验证：** 固定多个不同 drop key 检查只落在 17 池且 reload 不重抽；篡改 digest/skill/value/item/count 必须拒绝；已学目标 +1、未学目标仍不可用、跨职业目标不增加；卸下/零耐久/重载保持同一 roll。

### 6. 神秘 218/219/220：随机属性、对应需求、无随机诅咒

**静态链闭合；source/生成/重载需运行核验。** 固定 `scripts/mystery_equipment_instance_rules.gd:4-181` 以 `equipment.mystery_random_stats.v1` 和 `assets/data/mystery_equipment_random.source.json` 作为 authority；`create_roll()` 按稳定 digest 生成 defense/magic defense/attack/magic/tao 五类随机值，并生成 family-specific requirement；`validate_roll()` 做严格 contract、digest、stats、requirement 比对；`modifiers()` 只把有效 roll 转为 additive modifiers。`EquipmentRules.requirement_for()`（`equipment_rules.gd:168-173`）消费实例 requirement，`player_state.gd:3707-3711` 消费 modifiers。代码路径没有把 mystery roll 转成 curse/lock/water chain，静态支持“无随机诅咒”。

**风险/缺口：** 本文件当前工作树与固定提交不同，不能用 dirty 文件结果替代本审计；固定提交还需确认源 JSON 与生成器/掉落入口的同一 source binding。普通小极品/锻造 modifiers 是另一层，不能代替 mystery contract。需求优先级（family、升级点数、职业属性）需运行覆盖。

**最小验证：** 真实生成 218/219/220 三 family，保存/重载后 roll、digest、requirement、五类 modifier 字节等值；篡改任何一项应拒绝装备；检查实例没有 curse/lock/water mutation，装备面板显示实际 roll 与对应需求。

### 7. 实际装备面板特殊属性展示

**静态链闭合；视觉/UI运行核验缺失。** `item_detail_presenter.gd:468-505` 按 item 250、隐身、麻痹、复活、传送/火焰/防御、护身、超负载、魔血/虹魔分支生成特殊描述；`:573-575` 还把有效 mystery roll 的 modifiers 纳入详情。`inventory_panel.gd:563-580` 在装备槽刷新时以正式 item record 生成 tooltip；`:602-616` 使用 `PlayerState.computed_stats`，展示 HP/MP/攻防/幸运/躲避/速度/暴击/负重等。`skill_panel.gd:523-565,600-641` 重建装备技能卡并显示 “装备赋予/可用” 状态。

**风险/缺口：** 静态只能证明字符串和 stats 消费者存在；不能证明所有特殊实例、零耐久、装备切换、面板重开、窄屏/本地化文本均实际显示且不残留旧行。面板显示“技能 +1”也不等于技能已学会，当前实现明确区分。

**最小验证：** 逐件打开 inventory detail/tooltip、character stats、skill panel，覆盖 valid/invalid mystery roll、技巧已学/未学、装备→卸下→零耐久→重开面板；断言旧 item 行不残留、特殊值与 `computed_stats`/`equipment_granted_skill_ids()` 一致，保存重载后仍一致。

## 固定源与复用边界

历史 `docs/review/special_equipment_20261008/FINAL_RESULT.md`、`SPECIAL_RING_CONNECTION_AUDIT.md` 和相关 receipts 可作为已有专项的来源线索，但它们混合旧源码阶段，不能替代本固定提交的证据。尤其历史标注的 PASS 只覆盖列明场景；本审计把真实麻痹命中、带毒复活、异步 stealth 集合、跨重载/损坏快捷栏和 mystery source binding 重新列为需运行核验或覆盖缺口。当前不提交、不运行、不把静态链升格为整模块 PASS。

## 固定提交源码指纹

以下 SHA256 是对 `git show ba97849b:<path>` 原始字节计算，避免把当前工作树 dirty 文件误当成审计输入：

| 固定路径 | SHA256 |
|---|---|
| `scripts/player.gd` | `01a04c3c5bab56e5507d730960531aef7aa403b08ffd788d6180d5be1162f275` |
| `scripts/player_state.gd` | `13cccb4cff55eda54c858c69ea8a0da16c33af44f19ec43b7199cf3ddf4d80a6` |
| `scripts/game_root.gd` | `d3ed6e93748c131106e589e84e08e01e22a94c6a8509d5219c283281f071d694` |
| `scripts/equipment_rules.gd` | `ac23080828818c09e8e812f3e668a2b2c4b0a533f6db4184dc47d6de2e5eccda` |
| `scripts/item_detail_presenter.gd` | `5f952f7cf7f3fd1ae6a5ff4ebc6157d5db197957d05de1e2234131de28700ed2` |
| `scripts/inventory_panel.gd` | `391a52ae236769a188a3673353c95a1e5a9b70713c565443235951efa734f392` |
| `scripts/skill_panel.gd` | `13ca0c09cfda62c86a9f68cbd470eca3b67113bd8bb999a5078c0dc3f4e5c5a3` |
| `scripts/mystery_equipment_instance_rules.gd` | `c65e6d3feda7f3b1f5f0dbecd23876e1ff88c8fb3ddf5e11dfde81ce7065094c` |
| `scripts/equipment_random_special_instance_rules.gd` | `63497cf958c1918872667310c8f9bd6a4822f215747072556ad70e60ba8c46a1` |
| `assets/data/equipment_special_rules.json` | `e82342b62319038b926b50e02430bb1f044551615eb22b62bef214aa1e43f7a8` |
| `assets/data/mystery_equipment_random.source.json` | `a9014c9c8bca1b674192e16766d0e0c7e716e4f437ab72da7d0a5ab515cb2903` |
