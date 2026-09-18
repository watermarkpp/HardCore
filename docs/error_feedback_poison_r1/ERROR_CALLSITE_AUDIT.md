# ERROR_CALLSITE_AUDIT — R1 统一错误反馈施工审计

基线：`4a91db49c7ae1738e75fbc114356da4423281cee`（origin/codex/integration，rebase 后父提交 `f06a3d29`）。

分类定义：

- `ERROR`：玩家操作被拒绝/失败，必须给出玩家可读中文反馈 → 走 `hud.show_error_message(...)`（内部经 `UIErrorFeedback.user_message` 边界守卫）。
- `NON_ERROR`：成功/状态提示（施放、进入、复活、自动补盾、使用了 XX 等）→ 保持 `show_message` / 面板内提示原路，禁止迁移。
- `TRANSACTION`：商店/仓库交易面板内部的成交反馈 → 保持面板内既有展示，未触碰。
- `DEBUG_ONLY`：仅日志/诊断（push_warning / push_error / JSON），不进玩家 UI，未触碰。

路由说明：`show_error_message(message, seconds)` 只接受玩家可读文本；机器 reason 先经 `UIErrorFeedback.from_result(result, fallback)` 或 `user_message()` 映射/守卫。文本/判定保持原样，仅换通道。

## scripts/game_root.gd（消费 PlayerState/EquipmentRules/传送结果的一方）

| 位置（函数） | 消息 | 分类 | 施工前 | 施工后 | 改动 |
|---|---|---|---|---|---|
| `_report_safe_logout_error` | 安全退出失败 | ERROR | `show_message("安全退出失败：%s" % reason)` | `show_error_message(UIErrorFeedbackScript.from_result(result, "安全退出失败，请稍后重试。"), 2.0)` | 是（消灭 reason 拼接） |
| `_handle_home_resolution_failure` | 无法确定安全返回位置 | ERROR | `show_message("目标位置解析失败：%s" % ...)` | `show_error_message("无法确定安全返回位置。", 2.0)` | 是 |
| 技能释放失败系列（近战/施法/目标校验） | 附近没有可交互目标 / "%s为空" / 技能尚未学习 / 该技能已隐藏无法使用 / 技能动作或冷却尚未结束(×3) / 附近没有可治疗的友方 / 魔法不足 / 附近没有可冲撞的低级普通怪物 / 法术需要有效目标 / 目标超出该法术的有效范围 / 特殊装备已失效 / 前方没有合法传送落点 / 火球需要5点魔法 / 治愈需要5点魔法 / 锁定目标已失效技能未释放(1.5) / 技能释放失败(1.5) / 附近没有可用传送落点 / 目标被遮挡或已失效(1.5) / 技能栏为空 / 周围12/10格内没有可锁定目标 | ERROR | `show_message` | `show_error_message` | 是（文本逐字保留，含 1.5 秒参数） |
| 快捷物品绑定/使用失败 | result.message（可能有玩家可读文案） | ERROR | `show_message(... % ...)` | `show_error_message(UIErrorFeedbackScript.user_message(str(result.get("message", "..."))))` | 是 |
| 技能栏配置失败 / 技能栏配置未能保存 | 技能栏配置失败 / 技能栏配置未能保存 | ERROR | `show_message` | `show_error_message` | 是 |
| 传送/切图失败系列（12 处） | 传送条件已经失效（经 user_message 守卫）/ 目标地图投影暂不可用 / 地图数据不存在(×3) / 当前无法开始传送 / 当前地图投影暂不可用 / 传送节点端点不存在 / 传送节点尚未稳定 / 传送节点配置无效 / 目标地图或目标门点不可用 / 目标地图标识不匹配 / 目标门点坐标不匹配 | ERROR | `show_message` | `show_error_message` | 是 |
| 施法成功系列 | 施放：%s / 进入%s / 魔法盾自动补盾开/关 / 你已在最近的城镇复活 / 快捷物品已绑定 / 技能学习成功 / 技能配置成功 / 传送戒指：安全位移 / 火焰戒指：火球 / 防御戒指：恢复N生命 / "%s：生命 %d/%d" | NON_ERROR | `show_message` | 保持 `show_message` | 否 |
| 拾取拒绝 | 掉落拒绝提示（LootFeedback 通道） | NON_ERROR | LootFeedback | 保持 LootFeedback（z_index 未动） | 否 |
| 使用物品成功 | 使用了%s（×2） | NON_ERROR | `show_message` | 保持 | 否 |
| 修理油类提示 | 修理油相关 String 返回（无 success 标志的旧通道） | NON_ERROR（legacy lane） | `show_message` | 保持 | 否（本任务不重构旧通道） |
| `_status_buff_entries` | 中毒状态旗标 | NON_ERROR（状态展示） | 无 | 追加 `{"id":"poison","skill":"施毒术","remaining":player.poison_status_remaining(),"started_at":0}` | 是（Part B） |

