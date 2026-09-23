extends Node

const LabScript := preload("res://tools/visual_acceptance_lab/visual_acceptance_lab.gd")
const RingGeometry := preload("res://scripts/monster_target_ring_geometry.gd")

func _ready() -> void:
	var original_test_mode := PlayerState.test_mode
	var lab := LabScript.new()
	add_child(lab)
	await get_tree().process_frame
	lab._mode_option.select(1)
	lab._on_mode_changed(1)
	# Include every offset identity plus a short crawler and a standing control.
	for monster_id in [92, 94, 110, 118, 120, 121, 122, 123, 170, 172, 64]:
		assert(lab._select_monster_id(monster_id))
		var foot: Vector2 = lab._visual_foot_origin()
		var visual_origin: Vector2 = lab._monster.visual.position
		var actor_origin: Vector2 = lab._monster.position
		var physics_radius: float = lab._monster.collision_radius_px
		var offsets := RingGeometry.direction_offsets(monster_id)
		for logical_direction in range(8):
			lab._direction_option.select(logical_direction)
			lab._apply_monster_preview_frame()
			var atlas_row: int = lab._monster.visual.current_direction
			var offset: Vector2 = offsets.get(atlas_row, Vector2.ZERO)
			assert(lab._visual_foot_origin().is_equal_approx(foot))
			assert(lab._monster.visual.position.is_equal_approx(visual_origin))
			assert(lab._monster.position.is_equal_approx(actor_origin))
			assert(is_equal_approx(lab._monster.collision_radius_px, physics_radius))
			var ring_count := 0
			for child: Node in lab._overlay_root.get_children():
				if child.name != LabScript.RUNTIME_TARGET_RING_OVERLAY_NAME:
					continue
				ring_count += 1
				assert((child.get_meta("center") as Vector2).is_equal_approx(foot + offset))
				assert((child.get_meta("radii") as Vector2).is_equal_approx(lab._monster.ground_indicator_radii()))
			assert(ring_count == 1)
			var snapshot: Dictionary = lab.monster_ground_review_snapshot()
			assert(snapshot.get("targetMatchesContract", false))
			assert((snapshot.get("runtimeRingCenter") as Vector2).is_equal_approx(lab._monster.ground_indicator_center() + offset))
	lab.queue_free()
	await get_tree().process_frame
	assert(PlayerState.test_mode == original_test_mode)
	print("MONSTER_TARGET_RING_CALIBRATOR_PASS monsters=11 directions=8 foot_and_physics_unchanged=true")
	get_tree().quit(0)
