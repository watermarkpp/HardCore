extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")

func _ready() -> void:
	var root := GameRootScript.new()
	root.current_map_id = -1
	var release := {
		"release_id": "integration.target_aligned.1",
		"origin_ground_gu": Vector2.ZERO,
		"locked_target_instance_id": 7,
		"locked_target_valid_at_release": true,
		"locked_target_ground_gu_at_release": Vector2(2.0, 0.75),
		"live_locked_target_direction_ground_gu": Vector2(2.0, 0.75),
	}
	var snapshot: Dictionary = root._create_melee_release_footprint_snapshot(
		Vector2.ZERO, Vector2.RIGHT, Geometry.SKILL_THRUST, release
	)
	assert(not snapshot.is_empty(), "valid lock must create target-aligned snapshot")
	var plan: Dictionary = release.get("target_aligned_plan", {})
	# The isolated fixture uses the canonical fallback projection; provide a
	# concrete runtime-map identity for strict visual-consumer validation.
	snapshot = snapshot.duplicate(true)
	snapshot["runtime_map_id"] = 1
	release["snapshot_validation_context"]["expected_runtime_map_id"] = 1
	assert(bool(plan.get("target_axis_eligible", false)), "valid lock must be eligible")
	var expected_axis: Vector2 = (
		release["live_locked_target_direction_ground_gu"] as Vector2
	).normalized()
	var actual_axis: Vector2 = plan.get("continuous_axis_ground_gu", Vector2.ZERO)
	assert(actual_axis.is_equal_approx(expected_axis), "axis must align to locked target continuously")
	assert(not actual_axis.is_equal_approx(Vector2.RIGHT) and not actual_axis.is_equal_approx(Vector2.DOWN), "arbitrary target axis must not quantize to body direction")
	assert(plan.get("skill_footprint_snapshot", {}).get("snapshot_id", "") == snapshot.get("snapshot_id", ""), "gameplay and visual snapshot identity must match")
	root._spawn_target_aligned_melee_visual(snapshot, Geometry.SKILL_THRUST, true, Vector2.ZERO, release)
	var visuals: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_in_group("zone_content"):
			visuals.append(child)
	assert(visuals.size() == 1, "valid release must add one zone_content visual")
	var visual: Node = visuals[0]
	assert(visual.get("_snapshot").get("snapshot_id", "") == snapshot.get("snapshot_id", ""), "visual must consume gameplay snapshot")
	visual.free()

	var invalid_release := release.duplicate(true)
	invalid_release["locked_target_valid_at_release"] = false
	var invalid_snapshot: Dictionary = root._create_melee_release_footprint_snapshot(
		Vector2.ZERO, Vector2.RIGHT, Geometry.SKILL_THRUST, invalid_release
	)
	assert(not bool(invalid_release.get("target_aligned_plan", {}).get("target_axis_eligible", true)), "invalid lock must fail closed")
	root._spawn_target_aligned_melee_visual(invalid_snapshot, Geometry.SKILL_THRUST, false, Vector2.ZERO, invalid_release)
	var remaining_zone_content := 0
	for child: Node in root.get_children():
		if child.is_in_group("zone_content"):
			remaining_zone_content += 1
	assert(remaining_zone_content == 0, "invalid lock must not generate visual")

	var body_release := root._create_melee_release_footprint_snapshot(Vector2.ZERO, Vector2.DOWN, Geometry.SKILL_NORMAL, {})
	assert(not body_release.is_empty(), "legacy body snapshot remains available for animation-only path")
	assert(not body_release.has("__target_aligned_plan") and not body_release.has("continuous_axis_ground_gu"), "body path remains legacy eight-way")
	root.free()
	print("GAME_ROOT_WARRIOR_TARGET_ALIGNED_INTEGRATION_PASS")
	get_tree().quit()
