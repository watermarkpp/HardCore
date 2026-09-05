extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const WarriorGeometry := preload(
	"res://scripts/skills/warrior_melee_geometry.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## Authored world_bich_province monster_id=21 spawn tile [28, 66].
const FIXTURE_ENEMY_GROUND_POSITION := Vector2(28.5, 66.5)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_formal_world(game)
	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var produced: Array[Dictionary] = []

	# Warrior melee production entry.
	produced.append(game._create_melee_release_footprint_snapshot(
		Vector2.ZERO,
		Vector2.RIGHT,
		WarriorGeometry.SKILL_THRUST
	))
	# Enemy production spawn + attack.
	var enemy_position: Vector2 = game._canonical_ground_gu_to_screen_px(
		FIXTURE_ENEMY_GROUND_POSITION
	)
	var player_ground: Vector2 = FIXTURE_ENEMY_GROUND_POSITION + Vector2(2.0, 0.0)
	var player_position: Vector2 = game._canonical_ground_gu_to_screen_px(player_ground)
	assert(enemy_position.is_finite() and player_position.is_finite(), "no-legacy snapshot fixture needs a finite map projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_ENEMY_GROUND_POSITION,
			game._active_safe_zones,
		)
			and not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
				player_ground,
				game._active_safe_zones,
			),
		"no-legacy snapshot fixture must exercise an authored outdoor point"
	)
	var enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(21),
		enemy_position,
		false,
		-1.0,
		{"respawn_enabled": false}
	)
	assert(
		enemy != null
			and enemy.runtime_map_id == int(game.get("current_map_id"))
			and enemy.projection_ready()
			and enemy.spatial_actor_runtime_id > 0,
		"no-legacy snapshot fixture must use the formal mapped spawn"
	)
	enemy.attack_range_gu = 2.0
	var player_node: PlayerCharacter = game.player
	game._set_player_world_position(player_position)
	player_node.set_physics_process(false)
	enemy._deal_melee_hit(player_node, 1)
	produced.append(enemy._last_attack_footprint_snapshot)
	produced.append(enemy._create_area_attack_footprint_snapshot())
	# Projectile production spawn.
	game._spawn_projectile(
		Vector2.ZERO,
		Vector2.RIGHT,
		10,
		8.0,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"no-legacy:1"
	)
	for child: Node in game.get_children():
		if child is SkillProjectile:
			produced.append(child.skill_footprint_snapshot)
			break
	# Summon production factory.
	# Q3-C: legacy the legacy resolver was removed; the summon factory
	# consumes a frozen canonical node plan.
	var summon_plan := {
		"operation": "summon",
		"success": true,
		"skill_id": "taoist.summon_skeleton",
		"release_id": "no-legacy:summon:1",
		"display_name": "骷髅",
		"skill_level": 3,
	}
	summon_plan["snapshot_coordinate_context"] = (
		Snapshot.make_absolute_runtime_context(
			9001,
			Vector2.ZERO,
			Vector2.ZERO,
			Callable(self, "_ground_to_screen")
		)
	)
	var summon := CasterRuntime.create_summon_actor(
		summon_plan, player_node, 30, 40, player_node.global_position
	)
	if summon != null:
		summon.configure_spawn_release_footprint("no-legacy:summon:1")
		produced.append(summon.summon_spawn_footprint_snapshot)
		summon.free()

	assert(
		produced.size() > 0,
		"production entries must create snapshots"
	)
	var v1_count := 0
	var legacy_space_count := 0
	for snapshot: Dictionary in produced:
		if int(snapshot.get("schema_version", 0)) == 1:
			v1_count += 1
		if (
			str(snapshot.get("coordinate_space", ""))
			== Snapshot.COORDINATE_SPACE_LEGACY_GROUND_GU
		):
			legacy_space_count += 1
		assert(
			int(snapshot.get("schema_version", 0)) == Snapshot.SCHEMA_VERSION,
			"production snapshot must be schema V2"
		)
		assert(
			snapshot.get("runtime_map_id", -1) is int,
			"production snapshot must carry a typed int map id"
		)
	assert(v1_count == 0, "production must not create schema V1 snapshots")
	assert(
		legacy_space_count == 0,
		"production must not create legacy_ground_gu snapshots"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"production regression must not increment the legacy counter"
	)

	game.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	print("PRODUCTION_SNAPSHOT_NO_LEGACY_PASS")
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _wait_for_formal_world(game: Node) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		var current_map_id: int = int(game.get("current_map_id"))
		var input_enabled: bool = bool(game.call("gameplay_input_is_enabled"))
		if current_map_id >= 0 and input_enabled:
			break
		await get_tree().process_frame
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"no-legacy snapshot fixture must wait for the formal mapped world"
	)
	assert(not game._active_safe_zones.is_empty(), "no-legacy snapshot fixture needs the formal safe-zone context")
