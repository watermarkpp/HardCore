extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var root := hud.get_node("MobileSafeRoot") as Control
	var chassis := root.get_node("IntegratedHUDChassis") as Control
	var label := hud.warrior_state_label as Label
	var peak_global: Vector2 = chassis.get_global_transform() * hud._chassis_source_to_local(GameHUD.HUD_CHASSIS_CENTER_PEAK_SOURCE)
	assert(absf(label.get_global_rect().get_center().x - peak_global.x) <= 1.0)
	assert(absf(peak_global.y - label.get_global_rect().end.y - GameHUD.HUD_CHASSIS_STATE_LABEL_GAP) <= 1.0)
	assert(label.get_meta("stable_id", "") == "hud.warrior_state_label.centered.v3")
	print("WARRIOR_STATE_LABEL_LAYOUT_PASS")
	get_tree().quit(0)
