extends Node

const LockPolicy := preload("res://scripts/skills/spell_target_lock_policy.gd")
const Geometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	_test_lock_range_and_order()
	_test_spell_range_is_independent_from_lock_range()
	_test_monster_footprint_cell_contact()
	print("SPELL_TARGET_LOCK_AND_FOOTPRINT_PASS: 12-GU Euclidean lock stays separate from spell range and area damage uses footprint contact")
	get_tree().quit(0)


func _test_lock_range_and_order() -> void:
	assert(LockPolicy.CONTRACT_ID == "combat.spell_lock.euclidean_gu.v2")
	assert(LockPolicy.LOCK_RANGE_GU == 12.0)
	assert(not LockPolicy.is_within_lock_range(Vector2.ZERO, Vector2(12.0, -3.0)))
	assert(LockPolicy.is_within_lock_range(Vector2.ZERO, Vector2(7.2, 9.6)))
	assert(not LockPolicy.is_within_lock_range(Vector2.ZERO, Vector2(12.01, 0.0)))
	var ordered := LockPolicy.ordered_candidates([
		{"origin_ground_gu": Vector2.ZERO, "target_ground_gu": Vector2(4, 4), "instance_id": 3},
		{"origin_ground_gu": Vector2.ZERO, "target_ground_gu": Vector2(2, 0), "instance_id": 2},
		{"origin_ground_gu": Vector2.ZERO, "target_ground_gu": Vector2(20, 0), "instance_id": 1},
	])
	assert(ordered.size() == 2)
	assert(ordered[0].instance_id == 2 and ordered[1].instance_id == 3)
	assert(ordered[0].has("distance_gu"))
	assert(ordered[0].has("distance_squared_gu"))
	assert(not ordered[0].has("tile_distance"))


func _test_spell_range_is_independent_from_lock_range() -> void:
	var origin := Vector2.ZERO
	var locked_target := Vector2(11, 0)
	assert(LockPolicy.is_within_lock_range(origin, locked_target))
	assert(not LockPolicy.spell_range_allows_target(origin, locked_target, 9.0))
	assert(not LockPolicy.spell_range_allows_target(origin, Vector2(9, 9), 9.0))
	assert(LockPolicy.spell_range_allows_target(origin, Vector2(5.4, 7.2), 9.0))


func _test_monster_footprint_cell_contact() -> void:
	assert(
		Geometry.FOOTPRINT_INTERSECTION_CONTRACT_ID
		== "skills.caster.area_footprint_intersection.ground_gu_sat.v2"
	)
	var touching := PackedVector2Array([
		Vector2(0.49, -0.10),
		Vector2(0.70, -0.10),
		Vector2(0.70, 0.10),
		Vector2(0.49, 0.10),
	])
	assert(Geometry.target_footprint_intersects_cell(touching, Vector2i.ZERO))
	assert(Geometry.target_footprint_intersects_cells([Vector2i.ZERO], touching))
	var separated := PackedVector2Array([
		Vector2(0.501, -0.10),
		Vector2(0.70, -0.10),
		Vector2(0.70, 0.10),
		Vector2(0.501, 0.10),
	])
	assert(not Geometry.target_footprint_intersects_cell(separated, Vector2i.ZERO))
	var overlaps_second_cell := PackedVector2Array([
		Vector2(1.40, -0.15),
		Vector2(1.60, -0.15),
		Vector2(1.60, 0.15),
		Vector2(1.40, 0.15),
	])
	assert(Geometry.target_footprint_intersects_cells(
		[Vector2i.ZERO, Vector2i.RIGHT],
		overlaps_second_cell
	))
