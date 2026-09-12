# UI Latency 闭环 · 两项生产发现（主控裁决用）

日期 2026-09-12 · 探针 v5 · test_mode=false · 合法 seed profile=1789194448_8760 · 真实 Input.parse_input_event 全程

## 实测 PASS（会话 JSON：probe_v3/ui_latency_probe_v2.json，会话 15）
- **buy：6/6 PASS**（cold 52.5ms；warm 47.5-53.3ms；金币每笔 -1210 精确；四轮会话一致复现）
- **sell：5/5 PASS**（cold 50.0ms；warm 49.3-53.9ms；金币每笔 +605 精确；修复=网格刷新后行按钮循环内重定位）
- **二进程 reload：PASS**（gold 675195 与会话终值精确一致，武器/物品一致；sidecar save_exists=false 为 probe 自身 globalize_path 用法错误，非游戏缺陷）

## 发现 1：桌面端背包"装备/卸下"操作入口在生产中不存在（有意禁用，非缺陷回归）
只读证据链（scripts/inventory_panel.gd）：
- L45 `const CONTEXT_MENU_ENABLED := false`
- L94-96 注释明示 "Production policy: the long-press context menu is intentionally suppressed."
- L1068-1071 `_context_menu_allowed()` 依 `_context_menu_policy.enabled=false` 直接返回 false →
  `_on_long_press_timer_timeout`（L1062-1065）永不弹菜单
- 备用 `action_button`/`unequip_button`（L72-73、L276-281）已创建但从未连接/显示（死变量）
- 双击装备物品（L986-990）仅 `_select_inventory_item` 选中，不执行穿戴
- 探针已满足全部真实输入条件：面板经生产 `_toggle_inventory` 打开、单元格有物、长按 1.17s（>0.48s 阈值）、
  合成事件 device=0 非 emulation、无拖动取消
结论：probe 无法触发是**生产策略性关闭**，属产品入口缺失/待定功能，按主控指令不修生产，交主控裁决
（桌面装备功能当前如何触达？是否本就仅移动端/后续版本开启？）。

## 发现 2：仓库存入执行了但 transferred=0（输入链完整，玩法规则层待确认）
只读证据链（scripts/warehouse_panel.gd L912-936 + probe wh_diag 行）：
- 探针真实点击 bag_grid 单元格 ItemButton（真实选择路径：button.pressed → _select_grid_button）
- wh_diag：`_active_selection_side="bag"`、`selected_bag_indices.size()=1`、`deposit_button.disabled=false`
  → 选择成功、按钮可点
- 点击后 fb=139ms：`_deposit` 确实执行（L923 set_button_feedback BUSY 即反馈来源），
  但 `PlayerState.deposit_to_warehouse_batch` 返回 transferred=0（物品数量不变）
- 可能原因（未验证，交主控/后续专项）：消耗品是否允许入仓、stash 当前页空位
  （`_free_slots_on_current_page`）、`_sanitize_transfer_selections` 清洗条件
结论：UI 输入链 PASS（选中→启用→执行→反馈），转移结果 0 属玩法规则判定，需专项确认；
withdraw 同理未达。

## 状态总表
| 动作 | 状态 |
|---|---|
| buy | PASS（4 会话一致） |
| sell | PASS（5/5） |
| equip/unequip | NOT_RUN（生产策略禁用入口，见发现 1） |
| warehouse deposit/withdraw | NOT_RUN（输入链 PASS，转移 0 待玩法确认，见发现 2） |
| persistence reload | PASS |
| autosave 30s 落盘瞬间计时 | NOT_CLOSED |
