extends Node

const SummonActorScript := preload("res://scripts/summon_actor.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## The production relocation boundary is exercised after an actual same-map
## random-teleport endpoint and again as the final map-arrival boundary.  The
## test deliberately seeds stale target/attack/motion state so a pet cannot
## pass by merely changing its position.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"召唤骷髅": 3,
		"召唤神兽": 3,
	}
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				game.player.global_position + Vector2(4000.0, 4000.0),
				&"summon_owner_teleport_fixture_clear"
			)

	var stale_enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(38),
		game.player.global_position + Vector2(2000.0, 2000.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_group_id": "summon_owner_teleport_stale_target"}
	)
	assert(stale_enemy != null, "stale summon-target fixture failed to spawn")
	var skeleton := _make_main_pet(
		game,
		"骷髅",
		"taoist.summon_skeleton",
		Vector2(800.0, 300.0),
		37
	)
	var divine_beast := _make_main_pet(
		game,
		"神兽",
		"taoist.summon_divine_beast",
		Vector2(-700.0, 450.0),
		53
	)
	await get_tree().process_frame
	_seed_stale_state(skeleton, stale_enemy)
	_seed_stale_state(divine_beast, stale_enemy)
	var skeleton_hp := skeleton.current_hp
	var divine_hp := divine_beast.current_hp
	var random_destination: Vector2 = game._find_valid_random_teleport_position(
		game.player.global_position
	)
	assert(
		not random_destination.is_equal_approx(game.player.global_position),
		"same-map random teleport fixture has no legal destination"
	)
	assert(
		game._apply_canonical_player_teleport(random_destination),
		"same-map random teleport did not reach its legal final endpoint"
	)
	_assert_relocated_pet(game, skeleton, skeleton_hp)
	_assert_relocated_pet(game, divine_beast, divine_hp)
	_assert_pet_pair_legal(game, skeleton, divine_beast)

	# Re-seed the stale state and invoke the shared map-arrival finalizer directly.
	# This models the cross-map caller after _load_zone/portal has installed the
	# player's final position; placement remains the canonical legal-plan search.
	# This published-map tile is a legal player landing, but its narrow nearby
	# footprint has exposed a second-pet relocation failure in actual runs.
	var arrival: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(13.5, 78.5))
	assert(
		not WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			game.background, arrival, ArtSpec.PLAYER_COLLISION_RADIUS_PX
		),
		"map-arrival fixture must be a legal player landing"
	)
	game.player.global_position = arrival
	skeleton.global_position = arrival + Vector2(800.0, 300.0)
	divine_beast.global_position = arrival + Vector2(-700.0, 450.0)
	_seed_stale_state(skeleton, stale_enemy)
	_seed_stale_state(divine_beast, stale_enemy)
	game._relocate_main_pets_after_map_arrival()
	_assert_relocated_pet(game, skeleton, skeleton_hp)
	_assert_relocated_pet(game, divine_beast, divine_hp)
	_assert_pet_pair_legal(game, skeleton, divine_beast)
	assert(
		game.current_map_id == skeleton.runtime_map_id
		and game.current_map_id == divine_beast.runtime_map_id,
		"map-arrival relocation did not install the current map projection"
	)

	# If every nearby landing is temporarily occupied, the pet must stop its
	# stale attack and leave collision until the owner reaches another tile.
	_seed_stale_state(divine_beast, stale_enemy)
	divine_beast.defer_owner_teleport_relocation()
	assert(divine_beast.owner_teleport_pending)
	assert(not divine_beast.visible and divine_beast.collision_layer == 0)
	assert(divine_beast.state == SummonActor.SummonState.FOLLOW_OWNER)
	assert(divine_beast._current_target == null)
	assert(divine_beast._pending_attack_target == null)
	var lifetime_before_retry := divine_beast.remaining_lifetime
	divine_beast._physics_process(1.0 / 60.0)
	assert(divine_beast.remaining_lifetime < lifetime_before_retry)
	assert(divine_beast.owner_teleport_pending and divine_beast.current_hp == divine_hp)
	game._pending_main_pet_arrivals.clear()
	game._pending_main_pet_arrivals.append(divine_beast)
	game._pending_main_pet_retry_tile = game._main_pet_owner_tile()
	game._pending_main_pet_retry_tile_valid = true
	game.player.global_position = random_destination
	game._retry_pending_main_pet_arrivals()
	_assert_relocated_pet(game, divine_beast, divine_hp)
	assert(not divine_beast.owner_teleport_pending)
	assert(divine_beast.visible and divine_beast.collision_layer != 0)
	assert(game._pending_main_pet_arrivals.is_empty())

	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"SUMMON_OWNER_TELEPORT_RUNTIME_PASS: random and map-arrival endpoints "
		+ "relocate both main pets legally while preserving HP and clearing combat state"
	)
	get_tree().quit(0)


