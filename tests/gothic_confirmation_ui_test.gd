extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/confirmation_dialog_contract_v1.json"
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "公共确认组件契约无法解析")
	assert(contract.get("contractId", "") == "ui.confirmation.dialog.v1", "公共确认组件契约 ID 错误")
	var dialog: Control = GothicConfirmationPanelScript.new()
	add_child(dialog)
	await get_tree().process_frame
	assert(dialog.get_meta("stable_id", "") == "ui.confirmation.dialog", "公共确认组件稳定 ID 错误")
	assert(dialog.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停状态下确认组件必须可操作")
	assert(not dialog.visible, "确认组件默认必须隐藏")
	assert(dialog.modal_frame.size == Vector2(560, 304), "确认组件尺寸不符合公共内嵌框原始比例")
	assert(dialog.modal_frame.theme_type_variation == "GothicInsetFrame", "紧凑确认组件没有使用比例匹配的公共内嵌框")
	assert(dialog.modal_frame.clip_contents, "确认框没有启用子内容裁切")
	assert(Rect2(Vector2.ZERO, dialog.modal_frame.size).encloses(Rect2(dialog.inner_fill.position, dialog.inner_fill.size)), "内部底板超出装饰框")
	assert(dialog.cancel_button.size.y >= 56 and dialog.confirm_button.size.y >= 56, "确认按钮触控高度不足")
	assert(dialog.cancel_button.theme_type_variation == "GothicComponentButton", "取消按钮未复用公共 Theme")
	assert(dialog.confirm_button.theme_type_variation == "GothicComponentSelectedButton", "确认按钮未复用公共 Theme")
	var safe_rect := Rect2(32, 20, 496, 256)
	for control: Control in [dialog.title_label, dialog.message_label, dialog.cancel_button, dialog.confirm_button]:
		assert(safe_rect.encloses(Rect2(control.position, control.size)), "%s 超出确认框安全内容区" % control.name)

	var cancelled_requests: Array[Dictionary] = []
	dialog.cancelled.connect(func(request: Dictionary) -> void: cancelled_requests.append(request.duplicate(true)))
	dialog.open_confirmation({
		"action_id": "ui.test.normal",
		"title": "确认操作",
		"message": "是否继续当前操作？",
		"context": {"sample_id": 1},
	})
	assert(dialog.visible, "普通确认样板没有显示")
	assert(dialog.current_request.tone == "normal", "普通确认 tone 错误")
	dialog.cancel_button.pressed.emit()
	assert(not dialog.visible and cancelled_requests.size() == 1, "取消操作没有关闭并发出信号")
	assert(cancelled_requests[0].contract_id == "ui.confirmation.dialog.v1", "取消信号缺少契约 ID")
	assert(cancelled_requests[0].context.sample_id == 1, "取消信号没有原样返回 context")

	var confirmed_requests: Array[Dictionary] = []
	dialog.confirmed.connect(func(request: Dictionary) -> void: confirmed_requests.append(request.duplicate(true)))
	dialog.open_confirmation({
		"action_id": "quest.abandon",
		"title": "确认放弃任务",
		"message": "放弃后，当前任务进度将按游戏规则处理。",
		"confirm_label": "确认放弃",
		"tone": "danger",
		"context": {"quest_id": "Q001"},
	})
	assert(dialog.current_request.tone == "danger", "危险确认 tone 错误")
	assert(dialog.confirm_button.text == "确认放弃", "危险确认按钮文字没有更新")
	dialog.confirm_button.pressed.emit()
	assert(not dialog.visible and confirmed_requests.size() == 1, "确认操作没有关闭并发出信号")
	assert(confirmed_requests[0].action_id == "quest.abandon", "确认信号 action_id 错误")
	assert(confirmed_requests[0].context.quest_id == "Q001", "确认信号没有原样返回 context")
	print("GOTHIC_CONFIRMATION_UI_PASS：公共紧凑弹窗、普通/危险状态、56px 触控区和稳定契约均正常")
	get_tree().quit(0)
