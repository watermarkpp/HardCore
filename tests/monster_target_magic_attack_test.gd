extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const TerrainPolicy := preload("res://scripts/monster_terrain_navigation_policy.gd")
const SnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const MagicEffectScript := preload("res://scripts/monster_target_magic_effect.gd")

var _descriptors: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_assert_race_200_profiles()

	var player := _make_player(Vector2(2.0, 0.0))
	var mage := _make_caster(220, player)
	mage.attack_min = 50
	mage.attack_max = 50
	mage._attack_timer = 0.0
	var hp_before := player.current_hp
	mage._physics_process(0.01)
	assert(_descriptors.size() == 1, "Race 200 cast must emit target lightning immediately")
	assert(player.current_hp == hp_before, "target magic must retain the original 200 ms delay")
	assert(mage._pending_attack_release_record.get("kind", "") == "target_magic")
	var descriptor := _descriptors[0]
	assert(str(descriptor.get("effect_id", "")) == MagicEffectScript.EFFECT_ID)
	assert(str(descriptor.get("damage_channel", "")) == "magic_defense")
	assert(str(descriptor.get("damage_owner", "")) == "enemy.target_magic_release")
	var snapshot: Dictionary = descriptor.get("footprint_snapshot", {})
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_CIRCLE)
	assert(str(snapshot.get("projection_relationship_id", "")) == "ground_exact")
	assert(_find_magic_effect() != null)

	mage._physics_process(0.19)
	assert(player.current_hp == hp_before)
	mage._physics_process(0.02)
	assert(player.current_hp < hp_before - 1, "magic attack incorrectly used physical defense")
	assert(bool(mage.last_magic_attack_resolution.get("physical_defense_bypassed", false)))
	assert(bool(mage.last_magic_attack_resolution.get("magic_defense_checked", false)))
	assert(str(mage.last_magic_attack_resolution.get("damage_channel", "")) == "magic_defense")

	# Full-health Race 200 only casts on the two-tile boundary; below half HP it
	# may cast anywhere inside the same ±2 square.
	mage.current_hp = mage.max_hp
	assert(not mage._target_magic_condition_met(Vector2(1.0, 0.0)))
	assert(mage._target_magic_condition_met(Vector2(2.0, 0.0)))
	mage.current_hp = maxi(1, mage.max_hp / 2 - 1)
	assert(mage._target_magic_condition_met(Vector2(1.0, 0.0)))
	assert(not mage._target_magic_condition_met(Vector2(2.01, 2.01)))

	# Target identity is bound at release, but a map transition cancels impact.
	player.current_hp = hp_before
	player.set_meta("runtime_map_id", 1)
	player.global_position = _ground_to_screen(Vector2(2.0, 0.0))
	mage.current_hp = mage.max_hp
	mage._attack_timer = 0.0
	mage._physics_process(0.01)
	assert(_descriptors.size() == 2)
	player.set_meta("runtime_map_id", 2)
	mage._physics_process(0.21)
	assert(player.current_hp == hp_before)
	player.set_meta("runtime_map_id", 1)

	# Cow priest healing is based on post-MAC damage, not the raw magic roll.
	var priest := _make_caster(222, player)
	priest.attack_min = 50
	priest.attack_max = 50
	priest.current_hp = maxi(1, priest.max_hp - 100)
	var priest_hp_before := priest.current_hp
	player.current_hp = hp_before
	priest._attack_timer = 0.0
	priest._physics_process(0.01)
	priest._physics_process(0.21)
	assert(priest.current_hp > priest_hp_before)
	assert(priest.current_hp <= priest.max_hp)

	mage.queue_free()
	priest.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print(
		"MONSTER_TARGET_MAGIC_ATTACK_PASS race200=220,222 visual=1 "
		+ "delay=0.2 magic_defense=1 physical_defense_bypass=1 "
		+ "hp_phase=1 boundary=2 cross_map_cancel=1 life_steal=1"
	)
	get_tree().quit(0)


func _assert_race_200_profiles() -> void:
	for monster_id: int in [220, 222]:
		var profile := MonsterIdentity.behavior_profile(
			GameData.get_monster_by_id(monster_id)
		)
		var service_class: Dictionary = profile.get("serviceClass", {})
		var service_behavior: Dictionary = profile.get("serviceBehavior", {})
		var timing: Dictionary = profile.get("timing", {})
		var delivery: Dictionary = profile.get("attackDelivery", {})
		assert(int(service_class.get("race", -1)) == 200)
		assert(str(service_class.get("confidence", "")) == "A")
		assert(int(service_behavior.get("aiCode", -1)) == 200)
		assert(
			str(service_behavior.get("resolutionStatus", ""))
			== "primary_monster_db_exact_id"
		)
		assert(int(timing.get("attackIntervalMs", 0)) == 2000)
		assert(int(timing.get("moveIntervalMs", 0)) == 1200)
		assert(str(delivery.get("kind", "")) == "target_magic")
		assert(str(delivery.get("damageChannel", "")) == "magic_defense")
		assert(str(delivery.get("confidence", "")) == "A")


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(ground_gu)
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 999
	player.defense_max = 999
	return player


func _make_caster(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var caster := EnemyActor.new()
	caster.global_position = Vector2.ZERO
	caster.setup(GameData.get_monster_by_id(monster_id), player, false)
	caster.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	caster.configure_terrain_navigation_context(_empty_terrain_context())
	caster.target = player
	caster.target_magic_requested.connect(_capture_descriptor)
	add_child(caster)
	caster.set_physics_process(false)
	return caster


func _capture_descriptor(descriptor: Dictionary) -> void:
	_descriptors.append(descriptor)


func _find_magic_effect() -> Node2D:
	for child: Node in get_children():
		if child is Node2D and child.get_script() == MagicEffectScript:
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
