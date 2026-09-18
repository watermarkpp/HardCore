# BUG-08 施工报告：祖玛休眠怪远程受击不反击 + 脚下白圈清理

日期：2026-09-18
分支：`codex/bug08-zuma-dormant-damage-wake`（已合并并删除）
工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\bug08-zuma-dormant-damage-wake-20260918`（已删除）
R1 closure：本报告提交同时包含 suite 注册与场景 G 增强（见文末 R1 章节）。

## 基线与最终 SHA

| 项 | 值 |
|---|---|
| AUDITED_BASE | `4a91db49c7ae1738e75fbc114356da4423281cee` |
| EXEC_BASE | `4a91db49c7ae1738e75fbc114356da4423281cee`（远端施工期间未前进，无需 rebase） |
| FIX_COMMIT | `08cec5fc8d620a7f16082e1573fe5f33064dd880`（核心修复，生产代码仅 `scripts/enemy.gd`） |
| REPORT/R1_COMMIT | 本报告所在提交（R1 closure：suite 注册 + 场景 G + 报告修正） |
| FINAL_INTEGRATION_SHA | 本提交即 `codex/integration` 最终 HEAD（push 后以 `git rev-parse origin/codex/integration` 核对一致） |

历史核对记录：`08cec5fc` push 后远端与本地均为该 SHA；随后报告/R1 提交前进，最终 HEAD 以本表为准。

注：主工作树 `C:\Users\Administrator\Documents\HardCore` 当时位于 `codex/wall-p1r-rollout-r2-r4` 且带用户未提交修改，按"保护现场"规则未触碰；`codex/integration` 实际检出于 `C:\Users\Administrator\Documents\hc-integration-v4`，合并/冒烟/push 均在该工作树完成。

## 根因

### 1. 远程受击不反击

`scripts/enemy.gd` 中 dormant 只有两个**接近唤醒**出口：

- 普通战斗路径（原 2490-2509 行）：`distance_gu <= wake_range_gu` 才 `dormant = false`；
- HC 路径（原 7724-7730 行）：同规则。

而伤害路径 `_apply_damage_core()` 只做 `_add_threat` → 扣血 → `_hc_received_damage`（后者对非 `_hc_standard_melee()` 怪直接早退）。于是：远程法术在 wakeRange 外命中 → 正常扣血、正常加 threat、正常受击事件，但 `dormant` 仍为 true → 移动/攻击全被 dormant 门禁锁死 → 玩家走进 wakeRange 后才突然苏醒追击。

### 2. 脚下灰白半透明圆

`enemy.gd::_draw()` 中存在 dormant 状态专属地面绘制：

```gdscript
if dormant:
    draw_circle(Vector2(0, -5), radius_px + 3.0, Color(0.52, 0.50, 0.46, 0.72))
```

祖玛雕像/卫士出生即 dormant，因此脚下始终叠加该灰色半透明实心圆（与正常暗色接触阴影重复，视觉上呈白圈）。

## 修改文件

| 文件 | 变更 |
|---|---|
| `scripts/enemy.gd` | 新增 `_wake_dormant_from_received_damage()`；接入 `_apply_damage_core()`；删除 `_draw()` 中 dormant 白圈绘制块（+33 / -4） |
| `tests/monster_dormant_damage_wake_test.gd/.tscn/.uid` | 新增回归测试（303 行，6 个场景） |
| `tests/monster_dormant_ground_marker_contract_test.py` | 新增白圈 source guard（4 用例） |

## 核心代码修改

统一契约：`proximity wake OR damage wake`。

```gdscript
func _wake_dormant_from_received_damage(attacker: Node2D, actual_damage: int) -> void:
	if actual_damage <= 0: return          # 无实际伤害不唤醒
	if current_hp <= 0: return             # 致死伤害直接走死亡流程，不进入战斗态
	if not dormant: return
	if _burrowed: return                   # 触龙神 124 burrow 机制保护
	if not _target_candidate_is_live(attacker): return
	dormant = false
	_retarget_timer = 0.0                  # 伤害已入 threat 表，由现有 retarget 决策选目标
