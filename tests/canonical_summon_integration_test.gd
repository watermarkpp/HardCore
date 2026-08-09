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
	PlayerState.inventory = [{"name": "护身符", "count": 20}]
	var skill_name := ProfessionRules.skill_display_name(
		"taoist.summon_skeleton"
	)
	PlayerState.learned_skills = {skill_name: 3}
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

	# Force the nearest candidate to be occupied. The authority must choose the
	# next deterministic legal grid point, still within radius <= 2 GU.
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

	var first_result: Dictionary = _game._execute_canonical_skill(
		skill_name,
		_player.global_position,
		_player.facing,
		0,
		{"release_id": "test:summon:spawn"}
	)
	assert(bool(first_result.get("accepted", false)), "canonical summon rejected")
	var first_plan: Dictionary = first_result.get("canonical_plan", {})
	var first_descriptors: Array = first_plan.get("summon_descriptors", [])
	assert(first_descriptors.size() == 1, "summon descriptor missing")
	var spawn_descriptor: Dictionary = first_descriptors[0]
	assert(str(spawn_descriptor.get("operation", "")) == "main_pet_spawn")
	var pet: SummonActor = _game._canonical_main_pet()
	assert(pet != null, "main-pet spawn descriptor did not create a pet")
	var pet_id := pet.get_instance_id()
	assert(
		pet.summon_exp_level
		== int(spawn_descriptor.get("initial_pet_level", -1)),
		"initial pet level was not preserved from the canonical descriptor"
	)
	assert(
		pet.maximum_pet_level == int(spawn_descriptor.get("max_pet_level", -1)),
		"maximum pet level was not preserved from the canonical descriptor"
	)
	var spawn_snapshot: Dictionary = spawn_descriptor.get(
		"spawn_footprint_snapshot", {}
	)
	assert(
		pet.global_position == _game._canonical_ground_gu_to_screen_px(
			spawn_snapshot.get("target_center_ground_gu", Vector2.INF)
		),
		"pet did not consume the canonical spawn snapshot"
	)

	# Recasting with a live main pet is recall-only: same instance, no new node,
	# and resource_commit_required=false means neither mana nor amulet is spent.
	pet.global_position += Vector2(600.0, 600.0)
	var recall_mp_before := _player.current_mp
	var recall_amulet_before := PlayerState.item_count("护身符")
	var summon_count_before := _summon_actor_count()
	var recall_result: Dictionary = _game._execute_canonical_skill(
		skill_name,
		_player.global_position,
		_player.facing,
		0,
		{"release_id": "test:summon:recall"}
	)
	var recall_plan: Dictionary = recall_result.get("canonical_plan", {})
	var recall_descriptors: Array = recall_plan.get("summon_descriptors", [])
	assert(recall_descriptors.size() == 1)
	assert(
		str((recall_descriptors[0] as Dictionary).get("operation", ""))
		== "recall_existing_main_pet"
	)
	assert(not bool(recall_plan.get("resource_commit_required", true)))
	assert(_game._canonical_main_pet().get_instance_id() == pet_id)
	assert(_summon_actor_count() == summon_count_before, "recall created a new pet")
	assert(_player.current_mp == recall_mp_before, "recall spent mana")
	assert(
		PlayerState.item_count("护身符") == recall_amulet_before,
		"recall spent an amulet"
	)

	# Fill every candidate in the exact radius-2 search after removing the pet.
	pet.queue_free()
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
	assert(not bool(blocked_plan.get("valid", true)), "occupied radius-2 search accepted a tile")
	var blocked_mp_before := _player.current_mp
	var blocked_amulet_before := PlayerState.item_count("护身符")
	var blocked_result: Dictionary = _game._execute_canonical_skill(
		skill_name,
		_player.global_position,
		_player.facing,
		0,
		{"release_id": "test:summon:blocked"}
	)
	var blocked_canonical_plan: Dictionary = blocked_result.get(
		"canonical_plan", {}
	)
	assert(not bool(blocked_canonical_plan.get("resource_commit_required", true)))
	assert(_game._canonical_main_pet() == null, "blocked no-op created a pet")
	assert(_player.current_mp == blocked_mp_before, "blocked no-op spent mana")
	assert(
		PlayerState.item_count("护身符") == blocked_amulet_before,
		"blocked no-op spent an amulet"
	)

	print(
		"CANONICAL_SUMMON_INTEGRATION_PASS: radius-2 placement, descriptor "
		+ "levels/snapshot, recall identity, and blocked no-op resources"
	)
	get_tree().quit(0)


func _add_blocker(ground_position_gu: Vector2) -> void:
	var blocker := Node2D.new()
	_game.add_child(blocker)
	blocker.add_to_group("summons")
	blocker.global_position = _game._canonical_ground_gu_to_screen_px(
		ground_position_gu
	)
	_blockers.append(blocker)


func _summon_actor_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if node is SummonActor:
			count += 1
	return count
