extends Node

## Error-feedback overlay acceptance (R2 unified layer, R1 error semantics).
## Covers: standalone display + auto-expiry, layering above every modal panel,
## latest-error-wins on the shared layer, empty text after expiry, and the
## machine-reason boundary guard at the HUD entry.

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
	var presenter := hud.notice_presenter
	assert(presenter != null, "notice presenter must exist")
	presenter.set_process(false)

	# --- Case 1: HUD with no window open -----------------------------------
	assert(hud.error_label != null, "error_label must exist")
	assert(hud.error_label.name == "ErrorNotice", "error label stable node name")
	assert(hud.error_label.text.is_empty(), "error label starts empty")
	hud.show_error_message("需要等级30")
	assert(hud.error_label.text == "需要等级30", "case1 error text shown")
	assert(hud.error_label.is_visible_in_tree(), "case1 error label visible")
	assert(presenter._remaining > 1.9, "case1 error timer armed")
	# Default lifetime ~2 seconds: still visible after 1.9s, gone after 2.0s.
	presenter._process(1.0)
	presenter._process(0.9)
	assert(hud.error_label.text == "需要等级30", "case1 error persists near 2s")
	presenter._process(0.1)
	assert(hud.error_label.text.is_empty(), "case1 error auto-dismissed after ~2s")
	# Minimum lifetime clamp: a tiny duration must still render at least once.
	hud.show_error_message("临时提示", 0.0)
	assert(hud.error_label.text == "临时提示", "case1 minimum lifetime still renders")
	presenter._process(0.1)
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
	assert(not presenter.z_as_relative, "case2 notice z must be absolute")
	assert(panel_z == 50, "case2 inventory z baseline")
	assert(presenter_z == 4095, "case2 item detail presenter z baseline")
	assert(int(presenter.z_index) == 4096, "case2 notice overlay must sit at z=4096")
	assert(int(presenter.z_index) > presenter_z and int(presenter.z_index) > panel_z, "case2 error above panel and detail presenter")
	assert(presenter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "case2 notice overlay never blocks input")

	# --- Case 3: the shared layer keeps R1 error semantics ------------------
	# A newer error replaces the visible error (latest wins); an INFO notice
	# must not flush a live error (it waits in the queue).
	presenter.clear_for_test()
	hud.show_error_message("魔法不足", 2.0)
	hud.show_error_message("技能动作或冷却尚未结束", 2.0)
	assert(hud.error_label.text == "技能动作或冷却尚未结束", "case3 latest error replaces the visible one")
	presenter.clear_for_test()
	hud.show_error_message("魔法不足", 2.0)
	hud.show_message("进入比奇省", 2.0)
	assert(hud.error_label.text == "魔法不足", "case3 info must not flush the live error")
	presenter._process(2.0)
	assert(hud.error_label.text == "进入比奇省", "case3 queued info shows after error expiry")
	presenter._process(2.0)
	assert(hud.error_label.text.is_empty(), "case3 queued info expires on its own clock")
	# The retired loot lane stays empty for global notices.
	assert(hud.loot_label.text.is_empty(), "case3 loot lane stays retired")

	# --- Case 4: error ends with empty text ---------------------------------
	presenter.clear_for_test()
	hud.show_error_message("技能动作或冷却尚未结束", 2.0)
	presenter._process(2.0)
	assert(hud.error_label.text == "", "case4 error text empty after expiry")

	# --- Machine-reason boundary at the HUD entry ----------------------------
	presenter.clear_for_test()
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
	print("UI_ERROR_FEEDBACK_OVERLAY_PASS: display, expiry, modal layering, latest-wins, reason guard")
	get_tree().quit(0)
