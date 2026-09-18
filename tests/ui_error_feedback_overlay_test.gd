extends Node

## Error-feedback overlay acceptance (R1 error channel).
## Covers: standalone display + auto-expiry, layering above every modal panel,
## independence from the loot/show_message lane, empty text after expiry, and
## the machine-reason boundary guard at the HUD entry.

const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")


func _ready() -> void:
	_run.call_deferred()


func _settle(frames := 3) -> void:
	for _index in range(frames):
		await get_tree().process_frame


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await _settle()
	# Freeze the engine-driven timer so the test controls _process manually.
	hud.set_process(false)

	# --- Case 1: HUD with no window open -----------------------------------
	assert(hud.error_label != null, "error_label must exist")
	assert(hud.error_label.name == "ErrorNotice", "error label stable node name")
	assert(hud.error_label.text.is_empty(), "error label starts empty")
	hud.show_error_message("需要等级30")
	assert(hud.error_label.text == "需要等级30", "case1 error text shown")
	assert(hud.error_label.is_visible_in_tree(), "case1 error label visible")
	assert(not is_equal_approx(float(hud._error_message_timer), 0.0), "case1 error timer armed")
	# Default lifetime ~2 seconds: still visible after 1.9s, gone after 2.0s.
	hud._process(1.0)
	hud._process(0.9)
	assert(hud.error_label.text == "需要等级30", "case1 error persists near 2s")
	hud._process(0.1)
	assert(hud.error_label.text.is_empty(), "case1 error auto-dismissed after ~2s")
	# Minimum lifetime clamp: a tiny duration must still render at least once.
	hud.show_error_message("临时提示", 0.0)
	assert(hud.error_label.text == "临时提示", "case1 minimum lifetime still renders")
	hud._process(0.1)
	assert(hud.error_label.text.is_empty(), "case1 minimum lifetime expires")

	# --- Case 2: layering above every modal panel ---------------------------
	hud._toggle_inventory()
	await _settle()
	assert(hud.inventory_panel != null and hud.inventory_panel.visible, "case2 inventory panel open")
	hud.show_error_message("需要攻击46")
	await _settle()
	assert(hud.error_label.text == "需要攻击46", "case2 error shown with panel open")
	assert(hud.error_label.is_visible_in_tree(), "case2 error visible with panel open")
	var panel_z := int(hud.inventory_panel.z_index)
	var presenter_z := int(hud.inventory_panel.item_detail_presenter.z_index)
	var error_z := int(hud.error_label.z_index)
	assert(not hud.error_label.z_as_relative, "case2 error z must be absolute")
	assert(panel_z == 50, "case2 inventory z baseline")
	assert(presenter_z == 4095, "case2 item detail presenter z baseline")
	assert(error_z == 4096, "case2 error channel must sit at z=4096")
	assert(error_z > presenter_z and error_z > panel_z, "case2 error above panel and detail presenter")
	assert(hud.error_label.get_index() >= 0 and hud.error_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "case2 error label never blocks input")

	# --- Case 3: timers independent from the show_message lane --------------
	hud.show_message("施放：雷电术", 2.0)
	hud.show_error_message("魔法不足", 2.0)
	assert(hud.loot_label.text == "施放：雷电术", "case3 normal lane keeps its text")
	assert(hud.error_label.text == "魔法不足", "case3 error lane keeps its text")
	hud._process(0.5)
	assert(hud.loot_label.text == "施放：雷电术" and hud.error_label.text == "魔法不足", "case3 both alive at 0.5s")
	# A short normal notice expires without clearing the still-armed error.
	hud.show_message("进入比奇省", 0.4)
	hud._process(0.4)
	assert(hud.loot_label.text.is_empty(), "case3 short normal notice expired")
	assert(hud.error_label.text == "魔法不足", "case3 error survives normal-lane expiry")
	# And the reverse: an expired error must not clear a live normal notice.
	hud.show_message("你已在最近的城镇复活", 2.0)
	hud._process(1.6)
	assert(hud.error_label.text.is_empty(), "case3 error expired on its own clock")
	assert(hud.loot_label.text == "你已在最近的城镇复活", "case3 normal notice survives error expiry")
	hud._process(0.4)
	assert(hud.loot_label.text.is_empty(), "case3 normal notice expired on its own clock")

	# --- Case 4: error ends with empty text ---------------------------------
	hud.show_error_message("技能动作或冷却尚未结束", 2.0)
	hud._process(2.0)
	assert(hud.error_label.text == "", "case4 error text empty after expiry")

	# --- Machine-reason boundary at the HUD entry ----------------------------
	hud.show_error_message("save_failed")
	assert(hud.error_label.text == "操作失败，请稍后重试。", "machine reason replaced by Chinese fallback")
	hud.show_error_message("safe_logout_home_resolution_failed")
	assert(hud.error_label.text == UIErrorFeedbackScript.GENERIC_FALLBACK, "namespaced reason replaced")
	hud.show_error_message("安全退出失败，请稍后重试。")
	assert(hud.error_label.text == "安全退出失败，请稍后重试。", "Chinese prose passes unchanged")
	hud.show_error_message("")
	assert(hud.error_label.text == "安全退出失败，请稍后重试。", "empty message never blanks the channel mid-display")

	hud.queue_free()
	await _settle()
	print("UI_ERROR_FEEDBACK_OVERLAY_PASS: display, expiry, modal layering, lane independence, reason guard")
	get_tree().quit(0)
