# 特殊戒指连接审计

2026-10-08更新：以下为改动前审计，不代表新行为。指定特戒修复、真实GameRoot命中/控制分类、自动复活/经验、隐身有效状态及真实脱战、三个装备技能和技能面板真实配置的当前证据见[特装/HUD最终交接](../special_equipment_20261008/FINAL_RESULT.md)。旧60秒/统一5秒/点击特装/隐身重穿断点由新实现覆盖；actor冷却持久化、带毒复活等未授权扩展保持原实现并保留原覆盖边界。

核验日期：2026-10-07；当前分支 `codex/integration`，HEAD `215f0b2f651a51e6855ee813ddd99221690311a1`，包含本轮其他工作人的未提交改动。此审计只读源码、配置和已有日志；没有更改生产或测试，没有运行 Godot。源码连接确认不等于本轮原生或设备通过。

## 当前结论与身份

8 种特殊戒指都有明确运行配置和正式消费者；复活和麻痹已接入真实伤害路径。稳定身份在 `assets/data/runtime/entity_registry_v1.json:2659` 起登记，属性主源是 `assets/data/equipment_attribute_master.json:9907` 起。当前运行配置是 `assets/data/equipment_customization.json:5-12`；主表的描述文字本身不是执行逻辑。

| 名称 | 稳定 ID | 主表起始行 | 等级需求 | 最大耐久 | 正式消费者与当前行为 |
|---|---|---:|---:|---:|---|
| 麻痹戒指 | `hc.item.000252` | 9907 | 16 | 5 | `scripts/game_root.gd:12881`：正式 melee 物理命中提交成功后，概率 `1/max(1, enemy.anti_poison+5)`，基础 20%，调用 `enemy.apply_control(5.0)`。无专属冷却或该处 Boss 免疫判断。 |
| 隐身戒指 | `hc.item.000253` | 9971 | 12 | 4 | `scripts/player.gd:1920`：有效装备提供隐身；`scripts/enemy.gd:2972` 等感知入口消费，反隐身怪物可识别。攻击／技能提交打破隐身。 |
| 传送戒指 | `hc.item.000254` | 10029 | 12 | 5 | `scripts/game_root.gd:7885,7927`：“特装”沿朝向依次尝试 5.625/4.5/3.375/2.25/1.125 GU；`test_move` 全段原生碰撞通过才位移。无 MP 消耗或该 helper 的专属冷却。 |
| 防御戒指 | `hc.item.000255` | 10087 | 16 | 5 | `scripts/game_root.gd:7918`：“特装”消耗 5 MP，自疗 `max(12,int(level/2)+tao_max*2)`。正式 `restore_health` 拒绝已死亡玩家回血。无该 handler 的专属冷却。 |
| 复活戒指 | `hc.item.000256` | 10151 | 16 | 5 | `scripts/player.gd:1074`：致死 HP=0 且距上次触发 ≥60000 ms，原地满 HP，消耗 1 显示点耐久；触发复活的物理击继续结算受击耐久。符合条件时不掷概率。 |
| 护身戒指 | `hc.item.000257` | 10220 | 16 | 5 | `scripts/player.gd:1038`：最终伤害以 `round(damage*1.5)` MP 抵偿；MP 不足则耗尽，并将欠付部分按 1.5 还原为 HP 伤害。无随机或专属冷却。 |
| 超负载戒指 | `hc.item.000258` | 10284 | 16 | 5 | `scripts/player_state.gd:3713`：重算时穿戴／手持／背包三项最大负重各 ×2，不逐戒指叠乘。 |
| 火焰戒指 | `hc.item.000259` | 10348 | 16 | 5 | `scripts/game_root.gd:7890`：“特装”消耗 5 MP，以当前 magic_min/max 掷伤害，生成 `wizard.fireball` 投射物，读正式火球射程。无该 handler 的专属冷却。 |

