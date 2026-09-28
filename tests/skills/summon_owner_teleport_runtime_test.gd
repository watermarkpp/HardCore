extends Node

const SummonActorScript := preload("res://scripts/summon_actor.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const PortalRuntimeService := preload("res://scripts/map_editor/map_portal_runtime_service.gd")

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
	await _exercise_high_rank_multi_pet_teleport(game, stale_enemy, skeleton, divine_beast, arrival)

	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"SUMMON_OWNER_TELEPORT_RUNTIME_PASS: random and map-arrival endpoints "
		+ "relocate 2 and 9 main pets legally across same-map and map arrival"
	)
	get_tree().quit(0)


func _make_main_pet(
	game: Node,
	display_name: String,
	skill_id: String,
	stale_position: Vector2,
	hp_loss: int,
	pet_slot_index: int = 0,
) -> SummonActor:
	var summon := SummonActorScript.new()
	summon.setup(game.player, display_name, 40, 3, skill_id, PlayerState.level)
	summon.pet_slot_index = pet_slot_index
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


func _exercise_high_rank_multi_pet_teleport(
	game: Node,
	stale_enemy: EnemyActor,
	first_skeleton: SummonActor,
	divine_beast: SummonActor,
	narrow_arrival: Vector2,
) -> void:
	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"all": 2}, "legacy": {},
	}
	assert(PlayerState.effective_skill_level("召唤骷髅") == 5)
	assert(SkillRankResolver.skeleton_count(5) == 2)
	_make_main_pet(
		game, "骷髅", "taoist.summon_skeleton",
		Vector2(940.0, 300.0), 21, 1,
	)
	await get_tree().process_frame
	game._synchronize_main_pet_skill_ranks()
	var three_before: Dictionary = {}
	for pet: SummonActor in game._canonical_main_pets():
		_seed_stale_state(pet, stale_enemy)
		three_before[_pet_key(pet)] = pet.current_hp
	assert(three_before.size() == 3)
	assert(game._apply_canonical_player_teleport(narrow_arrival))
	_assert_multi_pet_arrival(game, three_before)
	assert(game._canonical_main_pets("skeleton").size() == 2)
	assert(game._canonical_main_pets("divine_beast").size() == 1)

	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"all": 14}, "legacy": {},
	}
	assert(PlayerState.effective_skill_level("召唤骷髅") == 17)
	assert(SkillRankResolver.skeleton_count(17) == 8)
	for slot: int in range(2, 8):
		_make_main_pet(
			game, "骷髅", "taoist.summon_skeleton",
			Vector2(900.0 + slot * 40.0, 300.0), 20 + slot, slot,
		)
	await get_tree().process_frame
	game._synchronize_main_pet_skill_ranks()
	var before: Dictionary = {}
	var pets: Array[SummonActor] = game._canonical_main_pets()
	assert(pets.size() == 9)
	for pet: SummonActor in pets:
		_seed_stale_state(pet, stale_enemy)
		before[_pet_key(pet)] = pet.current_hp
	var high_rank_destination: Vector2 = game._find_valid_random_teleport_position(narrow_arrival)
	assert(not high_rank_destination.is_equal_approx(narrow_arrival))
	assert(game._apply_canonical_player_teleport(high_rank_destination))
	_assert_multi_pet_arrival(game, before)
	assert(game._canonical_main_pets("skeleton").size() == 8)
	assert(game._canonical_main_pets("divine_beast").size() == 1)
	assert(game._canonical_main_pets("skeleton")[0] == first_skeleton)
	assert(game._canonical_main_pets("divine_beast")[0] == divine_beast)

	# Loading another formal map restores the saved slots before the portal
	# installs its final destination. Every slot must survive that provisional
	# placement, even when the initial point has no legal body space.
	var target_map_id := 916004
	var target_map_data: Dictionary = game._runtime_named_map_data(
		GameData.get_map_by_id(target_map_id)
	)
	assert(not target_map_data.is_empty())
	game._load_zone("multi-pet-arrival", false, target_map_data)
	assert(game.current_map_id == target_map_id)
	# Reproduce a saved slot with no live provisional actor. The final arrival
	# must rebuild that slot from its preserved snapshot, never silently drop it.
	var provisional_pets: Array[SummonActor] = game._canonical_main_pets()
	if not provisional_pets.is_empty():
		provisional_pets[provisional_pets.size() - 1].queue_free()
	assert(game._canonical_main_pets().size() < 9)
	var runtime: Dictionary = MapEditorRuntimeBridge.load_map(target_map_id)
	var endpoint: Dictionary = PortalRuntimeService.endpoint_by_id(runtime, "map_exit_000001")
	assert(not endpoint.is_empty())
	var tile: Array = endpoint.get("tile", [])
	assert(tile.size() == 2)
	var destination_ground_gu: Vector2 = MapEditorRuntimeBridge.cell_to_ground_position_gu(tile)
	var destination: Vector2 = game._canonical_ground_gu_to_screen_px(destination_ground_gu)
	assert(not WorldSpatialRulesScript.environment_blocks_actor_screen_px(
		game.background, destination, ArtSpec.PLAYER_COLLISION_RADIUS_PX
	))
	game._set_player_world_position(destination)
	game._relocate_main_pets_after_map_arrival()
	_assert_multi_pet_arrival(game, before)
	await get_tree().process_frame
	# Ordinary formation movement can pass through allied bodies by its existing
	# collision contract. The arrival itself must be legal, and no slot may be
	# lost when the following physics frame starts that movement.
	assert(game._canonical_main_pets().size() == 9)
	for pet: SummonActor in game._canonical_main_pets():
		assert(pet.current_hp == int(before.get(_pet_key(pet), -1)))
		assert(pet.runtime_map_id == target_map_id)


func _pet_key(pet: SummonActor) -> String:
	return "%s:%d" % [pet.summon_id, pet.pet_slot_index]


func _assert_multi_pet_arrival(game: Node, expected_hp: Dictionary) -> void:
	var pets: Array[SummonActor] = game._canonical_main_pets()
	assert(pets.size() == expected_hp.size(), "owner arrival lost a summon slot")
	var seen: Dictionary = {}
	for pet: SummonActor in pets:
		var key := _pet_key(pet)
		assert(not seen.has(key), "owner arrival duplicated a summon slot")
		seen[key] = true
		assert(pet.current_hp == int(expected_hp.get(key, -1)), "%s HP changed" % key)
		assert(pet.runtime_map_id == game.current_map_id)
		assert(pet._current_target == null and pet._pending_attack_target == null)
		if pet.owner_teleport_pending:
			assert(not pet.visible and pet.collision_layer == 0 and pet.collision_mask == 0)
			continue
		assert(pet.visible and pet.collision_layer != 0)
		var ground_gu: Vector2 = game._canonical_screen_px_to_ground_gu(pet.global_position)
		assert(game._canonical_summon_position_is_valid(
			ground_gu, pet.combat_radius_gu, pet
		), "%s overlaps terrain, owner, enemy or another pet" % key)
	assert(seen.size() == expected_hp.size())


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
