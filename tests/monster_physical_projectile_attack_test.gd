extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const TerrainPolicy := preload("res://scripts/monster_terrain_navigation_policy.gd")
const SnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const ProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

var _descriptors: Array[Dictionary] = []
var _blocked_world_px := Vector2.INF


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_assert_authoritative_archer_profiles()
	_assert_id50_identity_bridge()
	for monster_id: int in [42, 50, 62, 145, 150, 152, 174, 186, 206]:
		await _assert_actual_actor_delivery(monster_id)
	print(
		"MONSTER_PHYSICAL_PROJECTILE_ATTACK_PASS "
		+ "exact_actors=42,50,62,145,150,152,174,186,206 release_after_frame=1 "
		+ "dodge=1 contact_once=1 cross_map_cancel=1 "
		+ "combat_epoch_cancel=1 can_fly_block=1"
	)
	get_tree().quit(0)


func _assert_actual_actor_delivery(monster_id: int) -> void:
	_descriptors.clear()
	_blocked_world_px = Vector2.INF

	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	# This delivery fixture needs a hit; exercise the real evasion roll with a
	# deterministic non-evading seed, not the actor's randomize() startup seed.
	var reference := RandomNumberGenerator.new()
	var hit_seed := 1
	while true:
		reference.seed = hit_seed
		if reference.randi_range(0, 9) == 9: break
		hit_seed += 1

	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(monster_id), player, false)
	attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.configure_terrain_navigation_context(_empty_terrain_context())
	attacker.environment_blocker = self
	attacker.ranged_projectile_requested.connect(_capture_descriptor)
	add_child(attacker)
	attacker.set_physics_process(false)
	await get_tree().process_frame
	# This fixture verifies delivery, not target acquisition. Keep the intended
	# target explicit under the formal terrain-context contract.
	attacker.target = player
	attacker.attack_min = 7
	attacker.attack_max = 7
	attacker._attack_timer = 0.0

	var hp_before := player.current_hp
	attacker._physics_process(0.01)
	assert(_descriptors.is_empty(), "projectile must wait for the source attack frame")
	assert(attacker._pending_attack_release_record.get("kind", "") == "physical_projectile_windup")
	_advance_release(attacker)
	assert(_descriptors.size() == 1, "monsterId=%d release must emit exactly one projectile" % monster_id)
	assert(player.current_hp == hp_before, "monsterId=%d projectile must not deal instant melee damage" % monster_id)
	assert(attacker._pending_attack_release_record.is_empty())
	var descriptor := _descriptors[0]
	assert(str(descriptor.get("effect_id", "")) == ProjectileEffectScript.EFFECT_ID)
	assert(str(descriptor.get("damage_owner", "")) == "enemy.physical_projectile_release")
	assert(not bool(descriptor.get("presentation_only", true)))
	var snapshot: Dictionary = descriptor.get("footprint_snapshot", {})
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_SWEPT_CAPSULE_PATH)
	assert(str(snapshot.get("projection_relationship_id", "")) == "projectile_sweep")
	assert(is_equal_approx(float(descriptor.get("duration_seconds", 0.0)), 0.2688), str(descriptor.get("duration_seconds")))
	var effect: Node2D = _find_projectile_effect()
	assert(effect != null, "accepted projectile release did not create its visual")
	effect.set_physics_process(false)
	effect.call("_physics_process", 0.1344)
	assert(is_equal_approx(float(effect.call("progress_ratio")), 0.5))
	# A lateral dodge after launch breaks actual contact; the old locked-ID
	# timer would still have damaged this player.
	player.global_position = _ground_to_screen(Vector2(4.0, 3.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	effect.call("_physics_process", 0.2)
	attacker._physics_process(0.3)
	assert(player.current_hp == hp_before, "monsterId=%d dodge still damaged player" % monster_id)
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	_advance_release(attacker)
	assert(_descriptors.size() == 2)
	effect = _latest_projectile_effect()
	assert(effect != null)
	effect.set_physics_process(false)
	player._rng.seed = hit_seed
	effect.call("_physics_process", 0.3)
	assert(player.current_hp == hp_before - 7, "monsterId=%d contact did not settle hp=%d expected=%d descriptor=%s hit=%s" % [monster_id, player.current_hp, hp_before - 7, str(effect._first_flight_collision(effect.origin_world_px, effect.target_world_px)), str(attacker.last_physical_hit_resolution)])
	effect.call("_physics_process", 0.3)
	attacker._physics_process(0.001)
	assert(player.current_hp == hp_before - 7, "one arrow applied damage twice")

	# A target changing maps during flight keeps the visual but cancels damage.
	player.current_hp = hp_before
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	_advance_release(attacker)
	assert(_descriptors.size() == 3)
	player.set_meta("runtime_map_id", 2)
	effect = _latest_projectile_effect()
	effect.call("_physics_process", 0.3)
	assert(player.current_hp == hp_before)
	player.set_meta("runtime_map_id", 1)

	# Every exact projectile actor freezes the typed player epoch at launch. A complete
	# Loading transition invalidates the old projectile even after READY resumes.
	attacker.target = player
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	_advance_release(attacker)
	assert(_descriptors.size() == 4)
	var transition_token := "projectile-transition-%d" % monster_id
	assert(player.begin_combat_transition(transition_token))
	assert(player.finish_combat_transition(transition_token))
	effect = _latest_projectile_effect()
	effect.call("_physics_process", 0.3)
	assert(player.current_hp == hp_before, "monsterId=%d projectile crossed combat_epoch" % monster_id)

	# A wall entering the frozen lane after launch must stop the live flight.
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	_advance_release(attacker)
	assert(_descriptors.size() == 5)
	effect = _latest_projectile_effect()
	var wall := StaticBody2D.new()
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	wall.global_position = _ground_to_screen(Vector2(2.0, 0.0))
	var wall_shape := CollisionShape2D.new()
	var wall_circle := CircleShape2D.new()
	wall_circle.radius = 8.0
	wall_shape.shape = wall_circle
	wall.add_child(wall_shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	effect.call("_physics_process", 0.3)
	assert(bool(effect.call("collision_interrupted")), "flight crossed a world collider")
	assert(player.current_hp == hp_before, "wall-blocked projectile damaged player")
	wall.queue_free()
	await get_tree().process_frame

	# CanFly parity: one blocked intermediate sample rejects the whole release,
	# so there is no visual and no delayed damage transaction.
	_blocked_world_px = _ground_to_screen(Vector2(2.0, 0.0))
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	_advance_release(attacker)
	assert(_descriptors.size() == 5)
	assert(attacker._pending_attack_release_record.is_empty())
	attacker._physics_process(1.0)
	assert(player.current_hp == hp_before)

	attacker.queue_free()
	player.queue_free()
	for child: Node in get_children():
		if child is Node2D and child.get_script() == ProjectileEffectScript:
			child.queue_free()
	await get_tree().process_frame


func _advance_release(attacker: EnemyActor) -> void:
	# Advance to this actor's release, without jumping past a faster actor's
	# next attack interval and accidentally starting a second test action.
	for step in range(400):
		attacker._physics_process(0.005)
		if attacker._pending_attack_release_record.is_empty(): return
	assert(false, "projectile windup did not release")


func _assert_authoritative_archer_profiles() -> void:
	for monster_id: int in [150, 152, 206]:
		var profile := MonsterIdentity.behavior_profile(
			GameData.get_monster_by_id(monster_id)
		)
		var delivery: Dictionary = profile.get("attackDelivery", {})
		assert(str(delivery.get("kind", "")) == "physical_projectile")
		assert(str(delivery.get("effectId", "")) == ProjectileEffectScript.EFFECT_ID)
		assert(str(delivery.get("obstaclePolicy", "")) == "environment_can_fly_line")
		assert(str(delivery.get("confidence", "")) == "A")


func _assert_id50_identity_bridge() -> void:
	var canonical_profile := MonsterIdentity.behavior_profile(
		GameData.get_monster_by_id(50)
	)
	var canonical_delivery: Dictionary = canonical_profile.get("attackDelivery", {})
	assert(str(canonical_delivery.get("kind", "")) == "physical_projectile")
	assert(
		str(canonical_delivery.get("effectId", ""))
		== ProjectileEffectScript.EFFECT_ID
	)
	assert(
		str(canonical_profile.get("serviceClass", {}).get("name", ""))
		== "TDualAxeMonster"
	)
	var combat_source := _read_json(
		"res://assets/data/canonical_monster_combat_source_v1.json"
	)
	var combat_record: Dictionary = combat_source.get(
		"records_by_monster_id",
		{},
	).get("50", {})
	assert(int(combat_record.get("monster_id", -1)) == 50)
	assert(int(combat_record.get("appearance", -1)) == 21)
	assert(int(combat_record.get("ai_code", -1)) == 87)
	var service := _read_json("res://assets/data/service_monster_runtime_catalog.json")
	var service_record: Dictionary = service.get("runtimeByMonsterId", {}).get(
		"50",
		{},
	)
	assert(str(service_record.get("resolutionStatus", "")) == "exact_service_name")
	assert(
		int(service_record.get("serviceRecord", {}).get("aiCode", -1)) == 8
	)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed as Dictionary


func is_environment_point_blocked(world_px: Vector2) -> bool:
	return (
		_blocked_world_px != Vector2.INF
		and world_px.distance_to(_blocked_world_px) <= 2.0
	)


func _capture_descriptor(descriptor: Dictionary) -> void:
	_descriptors.append(descriptor)


func _find_projectile_effect() -> Node2D:
	for child: Node in get_children():
		if child is Node2D and child.get_script() == ProjectileEffectScript:
			return child as Node2D
	return null


func _latest_projectile_effect() -> Node2D:
	var children := get_children()
	for index: int in range(children.size() - 1, -1, -1):
		var child: Node = children[index]
		if child is Node2D and child.get_script() == ProjectileEffectScript and not child.is_queued_for_deletion():
			return child as Node2D
	return null


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)


func _empty_terrain_context() -> Dictionary:
	return TerrainPolicy.build_context(
		1,
		{
			"build_sha256": "1".repeat(64),
			"source": {"runtime_map_id": 1},
			"design": {"design_size": [32, 32]},
			"collision": {"blocked_tiles": []},
		},
		TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
	)
