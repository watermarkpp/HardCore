extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/loading_transition_contract_v1.json"
const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "Loading过渡契约无法解析")
	assert(contract.get("contractId", "") == "ui.loading.transition.v1", "Loading过渡契约ID错误")
	assert(contract.get("exactVisibleText", "") == "Loading......", "Loading固定文字契约错误")
	var overlay: Control = LoadingTransitionOverlayScript.new()
	add_child(overlay)
	await get_tree().process_frame
	assert(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "Loading过渡层不能在暂停时继续淡入淡出")
	assert(overlay.get_meta("stable_id", "") == "ui.loading.overlay", "Loading过渡层稳定ID错误")
	assert(not overlay.visible, "Loading过渡层默认没有隐藏")
	assert(overlay.loading_label.text == "Loading......", "Loading文字不是指定内容")
	assert(_all_visible_text(overlay) == ["Loading......"], "Loading界面出现了额外文字")
	assert(overlay.shade.color.a < 1.0 and overlay.shade.color.r > 0.0, "Loading背景不是半透明深灰色")

	overlay.show_loading_immediately("map:test:001")
	assert(overlay.visible and overlay.modulate.a == 1.0, "Loading立即显示入口错误")
	var finished_requests: Array[Dictionary] = []
	overlay.transition_finished.connect(func(request: Dictionary) -> void: finished_requests.append(request.duplicate(true)))
	overlay.finish_loading()
	await get_tree().create_timer(0.25).timeout
	assert(not overlay.visible, "Loading完成后没有隐藏")
	assert(finished_requests.size() == 1, "Loading完成信号没有发出")
	assert(finished_requests[0].contract_id == "ui.loading.transition.v1", "Loading完成信号契约错误")
	assert(finished_requests[0].transition_id == "map:test:001", "Loading完成信号丢失transition_id")
	print("LOADING_TRANSITION_UI_PASS：半透明深灰遮罩、唯一Loading文字、淡入淡出和稳定契约均正常")
	get_tree().quit(0)


func _all_visible_text(root: Node) -> Array[String]:
	var result: Array[String] = []
	if root is Label and root.visible and not root.text.is_empty():
		result.append(root.text)
	if root is Button and root.visible and not root.text.is_empty():
		result.append(root.text)
	for child: Node in root.get_children():
		result.append_array(_all_visible_text(child))
	return result
