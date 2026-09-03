extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/loading_transition_contract_v1.json"
const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const GAME_ICON_PATH := "res://assets/branding/game_icon.png"
const BATTLEFIELD_BACKGROUND_PATH := "res://assets/ui/gothic_theme/v1/loading_battlefield_background.jpg"


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
	assert(is_equal_approx(overlay.shade.color.a, 1.0), "Loading底层遮罩没有保持完全不透明")
	assert(overlay.shade.color.b > overlay.shade.color.g and overlay.shade.color.g > overlay.shade.color.r, "Loading背景不是冷调炭黑蓝")
	assert(overlay.battlefield_background.texture.resource_path == BATTLEFIELD_BACKGROUND_PATH, "Loading没有使用正式黑白战场底图")
	assert(overlay.battlefield_background.get_meta("stable_id", "") == "ui.loading.battlefield_background", "Loading战场底图稳定ID错误")
	assert(overlay.battlefield_background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "Loading战场底图没有无变形铺满视口")
	assert(overlay.game_icon_watermark.texture.resource_path == GAME_ICON_PATH, "Loading没有使用正式游戏图标暗纹")
	assert(overlay.game_icon_watermark.get_meta("stable_id", "") == "ui.loading.game_icon_watermark", "Loading图标暗纹稳定ID错误")
	assert(overlay.game_icon_watermark.material is ShaderMaterial, "Loading图标没有去黑底亮度遮罩")
	assert(overlay.red_glow.get_meta("stable_id", "") == "ui.loading.red_breathing_glow", "暗红呼吸光稳定ID错误")
	assert(overlay.vignette.get_meta("stable_id", "") == "ui.loading.edge_vignette", "边缘暗角稳定ID错误")
	assert(overlay.embers.size() == 14 and overlay.embers.size() <= 16, "Loading余烬数量不符合低开销限制")

	var covered_requests: Array[Dictionary] = []
	var finished_requests: Array[Dictionary] = []
	overlay.transition_covered.connect(func(request: Dictionary) -> void: covered_requests.append(request.duplicate(true)))
	overlay.transition_finished.connect(func(request: Dictionary) -> void: finished_requests.append(request.duplicate(true)))
	overlay.begin_loading("map:test:001")
	assert(overlay.visible and is_equal_approx(overlay.modulate.a, 1.0), "Loading显示首帧没有完全遮住旧地图")
	assert(covered_requests.is_empty(), "Loading覆盖许可不能在调用方开始等待前同步发出")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(overlay.visible and is_equal_approx(overlay.modulate.a, 1.0), "Loading显示期间出现根节点透明度变化")
	assert(covered_requests.size() == 1, "Loading完全覆盖后没有发出切图许可信号")
	assert(covered_requests[0].contract_id == "ui.loading.transition.v1", "Loading覆盖信号契约错误")
	assert(covered_requests[0].transition_id == "map:test:001", "Loading覆盖信号丢失transition_id")
	overlay.finish_loading()
	assert(not overlay.visible, "Loading完成后没有隐藏")
	assert(is_equal_approx(overlay.modulate.a, 1.0), "Loading隐藏后错误保留根节点透明度")
	assert(finished_requests.size() == 1, "Loading完成信号没有发出")
	assert(finished_requests[0].contract_id == "ui.loading.transition.v1", "Loading完成信号契约错误")
	assert(finished_requests[0].transition_id == "map:test:001", "Loading完成信号丢失transition_id")
	print("LOADING_TRANSITION_UI_PASS：不透明黑白战场、唯一Loading文字、零HUD透出和稳定契约均正常")
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
