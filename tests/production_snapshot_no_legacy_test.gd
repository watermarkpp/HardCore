extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const WarriorGeometry := preload(
	"res://scripts/skills/warrior_melee_geometry.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var produced: Array[Dictionary] = []

	# Warrior melee production entry.
	produced.append(game._create_melee_release_footprint_snapshot(
		Vector2.ZERO,
		Vector2.RIGHT,
		WarriorGeometry.SKILL_THRUST
	))
	# Enemy production spawn + attack.
	var enemy: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(21), Vector2.ZERO, false
	)
	enemy.attack_range_gu = 2.0
	var player_node: PlayerCharacter = game.player
	player_node.global_position = Vector2(70, 0)
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
