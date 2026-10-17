extends Node

## Required behavior comparison against the protected original GameRoot.
## This scope covers source helper math/selection/envelopes and exact RNG
## sequence. WorldCore/S lifetime/native effects need their own live tests.
const OracleRoot := preload("res://tests/framework/helpers/multicore_world_skill_original_game_root_20261014.gd")
const CurrentRoot := preload("res://scripts/game_root.gd")
const FullModel := preload("res://scripts/gameplay/world/world_skill_full_model.gd")
const LegacyPorts := preload("res://scripts/gameplay/world/world_skill_legacy_full_ports.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Manager := preload("res://scripts/persistent_ground_effect_manager.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var _checks: Array[Dictionary] = []

func _check(name: String, condition: bool, details: Dictionary = {}) -> void:
	proof.record(condition, name)
	_checks.append({"name":name,"status":"PASS" if condition else "FAIL","details":details})

func _ready() -> void:
	var original: Node = OracleRoot.new()
	var current: Node = CurrentRoot.new()
	current._combat_spatial_index = Index.new()
	current._ground_effect_manager = Manager.new(current._combat_spatial_index, current._combat_runtime)
	var ports: RefCounted = LegacyPorts.new(current)
	var model: RefCounted = FullModel.new()
	_check("full_model_rejects_missing_services", not model.configure_full_ports({}))
	var bindings: Dictionary = ports.full_bindings(model)
	var configured: bool = model.configure_full_ports(bindings)
	_check("full_legacy_exact_ports_configure", configured)
	if configured:
		var cells: Array[Vector2i] = [Vector2i(4,7),Vector2i(3,8),Vector2i(3,7),Vector2i(4,8)]
		var empty_cells: Array[Vector2i] = []
		_check("fire_wall_center_original_order", model._fire_wall_registry_center_cell(cells) == original._fire_wall_registry_center_cell(cells))
		_check("fire_wall_center_empty", model._fire_wall_registry_center_cell(empty_cells) == original._fire_wall_registry_center_cell(empty_cells))
		for effect: Dictionary in [{},{"max_active_fields_per_caster":8},{"max_active_fields_per_caster":1,"cap_policy":"evict_oldest"},{"cap_policy":"reject_new"}]:
			_check("fire_wall_cap_policy_%d" % _checks.size(), model._fire_wall_cap_policy(effect) == original._fire_wall_cap_policy(effect))
			_check("fire_wall_limit_%d" % _checks.size(), model._fire_wall_max_active_fields(effect) == original._fire_wall_max_active_fields(effect))
		var directions: Array[Vector2] = [Vector2.ZERO,Vector2.UP,Vector2.RIGHT,Vector2(1.0,0.00001),Vector2(-3.75,5.25),Vector2(1,1)]
		for direction: Vector2 in directions:
			_check("canonical_facing_%d" % _checks.size(), model._canonical_facing(direction) == original._canonical_facing(direction))
			for skill_id: String in ["wizard.fireball","wizard.laser_beam","warrior.thrusting","taoist.soul_fire_talisman"]:
				_check("skill_facing_%d" % _checks.size(), model._canonical_facing_for_skill(skill_id,direction) == original._canonical_facing_for_skill(skill_id,direction))
		_check("geometry_cells_aabb", model._aoe_geometry_cells_aabb(cells) == original._aoe_geometry_cells_aabb(cells))
		_check("geometry_empty_aabb", model._aoe_geometry_cells_aabb(empty_cells) == original._aoe_geometry_cells_aabb(empty_cells))
		for plan: Dictionary in [{},{"skill_id":"wizard.fireball","rejection":{"accepted":false,"reason":"invalid_target"}},
			{"skill_id":"warrior.thrusting","rejection":{"accepted":true,"reason":"accepted"},"gameplay_actions":[{"type":"melee_hit","multiplier":1.0}]}]:
			_check("legacy_plan_envelope_%d" % _checks.size(), model._legacy_result_from_plan(plan) == original._legacy_result_from_plan(plan))
		original._rng.seed = 721991
		current._rng.seed = 721991
		var original_test_mode: bool = PlayerState.test_mode
		PlayerState.test_mode = false
		var stats := {"attack_min":3,"attack_max":17,"magic_min":2,"magic_max":9,"tao_min":4,"tao_max":15,"luck":0}
		for index: int in range(64):
			var profession: String = ["warrior","wizard","taoist"][index % 3]
			var expected: int = original._canonical_primary_stat_roll(profession,stats)
			var actual: int = model._canonical_primary_stat_roll(profession,stats)
			_check("primary_stat_roll_%d" % index, actual == expected and current._rng.state == original._rng.state)
		for index: int in range(16):
			_check("canonical_seed_%d" % index, model._next_canonical_seed() == original._next_canonical_seed() and current._rng.state == original._rng.state)
		PlayerState.test_mode = original_test_mode
	var failed := 0
	for check: Dictionary in _checks:
		if check.status == "FAIL": failed += 1
	var model_weak: WeakRef = weakref(model)
	bindings = {}
	model = null
	ports = null
	original._combat_runtime.free()
	current._combat_runtime.free()
	original.free()
	current.free()
	_check("execution_backlink_does_not_retain_model", model_weak.get_ref() == null)
	if _checks.back().status == "FAIL": failed += 1
	if not proof.write_receipt("multicore_world_skill_full_20261014", _checks.size(), failed): failed += 1
	var result := {"status":"PASS" if failed == 0 else "FAIL","checks":_checks,"failed":failed,
		"scope":"protected original GameRoot helper behavior, exact RNG state, strict full-port admission",
		"full_world_native":"NOT_RUN","source_manifest_required":true}
	var file := FileAccess.open("user://multicore_world_skill_full_20261014.result.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result,"\t"))
	print("WORLD_SKILL_FULL_BEHAVIOR ", JSON.stringify(result))
	print("MULTICORE_WORLD_SKILL_FULL_", "PASS" if failed == 0 else "FAIL", " checks=", _checks.size())
	get_tree().quit(0 if failed == 0 else 1)