这些戒指无职业或性别锁。表中等级及耐久来自主表逐 ID 记录，而不是按名称推定。

## 配置、装备状态、卸下与损坏

`GameData.apply_equipment_customization()`（`scripts/game_data.gd:2322`）目前按名称键应用上述明确配置，然后 `:2602` 通过 `EquipmentRules.enrich_catalog_record()` 登记 catalog。效果配置仍标 `confidence:B`；`scripts/equipment_rules.gd:344` 对明确 `specialEffect` 优先读取，也保留 AniCount／名称候选兼容逻辑。不能声称逐件原服数据库映射已全部核实。

装备实例通过 `scripts/player_state.gd:3606` 的 `GameData.get_item_record(instance)` 按稳定身份解析 catalog；重算在 `:3563` 清空 `computed_special_effects`，`:3604` 跳过零 raw 耐久，`:3701` 登记有效效果，`:3913` 提供查询。

正式卸下在 `scripts/player_state.gd:3177` 清空槽并重算；存档失败回滚并再次重算。耐久耗尽在 `:4314` 重算。主动入口从 `scripts/hud.gd:409,2577` 订阅 profile_changed 更新；`scripts/game_root.gd:7880` 在点击时再次检查效果。卸下麻痹戒指阻止新触发，不撤销已经提交给目标、正在自然计时的控制。

## 当前实际边界；不自动改玩法

- **麻痹完整专项 MISSING**：`tests/equipment_special_effects_test.gd:37` 只检验概率纯函数两个 roll；未验证真实装备→近战输入→命中→控制持续时间→卸下后不再触发的完整链。`scripts/enemy.gd:7446` 撤销 pending 攻击、固定身体、设置 `control_time=max(old,seconds)`；`:7634` 自然递减。该消费者没有额外抗控或 Boss 分支。
- **复活冷却是 actor 内存字段**：`scripts/player.gd:149,1074,1084` 的 `_last_revival_at_ms` 未发现持久化；同一 actor 卸下重穿不重置，重新创建 actor 会初始化为立即可用。
- **带毒自动复活清理未被证明**：自动复活分支只恢复 HP／耗耐久；清毒在真正死亡的 else 分支 `scripts/player.gd:1099`。`tests/hc_monster_combat_r2/revival_durability_test.gd:81` 没有先种毒便断言 poison 为零，不能覆盖带毒复活。
- **隐身打破锁不会因重穿自动复位**：`scripts/player.gd:1803` 设置 `_stealth_break_override`；只有 `apply_stealth()` 明确清除。未发现装备变更清锁的消费者。卸下戒指不应误清其他来源尚有效的 `stealth_time`。
- **主动戒指规格与描述存在差别**：传送实际沿朝向短距位移，不是坐标／命令传送，该 helper 未检查地图禁止传送规则。火焰／防御直接调用 projectile／恢复入口，没有 canonical 技能准入或专属 cooldown。handler 本身不检查死亡／过图状态；UI 在这些状态是否可触发未实测，不能据此宣称玩家可以实际操作。
- 上述边界均为本次只读事实或覆盖缺口。冷却持久化、清毒、传送规格、主动技能节拍等玩法改变需用户决定，本次不实施。

## 本轮状态与历史 epoch 分开

本轮源码连接确认：**PASS（仅静态链路）**；原生专项：**NOT_RUN**；设备：**NOT_RUN**。没有构建、安装或性能采集。

| 现有精确 scene | 建议外层 runner deadline | 当前状态／范围 |
|---|---:|---|
| `tests/equipment_special_effects_test.tscn` | 60 秒（正式 main／完整 READY 的重场景） | **NOT_RUN**。综合被动、复活、零耐久；共享正式 READY helper 的生产 fail-safe 已是 60 秒，不表示启动 SLA 通过。 |
| `tests/equipment_special_phase2_test.tscn` | 30 秒（普通功能场景） | **NOT_RUN**。主动三戒指、魔血／虹魔、零耐久入口；源码只等待两个 process_frame 后访问 enemies，对现异步 bootstrap 的适配尚未复验。不得把等待失败自动判为戒指生产失败。 |
| `tests/hc_monster_combat_r2/revival_durability_test.tscn` | 30 秒（本地 Player 专项） | **NOT_RUN**。复活耐久和致死物理击受击耐久精确结算。 |

