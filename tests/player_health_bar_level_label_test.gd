extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	var bar := PlayerHealthBar.new()
	add_child(bar)
	for level_value in [1, 30, 99]:
		PlayerState.level = level_value
		PlayerState.profile_changed.emit()
		await get_tree().process_frame
		assert(bar.level_label_text() == "Lv%d" % level_value, "level label did not refresh")
		var snapshot: Dictionary = bar.layout_snapshot()
		var label_rect: Rect2 = snapshot["label_rect"]
		var bar_rect: Rect2 = snapshot["bar_rect"]
		assert(label_rect.end.x + float(snapshot["gap"]) <= bar_rect.position.x, "level label overlaps health bar")
		assert(is_equal_approx(label_rect.end.y, bar_rect.end.y), "level label typographic bottom is not aligned with health bar bottom")
		assert(is_equal_approx(float(snapshot["label_baseline"]) + float(snapshot["label_descent"]), bar_rect.end.y), "level label baseline does not use font descent")
		assert(is_equal_approx(float(snapshot["label_draw_baseline"]), float(snapshot["label_baseline"]) + 3.0), "level label optical correction changed")
		assert(is_equal_approx(float(snapshot["label_draw_baseline"]) + float(snapshot["label_descent"]), bar_rect.end.y + 3.0), "level label visible-baseline correction is not three logical pixels")
		assert(is_equal_approx(float(snapshot["group_center_x"]), 0.0), "label and bar group is not centered")
		assert(bar_rect.size == Vector2(50.0, 5.0), "health bar size changed")
		assert(snapshot["background_color"] == Color(0.12, 0.05, 0.04, 0.92), "health bar background changed")
		assert(snapshot["health_color"] == Color(0.75, 0.12, 0.08, 1.0), "health bar color changed")
	bar.set_health(30, 120)
	assert(bar.current_hp == 30 and bar.max_hp == 120, "set_health state regressed")
	print("PLAYER_HEALTH_BAR_LEVEL_LABEL_PASS")
	get_tree().quit(0)
