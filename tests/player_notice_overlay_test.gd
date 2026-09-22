extends Node

## Unified central notice acceptance (R2 overlay + R1 error semantics).
## Covers: single overlay geometry/z, display + auto-expiry, layering above
## every modal panel, error-priority preemption, info queueing, loot_label
## retirement for global notices, and the machine-reason boundary guard.

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
	expect(hud.notice_presenter != null, "notice presenter exists")
	if hud.notice_presenter == null:
		get_tree().quit(1)
		return
	var presenter := hud.notice_presenter
	presenter.set_process(false)

	# --- Case 1: fixed geometry, layering, single notice layer ---------------
	expect(hud.error_label != null, "error_label alias exists")
	expect(hud.error_label.name == "ErrorNotice", "primary notice label stable node name")
	expect(hud.error_label.text.is_empty(), "notice starts empty")
	expect(presenter.offset_left == 360 and presenter.offset_top == 132, "notice overlay keeps x offsets")
	expect(presenter.offset_right == -360 and presenter.offset_bottom == 172, "notice overlay keeps y offsets")
	expect(not presenter.z_as_relative, "notice overlay z is absolute")
	expect(int(presenter.z_index) == 4096, "notice overlay sits at z=4096")
	expect(presenter.prefix_label.get_theme_font_size("font_size") == 22, "notice font size stays 22px")

	# --- Case 2: display + auto-expiry (error lane) --------------------------
	hud.show_error_message("需要等级30")
	expect(hud.error_label.text == "需要等级30", "case2 error text shown")
	expect(hud.error_label.is_visible_in_tree(), "case2 notice visible")
	expect(presenter._remaining > 1.9, "case2 timer armed at ~2s")
	presenter._process(1.0)
	presenter._process(0.9)
	expect(hud.error_label.text == "需要等级30", "case2 notice persists near 2s")
	presenter._process(0.1)
	expect(hud.error_label.text.is_empty(), "case2 notice auto-dismissed after ~2s")
	hud.show_error_message("临时提示", 0.0)
	expect(hud.error_label.text == "临时提示", "case2 minimum lifetime still renders")
	presenter._process(0.1)
	expect(hud.error_label.text.is_empty(), "case2 minimum lifetime expires")

	# --- Case 3: priority preemption (error over success) --------------------
	hud.show_success_message("已装备 屠龙", 2.0)
	expect(hud.error_label.text == "已装备 屠龙", "case3 success shown centrally")
	hud.show_error_message("魔法不足", 2.0)
	expect(hud.error_label.text == "魔法不足", "case3 error preempts success immediately")
	expect(presenter.queue_size() == 0, "case3 preempted success is not re-queued")

	# --- Case 4: info never flushes a live error -----------------------------
	presenter.clear_for_test()
	hud.show_error_message("魔法不足", 2.0)
	hud.show_message("进入比奇省", 2.0)
	expect(hud.error_label.text == "魔法不足", "case4 error keeps the overlay")
	expect(presenter.queue_size() == 1, "case4 info waits in the queue")
	presenter._process(2.0)
	expect(hud.error_label.text == "进入比奇省", "case4 queued info shows after error expiry")
	presenter._process(2.0)
	expect(hud.error_label.text.is_empty(), "case4 queued info expires on its own clock")

	# --- Case 5: global notices never write the retired loot label ----------
	presenter.clear_for_test()
	hud.show_message("施放：雷电术", 2.0)
	expect(hud.error_label.text == "施放：雷电术", "case5 show_message renders centrally")
	expect(hud.loot_label.text.is_empty(), "case5 loot label stays retired")
	hud.show_error_message("需要攻击46", 1.0)
	expect(hud.loot_label.text.is_empty(), "case5 loot label never reactivated by errors")

	# --- Case 6: layering above every modal panel ----------------------------
	presenter.clear_for_test()
	hud._toggle_inventory()
	await _settle()
	expect(hud.inventory_panel != null and hud.inventory_panel.visible, "case6 inventory panel open")
	hud.show_error_message("需要攻击46")
	await _settle()
	expect(hud.error_label.text == "需要攻击46", "case6 error shown with panel open")
	var panel_z := int(hud.inventory_panel.z_index)
	var detail_z := int(hud.inventory_panel.item_detail_presenter.z_index)
	expect(panel_z == 50, "case6 inventory z baseline")
	expect(detail_z == 4095, "case6 item detail presenter z baseline")
	expect(int(presenter.z_index) == 4096 and int(presenter.z_index) > detail_z and int(presenter.z_index) > panel_z, "case6 notice overlay above panel and detail presenter")
	expect(presenter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "case6 notice overlay never blocks input")

	# --- Machine-reason boundary at the HUD entry ----------------------------
	presenter.clear_for_test()
	hud.show_error_message("save_failed")
	expect(hud.error_label.text == "操作失败，请稍后重试。", "machine reason replaced by Chinese fallback")
	hud.show_error_message("safe_logout_home_resolution_failed")
	expect(hud.error_label.text == UIErrorFeedbackScript.GENERIC_FALLBACK, "namespaced reason replaced")
	hud.show_error_message("安全退出失败，请稍后重试。")
	expect(hud.error_label.text == "安全退出失败，请稍后重试。", "Chinese prose passes unchanged")
	hud.show_error_message("")
	expect(hud.error_label.text == "安全退出失败，请稍后重试。", "empty message never blanks the channel mid-display")

	hud.queue_free()
	await _settle()
	if failures.is_empty():
		print("PLAYER_NOTICE_OVERLAY_PASS: geometry, layering, expiry, priority, loot retirement, reason guard")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PLAYER_NOTICE_OVERLAY_FAIL: " + failure)
		get_tree().quit(1)


var failures: Array[String] = []


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