func _make_main_pet(
	game: Node,
	display_name: String,
	skill_id: String,
	stale_position: Vector2,
	hp_loss: int
) -> SummonActor:
	var summon := SummonActorScript.new()
	summon.setup(game.player, display_name, 40, 3, skill_id, PlayerState.level)
	summon.set_meta("taoist_main_pet", true)
	summon.set_meta("taoist_main_pet_contract", "skills.taoist_main_pet.v2")
	summon.configure_runtime_map_projection(
		game.current_map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu")
	)
	summon.configure_spatial_index(game._combat_spatial_index)
	summon.global_position = game.player.global_position + stale_position
	summon.current_hp = maxi(1, summon.max_hp - hp_loss)
	game.add_child(summon)
	return summon


func _seed_stale_state(summon: SummonActor, stale_enemy: EnemyActor) -> void:
	summon._current_target = stale_enemy
	summon._pending_attack_target = stale_enemy
	summon._pending_attack_snapshot = {"release_id": "stale-before-owner-teleport"}
	summon._pending_attack_release_remaining = 0.6
	summon.velocity = Vector2(80.0, -35.0)
	summon.actual_ground_motion_gu = Vector2(1.0, 0.25)
	summon.state = SummonActor.SummonState.CHASE_TARGET


func _assert_relocated_pet(game: Node, summon: SummonActor, expected_hp: int) -> void:
	assert(summon.current_hp == expected_hp, "%s HP changed during owner relocation" % summon.summon_id)
	assert(summon.state == SummonActor.SummonState.FOLLOW_OWNER)
	assert(summon.velocity.is_zero_approx())
	assert(summon.actual_ground_motion_gu.is_zero_approx())
	assert(summon._current_target == null)
	assert(summon._pending_attack_target == null)
	assert(summon._pending_attack_snapshot.is_empty())
	assert(summon.runtime_map_id == game.current_map_id)
	assert(summon.projection_ready())
	var player_ground: Vector2 = game._canonical_screen_px_to_ground_gu(
		Vector2(game.player.global_position)
	)
	var summon_ground: Vector2 = game._canonical_screen_px_to_ground_gu(
		Vector2(summon.global_position)
	)
	assert(
		GroundUnitSpace.distance_gu(player_ground, summon_ground) <= 4.0,
		"relocated %s is not adjacent to final owner position" % summon.summon_id
	)


func _assert_pet_pair_legal(game: Node, a: SummonActor, b: SummonActor) -> void:
	var a_ground: Vector2 = game._canonical_screen_px_to_ground_gu(a.global_position)
	var b_ground: Vector2 = game._canonical_screen_px_to_ground_gu(b.global_position)
	assert(
		GroundUnitSpace.distance_gu(a_ground, b_ground)
		>= a.combat_radius_gu + b.combat_radius_gu,
		"teleported pets overlap each other's body"
	)
	for pet: SummonActor in [a, b]:
		assert(
			not WorldSpatialRulesScript.environment_blocks_actor_screen_px(
				game.background, pet.global_position, pet.collision_radius_px
			),
			"teleported pet landed inside world collision"
		)
