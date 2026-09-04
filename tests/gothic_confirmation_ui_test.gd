extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/confirmation_dialog_contract_v1.json"
const LAYOUT_CONTRACT_PATH := "res://assets/data/ui/manual_layout_overrides.json"
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "公共确认组件契约无法解析")
	assert(contract.get("contractId", "") == "ui.confirmation.dialog.v1", "公共确认组件契约 ID 错误")
	var dialog: Control = GothicConfirmationPanelScript.new()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(dialog.get_meta("stable_id", "") == "ui.confirmation.dialog", "公共确认组件稳定 ID 错误")
	assert(dialog.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停状态下确认组件必须可操作")
	assert(not dialog.visible, "确认组件默认必须隐藏")
	_assert_saved_local_rect(dialog, "ModalFrame")
	assert(dialog.modal_frame.theme_type_variation == "GothicInsetFrame", "紧凑确认组件没有使用比例匹配的公共内嵌框")
	assert(dialog.modal_frame.clip_contents, "确认框没有启用子内容裁切")
	assert(Rect2(Vector2.ZERO, dialog.modal_frame.size).encloses(Rect2(dialog.inner_fill.position, dialog.inner_fill.size)), "内部底板超出装饰框")
	assert(dialog.inner_fill.get_script() == GothicFrameFillScript and dialog.inner_fill.show_behind_parent, "确认框没有使用贴合单圈框的代码背景")
	assert(dialog.cancel_button.size.y >= 56 and dialog.confirm_button.size.y >= 56, "确认按钮触控高度不足")
	assert(dialog.cancel_button.theme_type_variation == "GothicComponentButton", "取消按钮未复用公共 Theme")
	assert(dialog.confirm_button.theme_type_variation == "GothicComponentButton", "确认按钮不应作为持久选择")
	var safe_rect := Rect2(Vector2(20, 16), dialog.modal_frame.size - Vector2(40, 32))
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
	assert(dialog.confirm_button.get_meta("gothic_feedback_state", "") == "busy", "confirmation action missing busy feedback")
	assert(not dialog.visible and confirmed_requests.size() == 1, "确认操作没有关闭并发出信号")
	assert(confirmed_requests[0].action_id == "quest.abandon", "确认信号 action_id 错误")
	assert(confirmed_requests[0].context.quest_id == "Q001", "确认信号没有原样返回 context")
	print("GOTHIC_CONFIRMATION_UI_PASS：公共紧凑弹窗、普通/危险状态、56px 触控区和稳定契约均正常")
	get_tree().quit(0)


func _assert_saved_local_rect(dialog: Control, path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_CONTRACT_PATH))
	assert(data is Dictionary, "正式 UI 布局合同无法解析")
	var profile: Dictionary = data.get("profiles", {}).get("confirmation_dialog", {})
	var entry: Dictionary = profile.get("nodes", {}).get(path, {})
	assert(not entry.is_empty(), "确认弹窗缺少保存布局：%s" % path)
	var rect: Array = entry.get("logicalRect", [])
	var design: Array = profile.get("logicalDesignSize", [])
	assert(rect.size() == 4 and design.size() == 2, "确认弹窗保存矩形无效：%s" % path)
	var scale := Vector2(dialog.size.x / float(design[0]), dialog.size.y / float(design[1]))
	var expected := Rect2(float(rect[0]) * scale.x, float(rect[1]) * scale.y, float(rect[2]) * scale.x, float(rect[3]) * scale.y)
	var actual := (dialog.get_node(path) as Control).get_rect()
	assert(actual.is_equal_approx(expected), "确认弹窗没有加载最新人工保存矩形：%s" % path)