普通场景保持 30 秒，已知正式 main 重场景才采用 60 秒；外层 timeout 不改变内部业务 deadline。主控可按统一冻结安排集中运行。本审计没有运行这些场景。

历史证据：

- `equipment_special_effects_test`：2026-10-03，旧 HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`，invocation `8f14d68e-0013-4b4d-8c8b-562fcc13feb6`，原生 **PASS**／退出0／无日志错误；receipt `outputs/test_logs/runner_results_adhoc_20261003_195109_021_1484.json`。覆盖超负载、隐身、护身、复活首次／60秒冷却／耐久和零耐久撤销；麻痹仅概率函数。
- `revival_durability_test`：2026-10-04，同旧 HEAD，invocation `c8e00de8-003f-410a-bdca-1fe4b5fcf8fb`，原生 **PASS**／退出0／无日志错误；receipt `outputs/test_logs/runner_results_adhoc_20261004_011017_289_12172.json`。精确 raw 耐久 `5000-1000-5=3995`。
- `equipment_special_phase2_test`：`outputs/test_logs/equipment_special_phase2_test.stdout.log`（2026-10-02）有 PASS 标记；本次未找到对应完整 receipt，源码／invocation 绑定 **MISSING**。不升格为当前通过。

当前专项源码 SHA256（只读采集，用于与统一 runner 冻结对照）：

| 文件 | SHA256 |
|---|---|
| `tests/equipment_special_effects_test.gd` | `9BD008A9E540F8486CFDA1D39B61BC3199C5074BE65F19D4783C71287801453F` |
| `tests/equipment_special_phase2_test.gd` | `E3B60C0CF5727DD8D76E159D7257596F4EABCE26F2EBF5F9733C6DB90063EE7B` |
| `tests/hc_monster_combat_r2/revival_durability_test.gd` | `7BF3876A7DF1B3F4D56F0D1B4AC8F632819316E2AD39EBDD666AED3418D00678` |

## 补麻痹完整专项的现成入口与成本（方案，未写测试）

最合适的既有真实输入 fixture 是 `tests/framework/feature_melee_ticket_paths_test.gd:23,58`：`FormalWorldSkillFixture.prepare_target()` 经正式地图发布产生稳定 spawn_slot 的目标，再 `player.request_attack_toward()` 接受真实 action configuration lease，等待实际释放，检查真实 HP 提交。其观察 Root 在 `tests/framework/fixtures/lease_probe_root.gd`，不是替换命中消费者；正式 fixture 入口在 `tests/helpers/formal_world_skill_fixture.gd:74,94`。既有内部 READY 20 秒、单次释放3秒和 republication5秒均不能因新专项顺便放宽。

建议未来复用正式目标发布和输入→release→HP 链，使用稳定 `hc.item.000252` 实例，通过正式装备／卸下事务；在不改生产概率的条件下用确定的测试 RNG 种子覆盖触发／不触发，并检查 `control_time`、pending 攻击撤销、真实移动被控、自然约5秒恢复、卸下和零耐久后无新触发、已提交控制不被卸下撤回。需要绑定 producer／action／源码／native receipt。种子必须针对真实随机消费序列核对，不能只用纯函数 roll 代替真实 melee。

成本：一套新增 .gd/.tscn 专项，约4—6个确定性子案；建议正式 main 重场景外层60秒，保留原内部 deadline。无需改变怪物数量、伤害或碰撞，无需性能测试。应在主控集中测试前另行安排施工／冻结，本次只提交方案，不写新测试。
