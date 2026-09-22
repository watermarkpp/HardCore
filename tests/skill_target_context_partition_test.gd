extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const CastRequest := preload("res://scripts/skills/skill_cast_request.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")

var _game: Node
var _caster: PlayerCharacter
var _center: EnemyActor
var _boundary: EnemyActor
var _anchor: Vector2i
var _serial := 0
var _terrain_cache: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 99
	PlayerState.profession = "法师"
	for skill_id: String in Loader.skill_ids():
		PlayerState.learned_skills[Loader.display_name(skill_id)] = 3
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await _wait_for_world()
	_caster = _game.player
	_caster.set_physics_process(false)
	_caster.current_mp = 9999
	# Remove ambient actors, retaining the actual authored map/collision and
	# the GameRoot-owned index. Test actors use the normal exact-ID spawn.
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("summons"):
		node.queue_free()
	await get_tree().process_frame
	_game.set_physics_process(false)
	_anchor = _find_open_patch()
	# Spawn before moving the caster adjacent: the real spawn path otherwise
	# pushes a new actor away from the player's contact circle in _ready.
	_game._set_player_world_position(_screen(_anchor + Vector2i(0, -6)))
	_center = _spawn(19, _anchor + Vector2i.RIGHT)
	_boundary = _spawn(156, _anchor + Vector2i(2, 0))
	_game._set_player_world_position(_screen(_anchor))
	_verify_unused_arrays_and_scalar_targets()
	_verify_positive_control_plans()
	_verify_friendly_partition()
	_verify_real_wall_probe_partition()
	_game.queue_free()
	await _game.tree_exited
	print("SKILL_TARGET_CONTEXT_PARTITION_PASS no_unused_queries=1 scalars=1 control_plans=1 friendly=1 authored_wall_probe=1")
	get_tree().quit(0)


func _wait_for_world() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if (
			int(_game.get("current_map_id")) >= 0
			and not bool(_game.get("_world_bootstrap_in_progress"))
			and bool(_game.call("gameplay_input_is_enabled"))
		):
			break
		await get_tree().process_frame
	assert(int(_game.get("current_map_id")) == GameData.service_runtime_map_id(0))
	assert(not bool(_game.get("_world_bootstrap_in_progress")), "formal map bootstrap did not finish")
	assert(not _game._active_safe_zones.is_empty(), "do not replace the authored safe-zone contract")


func _screen(cell: Vector2i) -> Vector2:
	return _game._canonical_grid_cell_to_screen_px(cell)


func _point_blocked(cell: Vector2i) -> bool:
	if not _terrain_cache.has(cell):
		_terrain_cache[cell] = bool(_game.background.is_environment_point_blocked(_screen(cell)))
	return bool(_terrain_cache[cell])


func _open_cell(cell: Vector2i) -> bool:
	return (
		not _point_blocked(cell)
		and not WorldRules.point_inside_safe_zones_ground_gu(Vector2(cell), _game._active_safe_zones)
	)


func _find_open_patch() -> Vector2i:
	# Same authored outdoor region as canonical_skill_production_entry_test;
	# require real open cells instead of clearing or mocking map obstacles.
	for dy: int in range(-8, 9):
		for dx: int in range(-8, 9):
			var candidate := Vector2i(38 + dx, 14 + dy)
			var clear := true
			for py: int in range(-1, 2):
				for px: int in range(0, 4):
					if not _open_cell(candidate + Vector2i(px, py)):
						clear = false
			if clear:
				return candidate
	assert(false, "authored outdoor fixture has no required open control patch")
	return Vector2i.ZERO


func _spawn(monster_id: int, cell: Vector2i) -> EnemyActor:
	_serial += 1
	var canonical: Dictionary = GameData.get_monster_by_id(monster_id)
	assert(not canonical.is_empty())
	var enemy: EnemyActor = _game._spawn_enemy(canonical, _screen(cell), false, -1.0, {
		"respawn_enabled": false,
		"spawn_slot_id": "test:target_context:%d" % _serial,
	})
	assert(is_instance_valid(enemy), "formal exact-ID spawn must be admitted")
	assert(enemy.monster_id == monster_id and not enemy.is_boss)
	assert(enemy.runtime_map_id == int(_game.current_map_id) and enemy.projection_ready())
	assert(enemy.spatial_actor_runtime_id > 0 and enemy.can_receive_damage())
	enemy.set_physics_process(false)
	enemy.max_hp = 9999
	enemy.current_hp = 9999
	assert(enemy.global_position.distance_to(_screen(cell)) < 0.1, "spawn must keep the authored fixture position")
	return enemy


