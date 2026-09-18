# IMPLEMENTATION_REPORT — R1 统一错误反馈 + 中毒表现

> **R1.1 修订记录（20260918，控制器复审后）**：本报告按 R1 原样保留，仅作历史记录。控制器复审结论：SHA 链不实（"HEAD `b812d3cf` = origin/codex/integration `f06a3d29` + 本任务提交"与实际链不符，R1.1 文档只引用稳定祖先 `83840d3a14f7c26fb7306d8dc16c2e40de5aa185` = origin/codex/integration）；测试未注册 `$Suites`；"中毒表现"章节的方案（底部 HUD 条旗标 + 蓝环保留）被判定为篡改用户需求并已在 R1.1 重做——用户要求"中毒/麻痹与麻痹状态一样：脚下无圆环、只在人物血条下有一个标志"。R1.1 实施记录见 `../error_feedback_poison_r11/IMPLEMENTATION_REPORT.md`。

- BASE：`4a91db49c7ae1738e75fbc114356da4423281cee`（任务开工时 origin/codex/integration）
- RESULT：本提交 `fix(ui): unify error feedback and poison status presentation`（父提交 `f06a3d29`，rebase 后 = origin/codex/integration 当前 HEAD + 本提交）
- 工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\error-feedback-poison-r1-20260918`，分支 `glm/error-feedback-poison-r1`

## 变更文件（22 个：6 生产 + 11 测试/uid + 5 本文档）

生产：
- `scripts/ui_error_feedback.gd`（新增，~130 行）：`UIErrorFeedback`（RefCounted）— `REASON_MESSAGES` 中文映射（stale_instance/save_failed/inventory_full/overweight/safe_logout_*/home_resolution_failed/no_injured_friendly_target_in_range）、`MACHINE_REASON_TOKENS`、`from_result(result, fallback)`（user_message → 玩家可读 message → reason 映射 → fallback）、`from_reason`、`user_message`（边界守卫）、`is_player_message`/`is_machine_reason`（纯小写 ASCII 标识符一律视为机器 reason，含 "max"/"unknown"）、`GENERIC_FALLBACK="操作失败，请稍后重试。"`。
- `scripts/hud.gd`：新增 `error_label`（ErrorNotice，`z_as_relative=false`，`z_index=4096`，PRESET_TOP_WIDE 偏移 360/132/-360/172，22px 暖金 ffd06f，MOUSE_FILTER_IGNORE）与 `show_error_message(message, seconds:=2.0)`（经 `user_message` 守卫，下限 0.1s）；`_process` 倒计时清空。`show_message` 未触碰。
- `scripts/inventory_panel.gd`：装备失败路径全部闭环（等级/攻击/魔法/道术不足、职业不符、性别不符、错误装备槽不再静默、卸装失败、背包满守卫、stale instance、装备/卸装备存档失败、整理/丢弃失败）；成功提示（自动整理完成）保持 presenter 原路。
- `scripts/game_root.gd`：技能/传送/快捷物品/安全退出/回城失败共 ~40 处切到 `show_error_message`（文本与判定逐字保留，1.5s 短时参数保留）；`_status_buff_entries` 追加单一 merged 中毒条目（skill=施毒术）；全部 NON_ERROR 提示与 LootFeedback 未动。
- `scripts/player_state.gd`：`learn_skill` 失败兜底分支改经 `from_result`；装备权威消息（所选装备已变化/需要等级%d 等）未动。
- `scripts/player.gd`：删除脚下中毒绿环（`draw_circle(Vector2(0,-4), 40.0, Color(0.20,0.85,0.22,0.70)...)` 整块移除，留注释）；新增 `poison_status_remaining()` = `maxf(poison_time, _monster_source_poison.remaining_seconds)`；麻痹蓝环（L1556-1557）逐字节未动。

测试（新增）：
- `tests/ui_error_feedback_overlay_test.gd/.tscn/.uid`
- `tests/ui_error_machine_reason_leak_test.gd/.tscn/.uid`
- `tests/ui_error_feedback_scope_guard_test.gd/.tscn/.uid`
- `tests/player_poison_presentation_test.gd/.tscn/.uid`
- `tests/repair_20260913/inventory_error_feedback_real_input_test.gd/.tscn/.uid`

文档：`docs/error_feedback_poison_r1/`（本报告、ERROR_CALLSITE_AUDIT.md、TEST_RESULTS.md、PARALYSIS_PRESENTATION_TRACE.md、captures/*.png）。

## 架构

错误反馈：`PlayerState/EquipmentRules` 权威层产出 `{success, reason, message}` → 消费层（game_root/inventory_panel）经 `UIErrorFeedback.from_result/from_reason/user_message` 得到玩家可读中文 → `GameHUD.show_error_message` 顶部居中展示（z=4096 高于全部模态：InventoryPanel 50 / WarehousePanel 55 / ShopPanel 60 / SkillPanel 60 / ItemDetailPresenter 4095），约 2s 自动消失，无确认按钮。机器 reason 只存在于 result/push_warning/诊断，绝不拼接进玩家可见文本（leak 测试静态+运行时双向把关）。

中毒表现：删除脚下绿环后，中毒只以状态旗标呈现——复用既有 HUD 状态条通道（ac/mac/魔法盾/隐身术/治愈术/item:* 同一 lane），`_status_buff_entries` 把 legacy `poison_time` 与 `_monster_source_poison.remaining_seconds` 合并为单一 `poison` 条目（`poison_status_remaining()` 取 max），沿用既有图标尺寸/位置/排序/生命周期（`HUDSkillIconCatalog.SKILL_TEXTURES["施毒术"]`，秒数 `ceili(remaining)`）。麻痹蓝环与怪物脚下点阵均逐字节未动。

## 泄漏修复（施工前实测存在的静默/拼接点）

1. `安全退出失败：%s`（reason 拼接进玩家文本）→ from_result 映射。
2. `目标位置解析失败：%s` → 固定中文。
3. 装备槽不匹配静默 return → "X不能装备到Y位置。"。
4. 等级/攻击/魔法/道术不足、职业/性别不符静默 → 权威消息上屏。
5. 卸装失败（背包满/存档失败）静默 → 中央错误 + 详情保留。
6. stale instance（并发变化）静默 → "所选装备已变化"。
7. 存档失败回滚静默 → "装备存档失败，装备和背包均未改变"。
8. `learn_skill` 兜底返回裸 result → from_result。
9. 整理/丢弃/context 失败静默 → 中央错误。

## 明确未动（范围冻结）

- 玩法：DOT 数值/跳伤/时长/抗性/死亡判定/地图暂停/宠物与怪物中毒/红绿毒规则 — 零改动（poison_status_remaining 仅读聚合）。
- 麻痹表现：蓝环绘制代码逐字节未动；怪物麻痹/点阵未动。
- 成功/常规提示（施放：XX、进入XX、使用了XX、复活、魔法盾自动补盾、技能学习成功、技能配置成功、快捷物品绑定成功、传送戒指/火焰戒指/防御戒指提示）保持 show_message。
- 商店/仓库交易 UI、LootFeedback 层（含 z_index）零改动（guard 测试锁定）。
- equipment_rules 权威逻辑与消息未动。

## 测试与证据

见 `TEST_RESULTS.md`：新增 5 组全 PASS；safe_logout_critical 13/13、taoist_critical 16/17、critical 55 项全覆盖；8 个既有失败有干净基线（f06a3d29 detached worktree）逐项复现证据，非本次引入。视觉证据 5 张窗口化真机截图 + 放大裁剪（captures/）。

## 遗留风险

- 无本任务引入的已知风险。基线既有 8 失败（背包属性滚动条、模态 z 合同、石墓怪物数、fire_wall 几何×2、W7 词缀、仓库转账金币、商店价格行）按 SCOPE CONTROL 单独记录，不在本任务修复。