```

接入点（顺序：`_add_threat` → 扣血 → 计算 `actual_damage` → damage wake → `_hc_received_damage` → HP UI / Boss / STRUCK）：

```gdscript
current_hp = maxi(0, current_hp - amount)
var actual_damage := hp_before_damage - current_hp
if actual_damage > 0 and is_instance_valid(attacker):
	_wake_dormant_from_received_damage(attacker, actual_damage)
	_hc_received_damage(attacker, float(actual_damage))
```

不直接 `target = attacker`；目标仍由 threat/stability/retarget 体系决定（场景 C 双向验证：高威胁挑战者可换目标、弱挑战者不可抢目标）。

## dormant ID 扫描结果

- 静态 dormant（`monster_behavior_profiles.json`）：153 祖玛雕像、155 祖玛雕像3、156-159 祖玛卫士系、160 祖玛教主（`zuma_dormant` / `zuma_guard_holy_word` / `w1_mixed_sculture_king_160`，均含 `dormant: true`，**未删除**）。
- 154 祖玛雕像0：退役来源为 `assets/data/vanilla_176/monsters.json` 中 `monsterId=154` 的 `recordStatus: "retired"`，并由 `tests/canonical_monster_variant_prune_test.py` 固定列入 P3C 退役 ID 集（不得进入 canonical active/animation/service universe），运行时 `setup()` 因 canonical catalog 无该活跃条目而 fail-closed。注意 `enemy.gd` 的 `RETIRED_SOURCE_ONLY_MONSTER_IDS` 常量仅含 `[71]`，与 154 无关。测试不覆盖 154、不恢复运行。
- 动态 dormant：124 触龙神（`burrowAmbush` 期间 `_burrowed=true, dormant=true`），受 burrow 保护条款覆盖。

## 白圈来源与影响面

唯一来源即 `enemy.gd::_draw()` 的 dormant 地面绘制块，按第 13 节要求**全局删除**（非按 ID 隐藏），今后新增 dormant 怪不会复现。未触碰：`monster_visual.gd` 接触阴影、黄色选中圈、毒提示（绿/红毒点）、控制/魅惑提示、Boss 预警 `_draw_boss_warning_ground_projection()`、坐标诊断 Overlay。

## 触龙神保护说明

`_apply_boss_rule()` 对 124 依据 `boss_service_rules.json` 设置 `_burrowed=true, dormant=true`；唤醒函数在 `dormant` 判定后显式 `if _burrowed: return`，禁止在该函数内出现 `_burrowed = false`。`emergeRange`/`healToFullOnEmerge`/`burrowAmbush` 配置与 `_load_zone` 的钻地浮现路径（原 2445-2465 行）零改动。测试场景 F 同时验证伤害入口与直接调用 helper 均保持 burrow。

## 新增测试

`tests/monster_dormant_damage_wake_test.gd`（stable monsterId，不依赖中文名）：

- 场景 A 出生休眠：153/155/156/157/158/159/160 全部 `assert(dormant)`；
- 场景 B 距离外受击立即唤醒：10 GU（> 全部 wakeRange：默认 190px/32≈5.94 GU、教主 64px/32=2.0 GU，且 ≤ leash 18 GU）；含接近对比断言（该距离首次警戒仍拒绝，仅伤害路径可唤醒）；断言扣血、`not dormant`、`_retarget_timer <= 0`、threat>0、`_retarget(0.0)` 后 `target == player`；
- 场景 C 不篡改目标系统：高威胁第二目标可经 threat 规则换目标、弱挑战者不可抢，证明无强制锁 attacker；
- 场景 D 零伤害不唤醒：`take_damage(0)` 后 dormant 仍 true、`_retarget_timer` 不变；
- 场景 E 致死伤害：`current_hp==0`、不进入战斗唤醒态（dormant 保持）、`_death_pending` 正常、无 target；
- 场景 F 触龙神保护：`_burrowed && dormant`，受击后与直接调用 helper 后均保持 burrow/dormant。

`tests/monster_dormant_ground_marker_contract_test.py`：禁色 `Color(0.52, 0.50, 0.46, 0.72)` 不存在；`if dormant:` 体内不得出现 `draw_circle`；正向断言 dormant AI/伤害唤醒/burrow/profile 数据仍在（不禁止 AI 中的 `if dormant` 判断）。

R1 新增场景 G（生产链集成）：`CombatRuntimeService.apply_enemy_direct_spell_damage(enemy, "wizard.lightning", 50, player, null, Callable(), ANTI_MAGIC_ROLL_SIDES-1)` 对 153/156/160 直接走真实服务结算链（`take_damage(final_damage, source_actor=player)`），断言结算成功、实际扣血、dormant 解除、threat 归属 player、retarget 后 target==player。参数确定性：三个目标的编译 `anti_magic_points` 均为 0，roll=SIDES-1 永不闪避；未传 MAC adapter 时 final_damage==raw_damage。

## 全部测试结果

| 门禁 | 结果 |
|---|---|
| Godot parse（`--headless --editor --quit`，全量导入+解析） | PASS，exit 0，0 SCRIPT ERROR（日志复查 0 命中） |
| monster_dormant_damage_wake_test（新，含 R1 场景 G） | PASS |
| monster_target_acquisition_test（含 ID 153 第一警戒范围） | PASS |
| monster_threat_animation_test | PASS |
| player_direct_spell_damage_test | PASS |
| player_enemy_struck_chain_e2e_test（STRUCK R1.3 链路） | PASS |
| monster_struck_visual_queue_test | PASS |
| hc_monster_ai/runtime_test | PASS |
| hc_monster_ai/w1_special_delivery_runtime_test | PASS |
| 正式 monster suite（R1 注册后全量） | 见 R1 章节 |
| 白圈 source guard（pytest） | PASS（4 passed） |
| zuma_area_test | **FAIL（基线预存，与本修复无关，见下）** |
| centipede_cave_test | **FAIL（基线预存，与本修复无关，见下）** |

最终树状态下在 bug08 工作树复跑：8/8 PASS（上述在册集合）。合并后于 `hc-integration-v4` 最小冒烟：`monster_dormant_damage_wake_test` PASS、`monster_target_acquisition_test` PASS。

### zuma_area_test / centipede_cave_test 失败定性（重要例外）

两项失败为**基线预存的过时测试**，与本次修改无因果关系，证据链：

1. **基线对照**：将工作树 `enemy.gd` 换回 `4a91db49` 原版（无本修复）运行 `zuma_area_test`，失败断言与数量完全相同（`祖玛地图659怪物数量不符`）；已还原并核对 diff。
2. **第二环境对照**：在 `hc-integration-v4`（同基线、暖缓存、无本修复）运行，同样失败。
3. **根因（探针实测）**：开机地图为 910001（比奇省·单机重制，82 个怪）；`travel_to_map(659/1378)` 后 `current_map_id` 仍为 910001——formal loader（FREEZE-P0.2/P0.3R）按 `map_runtime_release_registry.json` fail-closed 拒绝未发布地图。当前正式 registry 发布 **67 张** implemented_playable editor runtime 世界图（910001-910007 世界图、911xxx/912xxx/913xxx/914xxx-918xxx 副本区等）；旧 authored 地图 ID 659/1378 **不在 registry**，祖玛区域已迁移到 `913101-913106`，蜈蚣洞/死亡山谷区域已迁移到 `913201-913207`。两个测试的"旧图旅行+计数"假设被**有意的生产契约变更**淘汰。
4. **休眠内容已迁移且验证正常**：探针实测新世界 `913101`（mengzhong_zuma_temple_f1，盟重→祖玛寺庙）加载成功，40 个怪中 17 个 dormant（含祖玛雕像、祖玛卫士）——出生休眠契约在新世界+本修复下正常。
5. **回归价值已被新测试覆盖**：旧 zuma 测试对 BUG-08 的核心价值（祖玛雕像出生休眠 `assert(statue.dormant)`）由新测试场景 A 以 stable monsterId 全量覆盖。

修复该两项需按新世界契约重写其地图域断言，属 integration/maps 域独立任务，不在 BUG-08 范围（任务第 25 节明确禁止借本任务改地图数据/刷怪表）。

## 行为验收（实测）

- 祖玛雕像/卫士出生仍休眠，wakeRange 原值未动（`range_gu` 读取逻辑零改动），不主动乱跑；
- 玩家不攻击远距离经过：首次警戒仍按 viewRange 边界拒绝（场景 B 对比断言 + monster_target_acquisition PASS）；
- 玩家进入 wakeRange：原接近唤醒路径（2490-2509 / 7724-7730）逐字未改，正常苏醒；
- 法师 wakeRange 外直接攻击：首次实际伤害 → `dormant=false` → 攻击者已有 threat → `_retarget_timer=0` → 下次决策立即追击/反击（场景 B）；
- 多目标：仍由 threat/stability/retarget 决定，无强制覆盖（场景 C）；
- 触龙神：burrow 不被破坏（场景 F）；
- 视觉：dormant 白圈全局移除；暗色接触阴影/选中圈/毒点/控制环/Boss 预警全保留（diff 审查确认）。

## 边界声明

| 项 | 结论 |
|---|---|
| 是否修改 view range | NO |
| 是否修改 aggro | NO |
| 是否修改 wake range | NO |
| 是否删除 dormant profile | NO |
| 是否修改 STRUCK R1.3 | NO |
| 是否修改触龙神 burrow 规则 | NO |
| 是否修改 `monster_behavior_profiles.json` / `monster_runtime_authority_v1.json` / `monster_target_acquisition_policy.gd` / 技能距离 / 怪物速度 / 地图数据 / 刷怪表 | NO |

## 工作树清理

| 项 | 结论 |
|---|---|
| worktree 是否删除 | YES（`git worktree remove` + `prune`，`git worktree list` 已确认消失） |
| 临时分支是否删除 | YES（`git branch -d codex/bug08-zuma-dormant-damage-wake`，ff 已合并故安全删除） |

## 遗留风险

1. `zuma_area_test` / `centipede_cave_test` 为基线预存过时测试，需 integration/maps 域按新世界契约（release registry + 910xxx/911xxx 正式图）单独重写；在重写前它们对所有近期 integration 状态均失败。
2. DOT/poison（attacker=null）不会触发伤害唤醒——符合"有效攻击者"契约，祖玛无 DOT 来源，无实际影响。
3. 本次 0 伤害仍计入 threat 的既有行为未整改（任务明确不扩大范围）。

## BUG-08-R1 closure（复审后补充）

复审结论：核心修复 PASS，保留 `08cec5fc`，不需要重做。R1 只做闭环，不再触碰 `enemy.gd` 核心修复代码：

1. **长期回归门禁补全（P1）**：`tests/monster_dormant_damage_wake_test.tscn` 注册进 `tools/run_godot_tests.ps1` 的 `$Suites.monster`（此前只能 adhoc 手动运行，正式 suite 不会执行它）。注册后全量正式 monster suite 结果见下。
2. **场景 G（P2，已实施）**：新增生产法术链集成断言（`CombatRuntimeService` → `take_damage(final, player)` → damage wake → retarget），覆盖复审第 4 节验证过的真实 wizard.lightning 链路，防止未来 `source_actor` 传递回归。
3. **报告事实修正（复审第十六/十七/十八节）**：
   - 正式 registry 为 **67 张** implemented_playable 地图（原报告"8 张"为统计脚本误把数组属性当元素计数所致，已修正；659/1378 确不在 registry，祖玛迁移至 913101-913106、蜈蚣/死亡山谷迁移至 913201-913207 的结论不变）；
   - 154 退役来源改为 `monsters.json recordStatus=retired` + `canonical_monster_variant_prune_test.py`（`RETIRED_SOURCE_ONLY_MONSTER_IDS` 仅 [71]，与此无关）；
   - SHA 表改为 FIX_COMMIT `08cec5fc` + 最终 HEAD 以本报告提交为准。
4. **白圈 Python guard 保持 adhoc（P2 接受现状）**：仍为施工验收证据；如需长期 formal gate，可后续改写为 Godot .tscn 契约测试或建立 Python contract runner，不在本任务范围。

### 正式 monster suite 运行结果（R1 注册后）

`-Suite monster` 全量：**45/46 PASS**，新注册的 `monster_dormant_damage_wake_test` 在正式 suite 内 PASS（含场景 G）。

唯一失败：`monster_world_integration_test`（"ID 76 runtime did not expose the complete V505 source profile"，loot 契约断言）。基线对照：将 `enemy.gd` 换回 `08cec5fc~1` 原版复跑，同断言同失败——**基线预存失败**，且该测试本就在 monster suite 内（非本次注册引入），属 loot/数据域既有问题，与 BUG-08 的 dormant/wake/绘制改动无因果路径，不在本任务范围。