func _lock(target: EnemyActor) -> void:
	_game.locked_target = target
	_game._set_magic_locked_target(target, true)
	_game._skill_cast_target = target


func _query_count() -> int:
	return int(_game._combat_spatial_index.index_enemy_node_aabb_query_count)


func _context(skill_id: String, extra: Dictionary = {}) -> Dictionary:
	_serial += 1
	return _game._canonical_target_context(
		Loader.skill(skill_id), _caster.global_position, Vector2.RIGHT,
		false, "partition:%s:%d" % [skill_id, _serial], extra,
	)


func _verify_unused_arrays_and_scalar_targets() -> void:
	for target: EnemyActor in [_center, _boundary]:
		var service: Dictionary = target.behavior_profile.get("serviceBehavior", {})
		var expected_undead := bool(service.get(
			"undead", target.monster_data.get("undead", target.monster_data.get("isUndead", false)),
		))
		assert(expected_undead == (target.monster_id == 156), "fixtures must exercise both undead scalar values")
		for skill_id: String in [
			"wizard.magic_shield", "wizard.fireball", "wizard.great_fireball",
			"wizard.lightning", "wizard.hellfire", "wizard.fire_wall",
			"wizard.laser", "wizard.ice_storm", "wizard.exploding_flame",
		]:
			_lock(target)
			var queries_before := _query_count()
			var context := _context(skill_id)
			assert(_query_count() == queries_before, "unused hostile AABB query: " + skill_id)
			assert(context.get("targets", []).is_empty(), "unused hostile records: " + skill_id)
			if skill_id == "wizard.magic_shield":
				assert(bool(context.get("friendly", false)))
				assert(not context.has("target_instance_id"), "self shield must not inherit the enemy lock")
				continue
			assert(int(context.get("target_instance_id", 0)) == target.get_instance_id())
			assert(int(context.get("target_level", -1)) == int(target.monster_data.get("level", target.level)))
			assert(bool(context.get("target_is_undead", not expected_undead)) == expected_undead)
			assert(bool(context.get("target_is_monster", false)))
			assert(bool(context.get("target_is_living", false)))
			assert(int(context.get("target_poison_resist", -1)) == target.anti_poison)
			assert(bool(context.get("has_target", false)))
			if skill_id == "wizard.lightning":
				assert(bool(context.get("line_of_sight", false)), "real open map LOS must remain valid")
				var action := _actions(skill_id, context)[0] as Dictionary
				assert(action.get("type", "") == "targeted_sky_strike")
				assert(float(action.get("race_multiplier", 0.0)) == (1.5 if expected_undead else 1.0))


func _actions(skill_id: String, context: Dictionary) -> Array:
	var facing: Vector2i = _game._canonical_facing_for_skill(skill_id, Vector2.RIGHT)
	var request := CastRequest.create(
		skill_id, 3, PlayerState.level,
		_game._canonical_screen_px_to_grid_cell(_caster.global_position),
		facing, context, {"mana": 9999, "materials": {}}, 4701,
	)
	var canonical_context: Dictionary = _game._canonical_execution_context(
		skill_id, _caster.global_position, Vector2.RIGHT, context,
		_game._skill_cast_target, str(context.get("release_id", "")),
	)
	var plan: Dictionary = Router.build_canonical_plan(request, canonical_context)
	assert(bool(plan.get("rejection", {}).get("accepted", false)), "real canonical plan rejected: " + str(plan.get("rejection", {})))
	return plan.get("gameplay_actions", [])


func _record(context: Dictionary, enemy: EnemyActor) -> Dictionary:
	for value: Dictionary in context.get("targets", []):
		if int(value.get("instance_id", 0)) == enemy.get_instance_id():
			return value
	return {}


