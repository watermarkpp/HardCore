extends Node

const ChassisDesigns := preload("res://scripts/hud_chassis_designs.gd")

## 2026-09-20 user order verification:
##   1. dragon chassis + top enemy bar are horizontally exempted from the
##      device safe area so their midline lands on the TRUE screen midline
##      (the vertical line through the camera-centered character);
##   2. the chassis is shrunk 20% (656x218.4) anchored at the bottom spike
##      tip, which keeps its global position;
##   3. experience bar segments fill the reserved slot height.

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
	var target_panel := root.get_node("TargetPanel") as Control
	var failures: Array[String] = []
	var check := func(condition: bool, label: String) -> void:
		if not condition:
			failures.append(label)
			print("FAIL_CHECK %s" % label)

	# 1. Shrunk chassis contract (656x218.4 = 820x273 * 0.8).
	check.call(
		is_equal_approx(chassis.size.x, 656.0) and is_equal_approx(chassis.size.y, 218.4),
		"chassis size == 656x218.4",
	)
	# Bottom spike tip anchor: rect bottom stays 1.43px above the root bottom.
	check.call(
		is_equal_approx(chassis.offset_top, -219.83)
			and is_equal_approx(chassis.offset_bottom, -1.43),
		"bottom spike anchor offsets (-219.83 / -1.43)",
	)
	check.call(
		is_equal_approx(chassis.get_global_rect().end.y, root.size.y - 1.43),
		"chassis global bottom keeps the spike anchor position",
	)
	# Base offsets are centered on the safe root (compensation is additive).
	check.call(
		is_equal_approx(chassis.offset_left, -328.0)
			and is_equal_approx(chassis.offset_right, 328.0),
		"chassis base offsets -328/+328",
	)

	# 2. Center exemption shifts BOTH controls by the requested delta without
	# accumulating across repeated applications.
	var base_target_left := float(target_panel.get_meta("center_exempt_base_offset_left"))
	hud._apply_center_alignment_delta(37.0)
	check.call(
		is_equal_approx(chassis.offset_left, -328.0 + 37.0)
			and is_equal_approx(chassis.offset_right, 328.0 + 37.0),
		"chassis honors +37 exemption delta",
	)
	check.call(
		is_equal_approx(target_panel.offset_left, base_target_left + 37.0),
		"target panel honors +37 exemption delta",
	)
	var center_after := chassis.get_global_rect().get_center().x
	hud._apply_center_alignment_delta(37.0)
	check.call(
		is_equal_approx(chassis.get_global_rect().get_center().x, center_after),
		"repeat application is idempotent (no accumulation)",
	)
	check.call(
		is_equal_approx(
			target_panel.get_global_rect().get_center().x,
			chassis.get_global_rect().get_center().x,
		),
		"chassis and target panel share one midline",
	)
	hud._apply_center_alignment_delta(0.0)
	check.call(
		is_equal_approx(chassis.offset_left, -328.0),
		"delta 0 restores base offsets",
	)
	# Desktop/headless safe area equals the window -> delta must be zero.
	check.call(
		is_zero_approx(hud._center_alignment_delta()),
		"desktop safe-area delta is 0",
	)

	# 3. Experience segments fill the slot-derived bar height.
	var experience_bar := chassis.get_node("ExperienceBar") as Control
	check.call(experience_bar.size.y > 10.0, "v3 slot policy bar is taller than the legacy 10px")
	var segments_fill := true
	for index: int in range(1, 11):
		var segment := experience_bar.get_node("Segment%02d" % index) as ColorRect
		if segment == null or not is_equal_approx(segment.size.y, experience_bar.size.y):
			segments_fill = false
	check.call(segments_fill, "all segments use the full bar height")
	var design: Dictionary = ChassisDesigns.active_design()
	var slot_rect: Rect2 = ChassisDesigns.source_rect_to_local(
		design, design["experience_slot_source_rect"])
	var bleed: Vector2 = design.get("experience_slot_render_bleed", Vector2.ZERO)
	check.call(
		is_equal_approx(experience_bar.size.y, slot_rect.size.y + bleed.y),
		"bar height == slot height + render bleed",
	)

	if failures.is_empty():
		print("HUD_CENTER_ALIGNMENT_PASS")
		get_tree().quit(0)
	else:
		print("HUD_CENTER_ALIGNMENT_FAILED count=%d" % failures.size())
		get_tree().quit(1)
