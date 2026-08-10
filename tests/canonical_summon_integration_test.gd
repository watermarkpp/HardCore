extends Node

var _game: Node
var _player: PlayerCharacter
var _blockers: Array[Node2D] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	var skeleton_skill_name := ProfessionRules.skill_display_name(
		"taoist.summon_skeleton"
	)
	var divine_skill_name := ProfessionRules.skill_display_name(
		"taoist.summon_divine_beast"
	)
	PlayerState.learned_skills = {
		skeleton_skill_name: 3,
		divine_skill_name: 3,
	}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _game.player
	_player.set_physics_process(false)
	_player.global_position = Vector2(240.0, 240.0)
	_player.facing = Vector2.RIGHT
	_player.current_mp = 999
	for raw_enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if raw_enemy is Node2D:
			(raw_enemy as Node2D).global_position += Vector2(5000.0, 5000.0)

	# The exact radius-2 authority skips an occupied nearest cell and chooses the
	# next deterministic legal point.
	var nearest_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	assert(bool(nearest_plan.get("valid", false)), "no initial summon candidate")
	var nearest_ground: Vector2 = nearest_plan.position_ground_gu
	_add_blocker(nearest_ground)
	var alternative_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	assert(bool(alternative_plan.get("valid", false)), "radius-2 search found no alternative")
	assert(alternative_plan.position_ground_gu != nearest_ground)
	assert(
		alternative_plan.position_ground_gu.distance_to(
			alternative_plan.desired_ground_gu
		) <= 2.0001,
		"chosen summon point escaped the canonical radius-2 search"
	)

	# Matrix 1: neither type exists, so the requested skeleton is created.
	var first_result: Dictionary = _cast(
		skeleton_skill_name, "test:summon:spawn:skeleton"
	)
	assert(bool(first_result.get("accepted", false)), "canonical summon rejected")
	var first_plan: Dictionary = first_result.get("canonical_plan", {})
	var first_descriptors: Array = first_plan.get("summon_descriptors", [])
	assert(first_descriptors.size() == 1, "summon descriptor missing")
	var spawn_descriptor: Dictionary = first_descriptors[0]
	assert(str(spawn_descriptor.get("operation", "")) == "main_pet_spawn")
	var skeleton: SummonActor = _game._canonical_main_pet("skeleton")
	assert(skeleton != null, "skeleton descriptor did not create a skeleton")
	var skeleton_id := skeleton.get_instance_id()
	assert(
		skeleton.summon_exp_level
		== int(spawn_descriptor.get("initial_pet_level", -1))
	)
	assert(
		skeleton.maximum_pet_level
		== int(spawn_descriptor.get("max_pet_level", -1))
	)
	var spawn_snapshot: Dictionary = spawn_descriptor.get(
		"spawn_footprint_snapshot", {}
	)
	assert(
		skeleton.global_position == _game._canonical_ground_gu_to_screen_px(
			spawn_snapshot.get("target_center_ground_gu", Vector2.INF)
		),
		"skeleton did not consume the canonical spawn snapshot"
	)

	# Matrix 2: recasting skeleton recalls that exact instance. Its gameplay
	# snapshot and resources remain unchanged.
	skeleton.current_hp = skeleton.max_hp - 17
	skeleton.pet_growth_exp = 123
	skeleton.remaining_lifetime = 4321.5
	skeleton.apply_stealth(11.0, "buff.test.skeleton.stealth")
	skeleton.apply_ac_buff(3, 12.0, "buff.test.skeleton.ac")
	skeleton.apply_mac_buff(4, 13.0, "buff.test.skeleton.mac")
	skeleton.set_process(false)
	skeleton.set_physics_process(false)
	var skeleton_state_before_recall := skeleton.persistence_snapshot()
	skeleton.global_position += Vector2(600.0, 600.0)
	var distant_skeleton_position := skeleton.global_position
	_player.current_mp = 0
	assert(
		_game._try_release_skill(skeleton_skill_name, false) == &"accepted",
		"zero-MP same-type recall was rejected by production preflight"
	)
	var recall_deadline_ms := Time.get_ticks_msec() + 3000
	while (
		skeleton.global_position == distant_skeleton_position
		and Time.get_ticks_msec() < recall_deadline_ms
	):
		await get_tree().process_frame
	assert(
		skeleton.global_position != distant_skeleton_position,
		"production skill release did not recall the skeleton"
	)
	var recall_result: Dictionary = _cast(
		skeleton_skill_name, "test:summon:recall:skeleton"
	)
	var recall_plan: Dictionary = recall_result.get("canonical_plan", {})
	var recall_quote: Dictionary = recall_plan.get("resource_cost", {})
	assert(_descriptor_operation(recall_plan) == "recall_existing_main_pet")
	assert(not bool(recall_plan.get("resource_commit_required", true)))
	assert(int(recall_quote.get("mp_cost", -1)) == 0)
	assert(str(recall_quote.get("material_id", "")) == "")
	assert(int(recall_quote.get("material_amount", -1)) == 0)
	assert(bool(recall_quote.get("main_pet_recall", false)))
	assert(
		str(recall_quote.get("main_pet_recall_resource_contract_id", ""))
		== "skills.taoist.main_pet.recall_resource.v1"
	)
	assert(_game._canonical_main_pet("skeleton").get_instance_id() == skeleton_id)
	assert(_live_main_pet_count() == 1, "same-type recall created a duplicate")
	assert(skeleton.persistence_snapshot() == skeleton_state_before_recall)
	assert(_player.current_mp == 0, "same-type recall spent mana")

	# Matrix 3: the other summon type is independent. Divine Beast spawns while
	# the skeleton remains alive and byte-for-byte unchanged. The existing other
	# type does not waive the new Divine Beast's normal MP requirement.
	var skeleton_state_before_divine := skeleton.persistence_snapshot()
	var insufficient_divine_result: Dictionary = _cast(
		divine_skill_name, "test:summon:insufficient:divine"
	)
	assert(not bool(insufficient_divine_result.get("accepted", true)))
	assert(
		str(insufficient_divine_result.get("reason", "")) == "insufficient_resource",
		"unexpected low-MP rejection: %s" % str(insufficient_divine_result)
	)
	assert(_game._canonical_main_pet("divine_beast") == null)
	assert(_game._canonical_main_pet("skeleton").get_instance_id() == skeleton_id)
	_player.current_mp = 999
	var divine_result: Dictionary = _cast(
		divine_skill_name, "test:summon:spawn:divine"
	)
	assert(bool(divine_result.get("accepted", false)))
	assert(
		_descriptor_operation(divine_result.get("canonical_plan", {}))
		== "main_pet_spawn"
	)
	var divine: SummonActor = _game._canonical_main_pet("divine_beast")
	assert(divine != null and divine.get_instance_id() != skeleton_id)
	assert(_live_main_pet_count() == 2, "two summon types did not coexist")
	assert(skeleton.persistence_snapshot() == skeleton_state_before_divine)

	divine.current_hp = divine.max_hp - 23
	divine.pet_growth_exp = 77
	divine.remaining_lifetime = 3210.25
	divine.apply_stealth(9.0, "buff.test.divine.stealth")
	var divine_id := divine.get_instance_id()
	var divine_state_before_recall := divine.persistence_snapshot()
	var divine_recall_mp_before := _player.current_mp
	var divine_recall_result: Dictionary = _cast(
		divine_skill_name, "test:summon:recall:divine"
	)
	var divine_recall_plan: Dictionary = divine_recall_result.get(
		"canonical_plan", {}
	)
	assert(_descriptor_operation(divine_recall_plan) == "recall_existing_main_pet")
	assert(not bool(divine_recall_plan.get("resource_commit_required", true)))
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == divine_id)
	assert(divine.persistence_snapshot() == divine_state_before_recall)
	assert(_player.current_mp == divine_recall_mp_before)

	# Matrix 4: killing one type clears/rebuilds only that slot. The other type
	# stays the same instance with the same state.
	var divine_state_before_skeleton_death := divine.persistence_snapshot()
	skeleton.take_damage(skeleton.current_hp + 9999)
	assert(_game._canonical_main_pet("skeleton") == null)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == divine_id)
	var replacement_result: Dictionary = _cast(
		skeleton_skill_name, "test:summon:replace:dead_skeleton"
	)
	assert(bool(replacement_result.get("accepted", false)))
	var replacement_skeleton: SummonActor = _game._canonical_main_pet("skeleton")
	assert(replacement_skeleton != null)
	assert(replacement_skeleton.get_instance_id() != skeleton_id)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == divine_id)
	assert(divine.persistence_snapshot() == divine_state_before_skeleton_death)
	assert(_live_main_pet_count() == 2)

	# Dual-pet persistence keeps the two typed slots isolated, restores both, and
	# remains idempotent when restoration is requested again.
	replacement_skeleton.current_hp = replacement_skeleton.max_hp - 31
	replacement_skeleton.pet_growth_exp = 211
	replacement_skeleton.remaining_lifetime = 2876.25
	replacement_skeleton.apply_ac_buff(6, 18.0, "buff.test.restore.skeleton.ac")
	divine.current_hp = divine.max_hp - 41
	divine.pet_growth_exp = 322
	divine.remaining_lifetime = 1987.5
	divine.apply_mac_buff(7, 19.0, "buff.test.restore.divine.mac")
	replacement_skeleton.set_process(false)
	replacement_skeleton.set_physics_process(false)
	divine.set_process(false)
	divine.set_physics_process(false)
	var persisted_states: Dictionary = (
		_game._capture_taoist_main_pet_runtime_states()
	)
	var persisted_slots: Dictionary = persisted_states.get("slots", {})
	assert(persisted_slots.size() == 2)
	var restore_mp_before := _player.current_mp
	var old_skeleton_id := replacement_skeleton.get_instance_id()
	var old_divine_id := divine.get_instance_id()
	var transition_map_data: Dictionary = _game.current_map_data.duplicate(true)
	assert(not transition_map_data.is_empty(), "map transition fixture has no map")
	var transition_zone_name := "%s:dual-pet-restore" % _game.current_zone
	_game._load_zone(transition_zone_name, false, transition_map_data)
	var restored_skeleton: SummonActor = _game._canonical_main_pet("skeleton")
	var restored_divine: SummonActor = _game._canonical_main_pet("divine_beast")
	assert(restored_skeleton != null and restored_divine != null)
	assert(restored_skeleton.get_instance_id() != old_skeleton_id)
	assert(restored_divine.get_instance_id() != old_divine_id)
	assert(restored_skeleton.persistence_snapshot() == persisted_slots["skeleton"])
	assert(restored_divine.persistence_snapshot() == persisted_slots["divine_beast"])
	var restored_skeleton_id := restored_skeleton.get_instance_id()
	var restored_divine_id := restored_divine.get_instance_id()
	await get_tree().process_frame
	assert(not _game._restore_persisted_taoist_main_pet_if_needed())
	assert(_game._canonical_main_pet("skeleton").get_instance_id() == restored_skeleton_id)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == restored_divine_id)
	assert(_live_main_pet_count() == 2)
	assert(_player.current_mp == restore_mp_before, "restore spent mana")

	# A blocked skeleton spawn stays a no-op even while Divine Beast survives;
	# the live other-type summon is not removed or treated as the blocker.
	PlayerState.clear_taoist_main_pet_runtime_state("skeleton")
	restored_skeleton.queue_free()
	await get_tree().process_frame
	var open_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	var desired_ground: Vector2 = open_plan.get(
		"desired_ground_gu",
		_game._canonical_screen_px_to_ground_gu(_player.global_position)
	)
	var center_tile := Vector2i(roundi(desired_ground.x), roundi(desired_ground.y))
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var tile := center_tile + Vector2i(x, y)
			if Vector2(tile).distance_to(desired_ground) <= 2.0001:
				_add_blocker(Vector2(tile))
	var blocked_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	assert(not bool(blocked_plan.get("valid", true)))
	var blocked_mp_before := _player.current_mp
	var blocked_result: Dictionary = _cast(
		skeleton_skill_name, "test:summon:blocked:skeleton"
	)
	var blocked_canonical_plan: Dictionary = blocked_result.get(
		"canonical_plan", {}
	)
	assert(not bool(blocked_canonical_plan.get("resource_commit_required", true)))
	assert(_game._canonical_main_pet("skeleton") == null)
	assert(_game._canonical_main_pet("divine_beast").get_instance_id() == restored_divine_id)
	assert(_player.current_mp == blocked_mp_before)

	print(
		"CANONICAL_SUMMON_INTEGRATION_PASS: typed coexistence, same-type recall, "
		+ "isolated death replacement, dual persistence, idempotence, blocked no-op"
	)
	get_tree().quit(0)


func _cast(skill_name: String, release_id: String) -> Dictionary:
	return _game._execute_canonical_skill(
		skill_name,
		_player.global_position,
		_player.facing,
		0,
		{"release_id": release_id}
	)


func _descriptor_operation(plan: Dictionary) -> String:
	var descriptors: Array = plan.get("summon_descriptors", [])
	assert(descriptors.size() == 1)
	return str((descriptors[0] as Dictionary).get("operation", ""))


func _add_blocker(ground_position_gu: Vector2) -> void:
	var blocker := Node2D.new()
	_game.add_child(blocker)
	blocker.add_to_group("summons")
	blocker.global_position = _game._canonical_ground_gu_to_screen_px(
		ground_position_gu
	)
	_blockers.append(blocker)


func _live_main_pet_count() -> int:
	var count := 0
	for summon_id: String in ["skeleton", "divine_beast"]:
		if _game._canonical_main_pet(summon_id) != null:
			count += 1
	return count