func _action_for(actions: Array, target_id: int) -> Dictionary:
	for value: Dictionary in actions:
		if int(value.get("target_instance_id", 0)) == target_id:
			return value
	return {}


func _verify_positive_control_plans() -> void:
	_lock(_center)
	var count_before := _query_count()
	var repulsion := _context("wizard.repulsion_ring", {"force_success": true})
	assert(_query_count() == count_before + 1, "repulsion must retain its one hostile query")
	var near_record := _record(repulsion, _center)
	assert(not near_record.is_empty(), "repulsion must see the adjacent real monster")
	assert(not bool(near_record.get("path_blocked", true)), "open push point must be probed as clear")
	assert(int(near_record.get("level", -1)) == _center.level)
	var push := _action_for(_actions("wizard.repulsion_ring", repulsion), _center.get_instance_id())
	assert(push.get("type", "") == "adjacent_push")
	assert(bool(push.get("eligible", false)) and bool(push.get("displaced", false)))
	assert(int(push.get("damage", -1)) == 0 and float(push.get("push_distance_gu", 0.0)) > 0.0)
	# Rebuild the essential reference record from the live canonical actor,
	# independently of the new context list; same seed must preserve output.
	var reference := repulsion.duplicate(true)
	reference["targets"] = [{
		"instance_id": _center.get_instance_id(), "level": _center.level,
		"is_boss": _center.is_boss, "immovable": _center.is_boss,
		"path_blocked": _game.background.is_environment_point_blocked(_screen(_anchor + Vector2i(2, 0))),
	}]
	assert(push == _action_for(_actions("wizard.repulsion_ring", reference), _center.get_instance_id()))

	_lock(_center)
	count_before = _query_count()
	var entrapment := _context("taoist.entrapment")
	assert(_query_count() == count_before + 1, "boundary context must retain its authorized query")
	assert(not _record(entrapment, _boundary).is_empty(), "real boundary occupant must remain a candidate")
	assert(entrapment.get("geometry_cells", []).size() == 8)
	var trap: Dictionary = _actions("taoist.entrapment", entrapment)[0]
	assert(trap.get("type", "") == "monster_boundary_control")
	assert(int(trap.get("trapped_count", 0)) == 1)
	assert(trap.get("target_instance_ids", []) == [_center.get_instance_id()])
	assert(int(trap.get("boundary_cell_count", 0)) == 8)
	assert(float(trap.get("duration_seconds", 0.0)) > 0.0)
	var no_boundary_records := entrapment.duplicate(true)
	no_boundary_records["targets"] = []
	var expected_without_boundary := trap.duplicate(true)
	expected_without_boundary["boundary_ring_candidate_count"] = 0
	assert(expected_without_boundary == _actions("taoist.entrapment", no_boundary_records)[0], "boundary attackers must not become center occupants")
	var immune_context := entrapment.duplicate(true)
	immune_context["target_control_immune"] = true
	var immune: Dictionary = _actions("taoist.entrapment", immune_context)[0]
	assert(int(immune.get("trapped_count", -1)) == 0, "scalar control immunity must still gate the locked target")