## scripts/hud.gd

| 位置 | 内容 | 分类 | 施工后 |
|---|---|---|---|
| `_build_hidden_compatibility_info` | 新建 `ErrorNotice` Label（z_as_relative=false, z_index=4096, 顶部居中 22px 暖金色） | ERROR 通道载体 | 新增 |
| `show_error_message(message, seconds:=2.0)` | `user_message` 边界守卫 → 设文本；`_process` 倒计时清理（下限 0.1s） | ERROR 通道 | 新增 |
| `show_message` | `loot_label.text = message` 原逻辑 | NON_ERROR | 未触碰 |

## scripts/inventory_panel.gd（装备失败路径闭环）

| 位置（函数） | 消息 | 分类 | 施工前 | 施工后 | 改动 |
|---|---|---|---|---|---|
| `_select_equipment_slot`（槽位不匹配） | "%s不能装备到%s位置。" | ERROR | 静默 return | `_show_error_message(...)` | 是 |
| `_select_equipment_slot`（权威拒绝） | 等级/攻击/魔法/道术不足、职业不符、性别不符、负重不足、所选装备已变化、存档失败等 result | ERROR | 静默 | `_show_error_message(UIErrorFeedbackScript.from_result(result, "无法装备该装备。"), 2.0)` | 是 |
| `_unequip_to_inventory_slot` 失败 | 背包满/存档失败等 | ERROR | 静默 | `_show_equipment_detail(slot)` + from_result(result, "无法卸下该装备，请重新操作。") | 是 |
| `_select_inventory_item`（卸装防挡） | 背包已满，没有空位可以卸下装备。 | ERROR | 无守卫（选中会打断卸装流程） | 选中装备槽且背包满时先报错 | 是 |
| context-action "unequip" 背包满 | 背包已满，没有空位可以卸下装备。 | ERROR | `show_message("没有可用的空背包格。")`（非错误措辞） | 中央错误 + 详情保留 | 是 |
| context-action 通用失败 | result.message | ERROR | 静默/presenter | from_result(result, "操作未能完成，请重新操作。") | 是 |
| `_activate_inventory_index` 拒绝 | result | ERROR | 静默 | from_result(result, "无法装备该装备。") | 是 |
| `_on_auto_sort_pressed` 失败 | 自动整理失败，物品顺序未改变。 | ERROR | 静默 | `_show_error_message(...)` | 是 |
| `_on_auto_sort_pressed` 成功 | 自动整理完成 | NON_ERROR | presenter `show_message("[color=#e8c277]自动整理完成[/color]")` | 保持 | 否 |
| 丢弃失败 | result.message | ERROR | 静默 | from_result(result, message) | 是 |
| `_unequip_selected` 背包满/失败 | 同上两条 | ERROR | 静默 | 中央错误 / from_result | 是 |

## scripts/player_state.gd

| 位置（函数） | 消息 | 分类 | 施工前 | 施工后 | 改动 |
|---|---|---|---|---|---|
| `learn_skill` 失败兜底分支 `_:` | result（机器 reason） | ERROR（结果层） | 返回裸 result/message | 返回 `UIErrorFeedbackScript.from_result(learn_result, "技能学习失败，请稍后重试。")` | 是 |
| `equip_inventory_index_result` / `unequip_to_inventory_slot` | 等级/攻击/魔法/道术不足、职业不符、性别不符、负重、所选装备已变化、存档失败 | 权威层（不变） | 已有 | 未触碰（文本与判定逐字保留） | 否 |
| 新增 `poison_status_remaining()`（player.gd） | maxf(poison_time, _monster_source_poison.remaining_seconds) | 状态聚合 | 无 | 新增 | 是（Part B） |

## 审计过且判定不动的文件

| 文件 | 判定 | 依据 |
|---|---|---|
| scripts/equipment_rules.gd | DEBUG_ONLY/权威层 | `requirement_error` 只产出机器 reason/中文短消息（"需要等级28" 等由权威给出，玩家可读，经 result 透传）；规则本身不改 |
| scripts/death_revival_panel.gd | NON_ERROR | 面板内 result label 是复活面板自有状态展示，非操作失败反馈 |
| scripts/shop_panel.gd / scripts/warehouse_panel.gd | TRANSACTION | 交易成交反馈留在面板内；guard 测试断言两文件零 show_error_message/ui_error_feedback 引用 |
| scripts/loot_feedback_layer.gd | NON_ERROR | 拾取通道独立，z_index 未动 |
| scripts/quest_panel.gd / scripts/map_panel.gd / scripts/skill_panel.gd | 面板内既有反馈 | 不在本次错误通道改造范围，未触碰 |
