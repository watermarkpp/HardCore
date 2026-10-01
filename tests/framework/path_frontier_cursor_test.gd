extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
var checks := 0
var failures: Array[String] = []

class CountedField extends Search.StaticGoalField:
	var pushes := 0
	func _push(item: Array) -> void:
		pushes += 1
		super._push(item)

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _context() -> Dictionary:
	return {"valid": true, "contract_id": Terrain.CONTRACT_ID, "runtime_map_id": 1,
		"design_size": Vector2i(64, 64), "blocked_cells": {}, "build_sha256": "a".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID}

func _goals() -> Dictionary:
	# A dense legal frontier isolates rebuilding from expansion and body/Node IO.
	var result := {}
	for y in range(8, 40):
		for x in range(8, 40):
			result[Vector2i(x, y)] = Vector2(x + 0.5, y + 0.5)
	return result

func _run() -> void:
	PlayerState.test_mode = true
	var goals := _goals()
	var field := CountedField.new(_context(), 0.35, goals, {})
	var original_heap: Array = field.heap
	field.pushes = 0
	var start := Vector2i(58, 58)
	field.attach(start)
	check(field.pushes <= 32, "start ownership change does not synchronously rebuild 1024 frontier records")
	check(is_same(field.heap, original_heap), "start ownership change does not publish a partial replacement heap")
	var published := false
	var services := 0
	while services < 80:
		services += 1
		field.advance_to(start, 32, 0)
		if not is_same(field.heap, original_heap):
			published = true
			break
	check(published and services > 1, "frontier reconstruction is resumable and eventually publishes")
	if published:
		check(field.expansions == 0, "no expansion reads a replacement before its final publication")
		check(field.heap == _reference_heap(goals, start), "published priorities retain exact stable legacy ordering")
	var result := "SEARCHING"
	var rounds := 0
	while result == "SEARCHING" and rounds < 300:
		rounds += 1
		result = field.advance_to(start, 32, 0)
	check(result == "FOUND", "bounded frontier and expansion quanta reach the actual destination")
	if result == "FOUND":
		var route: PackedVector2Array = field.path_from(start)
		var expected := PackedVector2Array()
		for index in range(19):
			expected.append(Vector2(57.5 - index, 57.5 - index))
		check(route == expected, "complete nearest diagonal route keeps exact legacy parents and endpoint")
	_verify_replacement_during_rebuild()
	if not _proof.write_receipt("path_frontier_cursor_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_PATH_FRONTIER_CURSOR_PASS" if failures.is_empty()
		else "FRAMEWORK_PATH_FRONTIER_CURSOR_FAIL") + " checks=" + str(checks)
		+ " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_replacement_during_rebuild() -> void:
	var goals := _goals()
	var field := CountedField.new(_context(), 0.35, goals, {})
	var first := Vector2i(58, 58)
	var replacement := Vector2i(54, 58)
	field.attach(first)
	field.attach(replacement)
	var old_heap: Array = field.heap
	field.advance_to(first, 32, 0)
	field.pushes = 0
	field.detach(first)
	check(field.pushes <= 32, "cancellation during rebuild does not rebuild all records synchronously")
	check(field.active_start == replacement, "remaining exact owner receives the active heuristic")
	check(is_same(field.heap, old_heap), "superseded partial frontier cannot become the published heap")
	var services := 0
	while is_same(field.heap, old_heap) and services < 100:
		services += 1
		field.advance_to(replacement, 32, 0)
	check(not is_same(field.heap, old_heap), "latest owner eventually receives one atomic completed frontier")
	check(field.expansions == 0 and field.heap == _reference_heap(goals, replacement),
		"only latest heuristic is published; cancellation leaves no stale half-heap")

func _reference_heap(goals: Dictionary, active: Vector2i) -> Array:
	# Independent literal legacy comparator/insertion reference. The fixture's
	# 1024 open goal records all have shortest distance zero.
	var result: Array = []
	var ordered: Array = goals.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in ordered:
		var delta := (active - cell).abs()
		var heuristic := float(maxi(delta.x, delta.y)) + (sqrt(2.0) - 1.0) * float(mini(delta.x, delta.y))
		var item: Array = [heuristic, 0.0, cell.y, cell.x, cell]
		result.append(item)
		var index := result.size() - 1
		while index > 0:
			var parent := (index - 1) >> 1
			if not _reference_less(item, result[parent]):
				break
			result[index] = result[parent]
			index = parent
		result[index] = item
	return result

func _reference_less(a: Array, b: Array) -> bool:
	for index in range(4):
		if a[index] != b[index]:
			return a[index] < b[index]
	return false
