extends Node

## Geometry contract for the two center-sensitive HUD text surfaces. This uses
## the production Main/GameRoot/HUD tree and calls only the real center
## alignment boundary; it does not reproduce the alignment formula locally.
const WorldFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await WorldFixture.wait_for_formal_world(self, game, "hud_center_alignment_special_text")
	var hud: CanvasLayer = game.hud
	var safe_root := hud.get_node_or_null("MobileSafeRoot") as Control
	assert(safe_root != null, "formal HUD MobileSafeRoot missing")
	var chassis := safe_root.get_node_or_null("IntegratedHUDChassis") as Control
	var warrior_label := safe_root.get_node_or_null("WarriorStateLabel") as Label
	var target_panel := safe_root.get_node_or_null("TargetPanel") as Control
	var target_label: Label = target_panel.get_node_or_null("TargetLabel") as Label if target_panel != null else null
	assert(chassis != null and warrior_label != null and target_panel != null and target_label != null)
	assert(warrior_label.get_meta("center_exempt_base_offset_left") != null)
	assert(target_panel.get_meta("center_exempt_base_offset_left") != null)

	var chassis_center := chassis.get_global_rect().get_center().x
	var warrior_center_before := warrior_label.get_global_rect().get_center().x
	var target_center_before := target_panel.get_global_rect().get_center().x
	var target_text_center_before := target_label.get_global_rect().get_center().x
	assert(is_equal_approx(warrior_center_before, chassis_center), "warrior text is not centered on chassis")
	assert(is_equal_approx(target_text_center_before, target_center_before), "target text is not centered in target panel")

	hud._apply_center_alignment_delta(24.0)
	var warrior_after_positive := warrior_label.get_global_rect().get_center().x
	var target_after_positive := target_panel.get_global_rect().get_center().x
	assert(is_equal_approx(warrior_after_positive - warrior_center_before, 24.0))
	assert(is_equal_approx(target_after_positive - target_center_before, 24.0))
	hud._apply_center_alignment_delta(24.0)
	assert(is_equal_approx(warrior_label.get_global_rect().get_center().x, warrior_after_positive), "repeated positive delta drifted warrior label")
	assert(is_equal_approx(target_panel.get_global_rect().get_center().x, target_after_positive), "repeated positive delta drifted target panel")

	hud._apply_center_alignment_delta(-24.0)
	assert(is_equal_approx(warrior_label.get_global_rect().get_center().x, warrior_center_before - 24.0))
	assert(is_equal_approx(target_panel.get_global_rect().get_center().x, target_center_before - 24.0))
	hud._apply_center_alignment_delta(0.0)
	assert(is_equal_approx(warrior_label.get_global_rect().get_center().x, warrior_center_before))
	assert(is_equal_approx(target_panel.get_global_rect().get_center().x, target_center_before))
	assert(is_equal_approx(target_label.get_global_rect().get_center().x, target_panel.get_global_rect().get_center().x))

	game.queue_free()
	await get_tree().process_frame
	print("HUD_CENTER_ALIGNMENT_SPECIAL_TEXT_PASS warrior_target_centered=true delta_repeat_stable=true")
	get_tree().quit(0)