func _verify_friendly_partition() -> void:
	PlayerState.profession = "道士"
	var pet := SummonActor.new()
	pet.setup(_caster, Loader.display_name("taoist.summon_skeleton"), 3, 3, "taoist.summon_skeleton", PlayerState.level, 7)
	pet.configure_runtime_map_projection(
		int(_game.current_map_id), Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	pet.global_position = _screen(_anchor + Vector2i.UP)
	_game.add_child(pet)
	pet.set_physics_process(false)
	pet.current_hp = maxi(1, roundi(float(pet.max_hp) * 0.25))
	_caster.current_hp = maxi(1, roundi(float(_caster.max_hp) * 0.5))
	_game._selected_friendly_instance_id = pet.get_instance_id()
	for skill_id: String in ["taoist.mass_healing", "taoist.magic_defense", "taoist.mass_invisibility"]:
		_lock(_center)
		var count_before := _query_count()
		var context := _context(skill_id, {
			"target_tile": _anchor, "origin_tile": _anchor,
			"friendly_candidates": _game._canonical_friendly_candidates(),
			"caster_ground_position_gu": Vector2(_anchor),
		})
		assert(_query_count() == count_before)
		assert(context.get("targets", []).is_empty())
		assert(bool(context.get("friendly", false)) and not bool(context.get("hostile", true)))
		var friend_ids: Array = context.get("friendly_target_instance_ids", [])
		assert(friend_ids.has(_caster.get_instance_id()) and friend_ids.has(pet.get_instance_id()))
		assert(not friend_ids.has(_center.get_instance_id()) and not friend_ids.has(_boundary.get_instance_id()))
		_caster.current_mp = 9999
		_lock(_center)
		count_before = _query_count()
		var result: Dictionary = _game._execute_canonical_skill(
			skill_id, _caster.global_position, Vector2.RIGHT, 0, {}, false, true,
		)
		assert(bool(result.get("accepted", false)), "formal support entry rejected: " + str(result.get("reason", "")))
		assert(_query_count() == count_before, "friendly release must not query hostile candidates")
		var affected: Array[int] = []
		for action: Dictionary in result.get("canonical_plan", {}).get("gameplay_actions", []):
			var single_id := int(action.get("target_instance_id", 0))
			if single_id > 0:
				affected.append(single_id)
			for raw_id: Variant in action.get("target_instance_ids", []):
				affected.append(int(raw_id))
		assert(affected.has(_caster.get_instance_id()) and affected.has(pet.get_instance_id()))
		assert(not affected.has(_center.get_instance_id()) and not affected.has(_boundary.get_instance_id()))
	pet.free()


func _verify_real_wall_probe_partition() -> void:
	var wall_fixture := _find_wall_fixture()
	var origin_cell: Vector2i = wall_fixture["origin"]
	var candidate_cell: Vector2i = wall_fixture["candidate"]
	var center_cell: Vector2i = wall_fixture["center"]
	_game._set_player_world_position(_screen(origin_cell))
	_center.set_combat_position(_screen(candidate_cell), &"test_context_authored_wall")
	_boundary.set_combat_position(_screen(center_cell), &"test_context_boundary_center")
	_lock(_center)
	var push_context := _context("wizard.repulsion_ring", {"force_success": true})
	var blocked_record := _record(push_context, _center)
	assert(not blocked_record.is_empty() and bool(blocked_record.get("path_blocked", false)))
	var blocked_push := _action_for(_actions("wizard.repulsion_ring", push_context), _center.get_instance_id())
	assert(bool(blocked_push.get("eligible", false)))
	assert(not bool(blocked_push.get("displaced", true)), "authored wall must still prevent repulsion")
	_lock(_boundary)
	var boundary_context := _context("taoist.entrapment")
	var unprobed_record := _record(boundary_context, _center)
	assert(not unprobed_record.is_empty(), "same wall-side monster must intersect the trap boundary")
	assert(not bool(unprobed_record.get("path_blocked", true)), "entrapment must not inherit the repulsion wall probe")
	var trap: Dictionary = _actions("taoist.entrapment", boundary_context)[0]
	assert(trap.get("target_instance_ids", []) == [_boundary.get_instance_id()])


func _find_wall_fixture() -> Dictionary:
	# Real point authority only. Cache avoids repeating the bounded map search.
	# O -> adjacent candidate -> wall; the trap center is perpendicular to the
	# candidate, so that same candidate belongs to the trap's boundary list.
	for radius: int in range(0, 25):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var origin := _anchor + Vector2i(x, y)
				if not _open_cell(origin):
					continue
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					var candidate := origin + direction
					if not _open_cell(candidate) or not _point_blocked(origin + direction * 2):
						continue
					var perpendicular := Vector2i(-direction.y, direction.x)
					for sign_value: int in [-1, 1]:
						var center := candidate + perpendicular * sign_value
						if _open_cell(center):
							return {"origin": origin, "candidate": candidate, "center": center}
	assert(false, "authored map lacks the required wall-side control fixture")
	return {}
