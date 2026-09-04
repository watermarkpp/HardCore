extends Node

const Policy := preload("res://scripts/skills/taoist_support_policy.gd")
const Targeting := preload("res://scripts/skills/taoist_friendly_targeting.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_candidate_filtering()
	_verify_range_gate()
	_verify_lowest_hp_percent_selection()
	_verify_tie_break_order()
	_verify_full_hp_allowed()
	_verify_area_geometry_contracts()
	print(
		"TAOIST_SUPPORT_POLICY_PASS: candidates, 9 GU, exact HP%, "
		+ "self/distance/id tie-breaks, full-HP allowed (self preferred), "
		+ "3x3/7x7 geometry"
	)
	get_tree().quit(0)


func _verify_candidate_filtering() -> void:
	var normalized := Policy.normalize_candidates([
		{
			"instance_id": 1,
			"is_self": true,
			"current_hp": 50,
			"max_hp": 100,
			"ground_position_gu": Vector2(0, 0),
			"level": 40,
			"actor_kind": "self",
		},
		{
			"instance_id": 101,
			"is_self": false,
			"current_hp": 30,
			"max_hp": 80,
			"ground_position_gu": Vector2(1, 0),
			"level": 5,
		},
		{
			"instance_id": 102,
			"is_self": false,
			"current_hp": 0,
			"max_hp": 80,
			"ground_position_gu": Vector2(2, 0),
			"level": 5,
		},
		{
			"instance_id": 0,
			"is_self": false,
			"current_hp": 10,
			"max_hp": 80,
			"ground_position_gu": Vector2(3, 0),
			"level": 5,
		},
		{"instance_id": 103, "current_hp": 10, "max_hp": 80},
	])
	assert(normalized.size() == 2)
	assert(normalized[0].is_self and normalized[0].actor_kind == "self")
	assert(not normalized[1].is_self and normalized[1].instance_id == 101)
	assert(Policy.normalize_candidates(null).is_empty())
	assert(Policy.normalize_candidates("bad").is_empty())


func _verify_range_gate() -> void:
	var center := Vector2(0, 0)
	var candidates := [
		Policy.make_candidate(1, true, 50, 100, Vector2(9.0, 0.0), 40),
		Policy.make_candidate(101, false, 30, 80, Vector2(9.001, 0.0), 5),
		Policy.make_candidate(102, false, 30, 80, Vector2(12.0, 0.0), 5),
	]
	var selection := Policy.select_heal_target(candidates, center, 9.0)
	assert(selection.valid)
	assert(selection.selected.instance_id == 1)
	assert(selection.injured_count == 1)
	assert(selection.contract_id == Policy.CONTRACT_ID)


func _verify_lowest_hp_percent_selection() -> void:
	var center := Vector2(0, 0)
	## A: 49/98 (missing fraction 0.5); B: 50/99 (missing fraction ~0.49495).
	## Cross-multiplication keeps the exact integer comparison.
	var near_tie := Policy.select_heal_target([
		Policy.make_candidate(1, true, 50, 99, center, 40),
		Policy.make_candidate(101, false, 49, 98, center, 5),
	], center, 9.0)
	assert(near_tie.valid and near_tie.selected.instance_id == 101)
	## 333/1000 (66.7% missing) vs 1/3 (66.666...% missing).
	var fraction_case := Policy.select_heal_target([
		Policy.make_candidate(1, true, 334, 1000, center, 40),
		Policy.make_candidate(101, false, 1, 3, center, 5),
	], center, 9.0)
	assert(fraction_case.valid and fraction_case.selected.instance_id == 101)


func _verify_tie_break_order() -> void:
	var center := Vector2(0, 0)
	## Self first even when another summon is closer.
	var self_first := Policy.select_heal_target([
		Policy.make_candidate(101, false, 50, 100, Vector2(1, 0), 5),
		Policy.make_candidate(1, true, 50, 100, Vector2(6, 0), 40),
	], center, 9.0)
	assert(self_first.valid and self_first.selected.instance_id == 1)
	## Then nearer distance.
	var nearer_first := Policy.select_heal_target([
		Policy.make_candidate(101, false, 50, 100, Vector2(6, 0), 5),
		Policy.make_candidate(102, false, 50, 100, Vector2(1, 0), 5),
	], center, 9.0)
	assert(nearer_first.valid and nearer_first.selected.instance_id == 102)
	## Then stable instance id.
	var id_first := Policy.select_heal_target([
		Policy.make_candidate(102, false, 50, 100, center, 5),
		Policy.make_candidate(101, false, 50, 100, center, 5),
	], center, 9.0)
	assert(id_first.valid and id_first.selected.instance_id == 101)


func _verify_full_hp_allowed() -> void:
	var center := Vector2(0, 0)
	var all_full := Policy.select_heal_target([
		Policy.make_candidate(1, true, 100, 100, center, 40),
		Policy.make_candidate(101, false, 80, 80, center, 5),
	], center, 9.0)
	assert(all_full.valid)
	assert(all_full.reason.is_empty())
	assert(all_full.all_full_hp)
	assert(
		all_full.selected.instance_id == 1,
		"all-full pool must prefer self"
	)
	assert(all_full.contract_id == Policy.CONTRACT_ID)
	var empty := Policy.select_heal_target([], center, 9.0)
	assert(not empty.valid and empty.reason == Policy.REASON_NO_FRIENDLY_CANDIDATES)
	var out_of_range := Policy.select_heal_target([
		Policy.make_candidate(1, true, 100, 100, center, 40),
		Policy.make_candidate(101, false, 50, 100, Vector2(10, 0), 5),
	], center, 9.0)
	## The in-range pool (self, full HP) remains valid; the out-of-range
	## injured summon does not block the user-approved full-HP cast.
	assert(out_of_range.valid)
	assert(out_of_range.all_full_hp)
	assert(out_of_range.selected.instance_id == 1)
	var only_out_of_range := Policy.select_heal_target([
		Policy.make_candidate(101, false, 50, 100, Vector2(10, 0), 5),
	], center, 9.0)
	assert(not only_out_of_range.valid)
	assert(
		only_out_of_range.reason == Policy.REASON_NO_FRIENDLY_TARGET_IN_RANGE
	)


func _verify_area_geometry_contracts() -> void:
	var square := Targeting.exact_square_cells(Vector2i(10, 10), 3)
	assert(square.size() == 9)
	assert(square.has(Vector2i(10, 10)))
	assert(square.has(Vector2i(9, 9)) and square.has(Vector2i(11, 11)))
	var chebyshev := Targeting.chebyshev_area_cells(Vector2i(10, 10), 3)
	assert(chebyshev.size() == 49)
	assert(chebyshev.has(Vector2i(7, 7)) and chebyshev.has(Vector2i(13, 13)))
	assert(not chebyshev.has(Vector2i(6, 6)) and not chebyshev.has(Vector2i(14, 14)))
	var center_gu := Vector2(10.0, 10.0)
	var inside := Targeting.candidates_in_cells([
		Policy.make_candidate(1, true, 50, 100, Vector2(10.0, 10.0), 40),
		Policy.make_candidate(101, false, 50, 100, Vector2(9.9, 10.0), 5),
		Policy.make_candidate(102, false, 50, 100, Vector2(11.5, 10.0), 5),
	], center_gu, square)
	assert(inside.size() == 3)
	var outside := Targeting.candidates_in_cells([
		Policy.make_candidate(103, false, 50, 100, Vector2(8.4, 10.0), 5),
		Policy.make_candidate(104, false, 50, 100, Vector2(12.0, 10.0), 5),
	], center_gu, square)
	assert(outside.is_empty())
