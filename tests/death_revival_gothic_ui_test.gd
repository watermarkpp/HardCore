extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/death_revival_contract_v1.json"
const DeathRevivalPanelScript := preload("res://scripts/death_revival_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "死亡复活契约无法解析")
	assert(contract.get("contractId", "") == "ui.death.revival.v1", "死亡复活契约 ID 错误")
	var panel: Control = DeathRevivalPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	assert(panel.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "死亡界面必须能在暂停状态工作")
	assert(panel.modal.theme_type_variation == "GothicModalFrame", "死亡界面没有复用公共哥特外框")
	assert(panel.town_button.get_meta("stable_id", "") == "death.revival.town", "城镇复活按钮稳定 ID 错误")
	assert(panel.special_button.get_meta("stable_id", "") == "death.revival.special", "特殊复活按钮稳定 ID 错误")
	assert(panel.town_button.size.y >= 56 and panel.special_button.size.y >= 56, "复活按钮触控范围不足")

	panel.open_death_screen({
		"death_id": "death:test:001",
		"message": "你倒在了兽人古墓",
		"loss_text": "损失：金币 5%",
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
