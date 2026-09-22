# IMPLEMENTATION_REPORT — R1.1 玩家头顶状态标志 + 错误入口补完

- BASE：`83840d3a14f7c26fb7306d8dc16c2e40de5aa185`（= origin/codex/integration，含 R1 合并）
- RESULT：本提交（R1.1 关闭提交；合并后以 `git log` 实际哈希为准，本文档不预写哈希）
- 工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\error-feedback-poison-r11-20260918`，分支 `glm/error-feedback-poison-r11`

## 0. 任务来源：控制器对 R1 的复审结论

R1 复审判定 PARTIAL：SHA 链、merge/push 真实性、装备错误闭环、独立错误通道（ErrorNotice z=4096）、错误路径、shop/warehouse 未动、绿毒环移除——通过，保留，不回滚。中毒标记位置——失败，重做。用户原话："中毒脚下绿色圆圈去掉。和麻痹一样。只需要在人物血条下有个标志。做法与麻痹状态一样。" R1 保留蓝环并把毒旗标放进底部 HUD `TaoistDefenseBuffStrip` 属于范围误判。R1.1 按以下最终目标状态施工：

- 麻痹：脚下无蓝圈 / 人物血条下麻痹标志
- 中毒：脚下无绿圈 / 人物血条下中毒标志
- 两个共用同一个人物头顶状态标志系统；麻痹标志 + 中毒标志按固定顺序排列
- 两种状态都不再使用脚下圆环；不碰玩法计时和数值

## 1. 变更文件

生产（8）：

- `scripts/player_status_marker_strip.gd`（新增）：`PlayerStatusMarkerStrip extends Node2D`。血条下状态标志行，对齐怪物侧既有先例（`enemy.gd` `POISON_INDICATOR_DOT_RADIUS := 3.0` / `POISON_INDICATOR_DOT_CENTER_OFFSET_X := 5.0` / 血条底 +5.0）：点半径 3.0，槽位偏移 ±5.0，麻痹固定左槽 `Color(0.42, 0.62, 1.0, 0.90)`（原脚下蓝环同色，色彩连续），中毒固定右槽 `Color(0.36, 0.92, 0.28, 0.90)`（怪物毒点同色）。槽位固定不随另一状态缺席而重排。`active_status_markers() -> Array[String]` 固定顺序契约（["paralysis","poison"]）供测试；`_process` 仅在活动集签名变化时 `queue_redraw`；`current_hp <= 0` 时全部隐藏；只读 `control_time` / `poison_status_remaining()`，不写任何玩法状态。
- `scripts/player_health_bar.gd`：`_ready` 挂载 `PlayerStatusMarkerStrip`（名字 `PlayerStatusMarkerStrip`，位置 `Vector2(0, BAR_SIZE.y + STATUS_MARKER_ROW_GAP)`，GAP=5.0 对齐怪物点阵"血条底+5"先例），绑定父节点（玩家）为状态源；`layout_snapshot()` 新增 `status_marker_strip_position` 布局契约。
- `scripts/player.gd`：删除脚下麻痹蓝环绘制块（`draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)`）；R1 的中毒注释更新为双状态指向标志行。`poison_status_remaining()`、`control_time`、`poison_time`、`_monster_source_poison` 与全部计时/数值逻辑未动。
- `scripts/game_root.gd`：`_status_buff_entries()` 移除 R1 加入的底部条毒旗标条目（`"id":"poison"` 整块删除）；`_on_loot_collection_rejected` 改走 `hud.show_error_message(message)`（拾取被拒=操作失败）；修复油/战神油调用改用结构化结果并经 `_report_repair_oil_result` 分类（成功→通知通道，拒绝→错误通道）。
- `scripts/player_state.gd`：物品使用权威结构化——`use_inventory_index_result(index) -> {success, reason, message}`（新权威入口），`use_inventory_index` 保留为 String 兼容包装（消息逐字不变，`use_quick_item_slot` 与既有测试/调用方不受影响）；失败机器原因：no_item_selected / no_local_rule / weapon_required / effect_config_invalid / blessing_rng_not_ready / insufficient_items / not_usable / save_failed / weapon_not_damaged / blessing 与临时增益原因透传；`_use_weapon_repair_oil_item_result` / `apply_weapon_repair_oil_result`（String 入口 `apply_weapon_repair_oil` 保留为包装）；`_learn_skill_result`（`learn_skill` 保留为包装）；`use_quick_item_slot` 改用结构化结果判定 ok（替换原"消耗数量差"启发式；失败 reason 携带具体机器原因），修复原启发式无法区分"拒绝"与"无效操作"的缺陷；临时增益失败经 `UIErrorFeedback.from_reason` 得到玩家可读中文，消灭 R1 遗留的 `return str(buff_result.get("reason", ...))` 原因直通泄漏。
- `scripts/ui_error_feedback.gd`：`REASON_MESSAGES` 补 6 条临时增益机器原因映射：invalid_arguments→"物品效果参数无效，无法使用。"、contract_mismatch→"物品效果与当前规则不匹配，无法使用。"、duration_invalid→"物品效果时长无效，无法使用。"、buff_group_missing→"物品效果组缺失，无法使用。"、modifiers_missing→"物品效果数值缺失，无法使用。"、stat_not_allowed→"物品效果包含不允许的属性，无法使用。"
- `scripts/inventory_panel.gd`：`_on_context_action` "use" 与 `_activate_inventory_index` 两处改用 `use_inventory_index_result`：成功→保持既有 presenter 绿色通道；失败→保持选中与详情，经 `UIErrorFeedback.from_result(result, "使用失败，请稍后重试。")` 走 `_show_error_message` 错误通道。
- `scripts/hud.gd`：快捷栏空点击改走错误通道（文本逐字保留："快捷物品 %d 为空：长按槽位可从背包选择"）。

测试（4 改/新 + runner）：

- `tests/player_poison_presentation_test.gd`（重写）：反转 R1 锁定错误行为的断言——蓝环字面量必须消失、底部条不得有 `"id":"poison"`；新增标志行契约：真实 main.tscn 启动 9 组用例（legacy 毒/怪物源毒/双源合并/单源残留/全部结束/死亡清标志不动玩法/麻痹单标志/麻痹+中毒固定顺序/干净态），固定槽位几何断言（麻痹 x<0、中毒 x>0）。
- `tests/player_health_bar_status_marker_test.gd/.tscn/.uid`（新增）：血条挂载、行位置 = `BAR_SIZE.y + 5`、layout 契约、未绑定源安全空、绑定源五态生命周期（毒单点/怪毒单点/双态固定顺序/毒止麻留槽/死亡全隐不写计时）、真实父子绑定路径。
- `tests/ui_error_feedback_scope_guard_test.gd`（更新）：新增 R1.1 路由门禁（拾取拒绝/修复油分类/快捷栏空/use 结构化消费 2 处/success presenter 保留 2 处/from_result 边界），通道计数阈值按现状校准（error≥40、message≥14）。
- `tests/ui_error_machine_reason_leak_test.gd`（更新）：6 条临时增益原因映射运行时断言 + player_state 结构化静态契约（result 入口、String 包装、`return str(buff_result.get("reason"...))` 禁绝、from_reason 边界、inventory_panel 消费契约）。
- `tests/hud_gothic_runtime_test.gd`（更新）：快捷栏空提示断言从 loot_label（旧 show_message 通道）改为 error_label（R1.1 错误通道），文本逐字不变；这是控制器点名的路由变更，生产契约已变，测试期望同步为新契约（非放宽：新增"不得再写入常规通知通道"反向断言）。
- `tools/run_godot_tests.ps1`：将 R1 遗漏注册的 5 个测试 + 新增标志行测试共 6 个注册进 `$Suites.critical`（此前"注册了新测试"为假，无长期回归门禁）。

文档：`docs/error_feedback_poison_r1/`（4 份 R1 文档顶部加 R1.1 修订记录横幅：SHA 链更正、未注册更正、中毒/麻痹表现误判更正；正文按 R1 原样保留作历史记录）；`docs/error_feedback_poison_r11/`（本文档、TEST_RESULTS.md、captures/）。

## 2. 架构契约

表现：状态源（player.control_time / poison_status_remaining，只读）→ `PlayerStatusMarkerStrip`（血条子节点，固定槽位点阵，死亡隐藏）→ 与怪物头顶点阵同一几何语言（3.0 半径 / ±5.0 槽位 / 血条底+5）。脚下蓝环、绿环代码均不存在；底部 HUD 条不再承载玩家麻痹/中毒。

错误反馈：权威层（player_state）产出 `{success, reason, message}`（message 恒为玩家可读中文）→ 消费层（inventory_panel/game_root/hud）成功走原通知通道、失败经 `UIErrorFeedback.from_result/from_reason` → `GameHUD.show_error_message`（z=4096 独立通道，位置与 R1 一致，屏幕上方居中，控制器裁定不改动）。机器 reason 只存在于 result/诊断，绝不拼接进玩家可见文本（leak 测试静态+运行时双向把关）。

## 3. 明确未动（控制器 PASS 保留项）

- R1 错误通道实现与全部既有错误路径、装备错误反馈闭环、ErrorNotice 位置与样式（匹配既有法术提示位置，非阻塞项维持现状）
- shop/warehouse 全部、LootFeedback 层自身反馈、玩法计时与数值（control_time/poison_time/_monster_source_poison 时钟、毒伤、技能效果）、怪物脚下点阵与控制环（enemy.gd）、存档格式、SHA 链（R1 历史提交不重写）

## 4. 范围外观察（不施工，仅记录）

- `player_state.apply_blessing_oil` / `apply_blessing_oil_with_rolls`：遗留 String 混合结果 API，无生产调用方（仅测试引用），未纳入本次结构化改造。
- 两个新发现的基线既有失败（见 TEST_RESULTS.md §4）：`quick_item_slots_test`（4 次升级假设与当前技能数据 max rank 不符）、`equipment_precise_durability_test` L180（木剑零耐久属性断言），均在干净 83840d3a 复现，与本次改动无关，未修改。
