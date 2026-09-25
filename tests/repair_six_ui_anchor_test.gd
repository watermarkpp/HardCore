extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var root := hud.get_node("MobileSafeRoot") as Control
	var chassis := root.get_node("IntegratedHUDChassis") as Control
	var failures: Array[String] = []
	for insets: Vector2 in [Vector2.ZERO, Vector2(66, 18), Vector2(12, 72), Vector2.ZERO]:
		root.offset_left = insets.x
		root.offset_right = -insets.y
		hud._apply_center_alignment_delta((insets.y - insets.x) * 0.5)
		hud.show_loot_batch(["金币 +123", "太阳水", "裁决之杖"])
		hud.show_message("世界提示居中检查")
		await get_tree().process_frame
		var center := chassis.get_global_rect().get_center().x
		if not is_equal_approx(hud.notice_presenter.get_global_rect().get_center().x, center):
			failures.append("world notice center insets=%s" % insets)
		for panel: Panel in hud.loot_feedback_layer.toast_panels:
			if panel.visible and not is_equal_approx(panel.get_global_rect().get_center().x, center):
				failures.append("pickup center %s insets=%s" % [panel.name, insets])
		if not is_equal_approx(hud.taoist_buff_icon_strip.get_global_rect().position.x,
			hud.hud_item_buttons[0].get_global_rect().position.x):
			failures.append("buff first-slot left edge insets=%s" % insets)
	for message: String in failures: print("FAIL_CHECK ", message)
	if not failures.is_empty():
		get_tree().quit(1)
		return
	print("REPAIR_SIX_UI_ANCHOR_PASS")
	get_tree().quit(0)
