extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"hc.skill.warrior.basic_swordsmanship": 3,
		"hc.skill.warrior.slaying_swordsmanship": 3,
		"hc.skill.warrior.thrusting": 3,
		"hc.skill.warrior.half_moon": 3,
		"hc.skill.warrior.fire_sword": 3,
	}
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var ready_deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<ready_deadline:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "death boundary needs the formal mapped world READY")
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5,13.5)))
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				game.player.global_position + Vector2(3000, 3000),
				&"test_fixture_relocation",
			)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)

	var origin: Vector2 = game.player.global_position
	var axis_gu := Vector2(1.0, 0.35).normalized()
	var primary := _make_enemy(game, origin + _screen_offset_gu(axis_gu))
	var survivor := _make_enemy(
		game,
		origin + _screen_offset_gu(axis_gu.rotated(PI / 4.0))
	)
	await get_tree().physics_frame
	await get_tree().process_frame
	primary.current_hp = 1
	primary._refresh_overhead_health()
	var survivor_hp_before := survivor.current_hp
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["hc.slot.weapon"] = preload("res://scripts/item_drop_instance_rules.gd").create_instance(
		GameData.get_item_record({"item_id":80}), "aoe-death-boundary-weapon"
	)
	PlayerState.test_transaction_debug_reset()
	var wear_revision_before: int = PlayerState._durability_mutation_revision
	var wear_commits_before: int = PlayerState.durability_event_commit_count
	var death_events: Array[int] = []
	primary.died.connect(func(_enemy: EnemyActor, _data: Dictionary) -> void:
		death_events.append(1)
	)
	game.locked_target = primary
	game.player.half_moon_enabled = true
	game.player._pending_attack_context = {
		"mode": "half_moon",
		"selected_body_mode": "half_moon",
		"skill_name": "半月弯刀",
		"skill_level": 3,
		"release_geometry": ReleaseGeometry.resolve(
			origin,
			Vector2.DOWN,
			primary.get_instance_id(),
			primary.global_position,
			true,
			true,
			ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
	}

	# Observe the actual physics body and live cached candidate identity before
	# lethal damage. No await or death pump is allowed between the two queries.
	var body_shape := CircleShape2D.new()
	body_shape.radius = 0.5
	var body_query := PhysicsShapeQueryParameters2D.new()
	body_query.shape = body_shape
	body_query.transform = Transform2D(0.0, primary.global_position)
	body_query.collision_mask = WorldSpatialRules.ENEMY_LAYER
	var before_body := false
	for hit: Dictionary in game.player.get_world_2d().direct_space_state.intersect_shape(body_query):
		if hit.get("collider") == primary: before_body = true
	assert(before_body, "live fixture is a real physics blocker before lethal damage")
	var peer_start: Vector2 = survivor.spatial_index_position()
	var death_point: Vector2 = primary.spatial_index_position()
	assert(not survivor._hc_motion_clear(peer_start,death_point), "live peer blocks the measured route")
	var Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")
	assert(not Positions.available(survivor,game.player,death_point,[primary]), "live occupant owns the measured station")
	game._on_player_attack(origin, Vector2.DOWN, 200)
	assert(primary.current_hp == 0, "半月致死主目标没有归零")
	assert(survivor.current_hp < survivor_hp_before, "主目标死亡打断了同次半月的存活目标伤害")
	assert(primary._death_pending and not primary._dying, "死亡清理仍在范围伤害循环内同步执行")
	assert(death_events.is_empty(), "died 信号仍在范围伤害循环内同步发出")
	assert(primary.is_inside_tree() and not primary.is_queued_for_deletion(), "corpse is still held before deferred animation and retirement")
	for hit: Dictionary in game.player.get_world_2d().direct_space_state.intersect_shape(body_query):
		assert(hit.get("collider") != primary, "lethal damage immediately removes the native physics blocker")
	assert(survivor._hc_motion_clear(peer_start,death_point), "lethal damage opens the peer route in the same stack")
	assert(Positions.available(survivor,game.player,death_point,[primary]), "lethal damage releases the station in the same stack")
	assert(
		not primary.is_in_group("enemies")
		and primary.collision_layer == 0
		and primary.collision_mask == 0,
		"待处理死亡仍能在同帧阻挡投射物或进入后续范围候选"
	)
	assert(PlayerState._durability_mutation_revision == wear_revision_before+1,
		"one physical swing applies one wear event for all half-moon targets")
	assert(PlayerState.test_transaction_debug_snapshot().commit_attempts == 0
		and PlayerState._durability_save_pending,
		"the current coalesced wear contract does not synchronously save inside damage")

	await get_tree().process_frame
	assert(
		primary._dying and death_events.size() == 1,
		"禁用 physics 的对象没有在当前伤害栈结束后统一提交死亡"
	)

	var save_deadline := Time.get_ticks_msec()+3000
	while PlayerState._durability_save_pending and Time.get_ticks_msec()<save_deadline:
		await get_tree().process_frame
	assert(not PlayerState._durability_save_pending
		and PlayerState.durability_event_commit_count == wear_commits_before+1
		and PlayerState.test_transaction_debug_snapshot().commit_attempts == 1,
		"one pending wear event commits exactly once through the normal save interval")
	game.queue_free()
	await get_tree().process_frame
	print("AOE_DEATH_PHASE_BOUNDARY_PASS: all targets resolve before deferred death lifecycle")
	get_tree().quit(0)


func _screen_offset_gu(delta_ground_gu: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(delta_ground_gu)


func _make_enemy(game: Node, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(34), game.player, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	var serial: int = 700000 + game._combat_spatial_index.registered_actor_count()
	enemy.configure_runtime_map_projection(
		int(game.current_map_id),
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.configure_spatial_index(game._combat_spatial_index, serial)
	enemy.set_meta("spawn_serial", serial)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("spawn_position", position)
	enemy.set_meta("zone_generation", int(game._zone_generation))
	game.add_child(enemy)
	enemy.set_physics_process(false)
	game._combat_spatial_index.register(
		serial,
		int(game.current_map_id),
		game._canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	return enemy
