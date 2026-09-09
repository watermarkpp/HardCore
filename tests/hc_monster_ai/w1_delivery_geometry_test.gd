extends Node

const Geometry := preload("res://scripts/monster_ai_package/delivery_geometry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

var failures: Array[String] = []


func _ready() -> void:
	_test_absolute_noninteger_origin_all_directions()
	_test_target_cell_is_absolute()
	_test_invalid_inputs_fail_closed()
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		get_tree().quit(1)
		return
	print("W1_MONSTER_DELIVERY_GEOMETRY_PASS")
	get_tree().quit(0)


func _context(origin_ground_gu: Vector2) -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		71,
		origin_ground_gu,
		Vector2(31.25, -18.75),
		Callable(self, "_ground_to_screen"),
	)


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return (
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(ground_gu)
		+ Vector2(733.0, 417.0)
	)


func _test_absolute_noninteger_origin_all_directions() -> void:
	var origin := Vector2(31.75, -18.125)
	var origin_cell := Vector2i(31, -19)
	var steps: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
	]
	for direction_index: int in range(8):
		var step := steps[direction_index]
		var snapshot := Geometry.create_directional_cell_snapshot(
			"monster.test.spit",
			"release:%d" % direction_index,
			origin,
			Vector2(step) * 1.7,
			2,
			_context(origin),
		)
		_check(
			bool(Snapshot.validate_for_consumer(
				snapshot,
				_context(origin),
				Snapshot.VALIDATION_STRICT_V2,
			).get("valid", false)),
			"direction %d snapshot is not strict V2" % direction_index,
		)
		var cells: Array = snapshot.get("geometry_cells_grid_steps", [])
		_check(
			cells == [origin_cell + step, origin_cell + step * 2],
			"direction %d translated absolute cells incorrectly: %s" % [
				direction_index,
				str(cells),
			],
		)
		_check(
			Snapshot.intersects_target_combat_footprint_ground_gu(
				snapshot,
				Vector2(origin_cell + step * 2) + Vector2(0.49, 0.49),
				0.0,
			),
			"direction %d lost the second source cell" % direction_index,
		)
		_check(
			not Snapshot.intersects_target_combat_footprint_ground_gu(
				snapshot,
				Vector2(origin_cell + step * 3),
				0.0,
			),
			"direction %d expanded beyond the two-cell spit mask" % direction_index,
		)


func _test_target_cell_is_absolute() -> void:
	var origin := Vector2(31.75, -18.125)
	var target := Vector2(44.99, 7.01)
	var snapshot := Geometry.create_target_cell_snapshot(
		"monster.test.target_tile",
		"release:target",
		origin,
		target,
		_context(origin),
	)
	_check(
		snapshot.get("geometry_cells_grid_steps", []) == [Vector2i(44, 7)],
		"target tile was treated as a relative mask",
	)
	_check(
		Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			Vector2(44.5, 7.5),
			0.0,
		),
		"target tile does not cover its absolute cell center",
	)
	_check(
		not Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			Vector2(76.5, -11.5),
			0.0,
		),
		"target tile was translated by the nonzero source origin",
	)


func _test_invalid_inputs_fail_closed() -> void:
	_check(
		Geometry.directional_cells(Vector2.INF, Vector2.RIGHT, 2).is_empty(),
		"nonfinite origin produced cells",
	)
	_check(
		Geometry.directional_cells(Vector2.ZERO, Vector2.ZERO, 2).is_empty(),
		"zero direction produced cells",
	)
	_check(
		Geometry.directional_cells(Vector2.ZERO, Vector2.RIGHT, 0).is_empty(),
		"nonpositive length produced cells",
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
