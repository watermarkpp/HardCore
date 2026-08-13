extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/death_revival_contract_v1.json"
const LAYOUT_CONTRACT_PATH := "res://assets/data/ui/manual_layout_overrides.json"
const DeathRevivalPanelScript := preload("res://scripts/death_revival_panel.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const GAME_ICON_PATH := "res://assets/branding/game_icon.png"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "死亡复活契约无法解析")
	assert(contract.get("contractId", "") == "ui.death.revival.v1", "死亡复活契约 ID 错误")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	var panel: Control = DeathRevivalPanelScript.new()
	host.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_saved_local_rect(panel, "DeathRevivalModal")
	host.size = Vector2(1600, 720)
	await get_tree().process_frame
	var modal_rect: Rect2 = (panel.modal as Control).get_global_rect()
	assert(modal_rect.position.x >= 0.0 and modal_rect.position.y >= 0.0, "死亡复活框超出屏幕左上安全范围")
	assert(modal_rect.end.x <= host.get_global_rect().end.x and modal_rect.end.y <= host.get_global_rect().end.y, "死亡复活框超出屏幕右下安全范围")
	assert(panel.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "死亡界面必须能在暂停状态工作")
	assert(panel.modal.theme_type_variation == "GothicModalFrame", "死亡界面没有复用公共哥特外框")
	assert(panel.modal.get_node("ModalSurface").get_script() == GothicFrameFillScript, "死亡界面一级框没有使用代码背景")
	assert(panel.modal.has_node("ModalFrameSafetyOverlay"), "死亡界面缺少双圈安全覆盖层")
	assert(panel.town_button.get_meta("stable_id", "") == "death.revival.town", "城镇复活按钮稳定 ID 错误")
	assert(panel.special_button.get_meta("stable_id", "") == "death.revival.special", "特殊复活按钮稳定 ID 错误")
	assert(panel.town_button.size.y >= 56 and panel.special_button.size.y >= 56, "复活按钮触控范围不足")
	assert(panel.death_icon.texture.resource_path == GAME_ICON_PATH, "死亡界面没有使用正式游戏图标")
	assert(panel.death_icon.get_meta("stable_id", "") == "ui.death.game_icon", "死亡游戏图标稳定 ID 错误")
	assert(panel.modal.get_node_or_null("DeathMark") == null, "死亡界面仍保留旧圆形底框")
	assert(not _tree_contains_exact_text(panel, "亡"), "死亡界面仍保留旧“亡”字")

	panel.open_death_screen({
		"death_id": "death:test:001",
		"message": "你倒在了兽人古墓",
		"loss_text": "死亡损失：经验 10%",
		"revival_options": [
			{
				"option_slot": "town",
				"method_id": "revive.nearest_town",
				"label": "最近城镇复活",
				"enabled": true,
				"countdown_seconds": 3,
				"hint": "返回比奇省安全区",
			},
			{
				"option_slot": "special",
				"method_id": "revive.special.scroll",
				"label": "使用复活卷轴",
				"enabled": false,
				"reason": "背包中没有复活卷轴",
			},
		],
	})
	assert(panel.visible and panel.message_label.text == "你倒在了兽人古墓", "死亡上下文没有显示")
	assert(panel.town_button.disabled and panel.town_status_label.text == "3 秒后可用", "城镇复活倒计时错误")
	assert(panel.special_button.disabled and panel.special_status_label.text == "背包中没有复活卷轴", "特殊复活不可用原因错误")

	panel.update_revival_option("town", {"countdown_seconds": 0})
	assert(not panel.town_button.disabled and panel.town_status_label.text == "返回比奇省安全区", "倒计时结束后按钮没有启用")
	var requests: Array[Dictionary] = []
	panel.revival_requested.connect(func(request: Dictionary) -> void: requests.append(request.duplicate(true)))
	panel.town_button.pressed.emit()
	assert(requests.size() == 1, "城镇复活没有发出请求")
	assert(requests[0].contract_id == "ui.death.revival.v1", "复活请求契约 ID 错误")
	assert(requests[0].death_id == "death:test:001", "复活请求没有携带死亡事件 ID")
	assert(requests[0].method_id == "revive.nearest_town" and requests[0].option_slot == "town", "复活方式请求错误")
	panel.apply_revival_result({"success": false, "message": "复活位置暂不可用"})
	assert(panel.visible and panel.result_label.text == "复活位置暂不可用", "失败结果没有保留界面和提示")
	panel.apply_revival_result({"success": true, "message": "已经复活"})
	assert(not panel.visible, "复活成功后死亡界面没有关闭")
	print("DEATH_REVIVAL_GOTHIC_UI_PASS：死亡遮罩、城镇/特殊复活、倒计时、不可用原因与请求契约均正常")
	get_tree().quit(0)


func _tree_contains_exact_text(root: Node, value: String) -> bool:
	if root is Label and root.text == value:
		return true
	if root is Button and root.text == value:
		return true
	for child: Node in root.get_children():
		if _tree_contains_exact_text(child, value):
			return true
	return false


func _assert_saved_local_rect(panel: Control, path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_CONTRACT_PATH))
	assert(data is Dictionary, "正式 UI 布局合同无法解析")
	var entry: Dictionary = data.get("profiles", {}).get("death_revival", {}).get("nodes", {}).get(path, {})
	assert(not entry.is_empty(), "死亡复活页缺少保存布局：%s" % path)
	var values: Array = entry.get("logicalRect", [])
	assert(values.size() == 4, "死亡复活页保存矩形无效：%s" % path)
	var profile: Dictionary = data.get("profiles", {}).get("death_revival", {})
	var design: Array = profile.get("logicalDesignSize", [])
	assert(design.size() == 2, "死亡复活页缺少逻辑设计尺寸")
	var scale := Vector2(panel.size.x / float(design[0]), panel.size.y / float(design[1]))
	var expected := Rect2(float(values[0]) * scale.x, float(values[1]) * scale.y, float(values[2]) * scale.x, float(values[3]) * scale.y)
	var actual := (panel.get_node(path) as Control).get_rect()
	assert(actual.is_equal_approx(expected), "死亡复活页没有加载最新人工保存矩形：%s" % path)
