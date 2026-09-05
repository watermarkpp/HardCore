extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
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

	# Formal melee release entry.
	var thrust: Dictionary = game._create_melee_release_footprint_snapshot(
		Vector2.ZERO,
		Vector2.RIGHT,
		WarriorGeometry.SKILL_THRUST
	)
	_assert_v2_absolute(thrust, "warrior thrust")
	var half_moon: Dictionary = game._create_melee_release_footprint_snapshot(
		Vector2.ZERO,
		Vector2.DOWN,
		WarriorGeometry.SKILL_HALF_MOON
	)
	_assert_v2_absolute(half_moon, "warrior half moon")

	# Formal wild-rush entry with an eligible adjacent target.
	var rush_target: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(21),
		game.player.global_position + Vector2(80, 40),
		false,
		-1.0,
		{"respawn_enabled": false}
	)
	assert(rush_target != null, "wild-rush snapshot fixture enemy must spawn")
	var rush_plan: Dictionary = game._build_wild_rush_path_plan(
		rush_target, "test:wild:1"
	)
	var rush_snapshot: Dictionary = rush_plan.get(
		"skill_footprint_snapshot", {}
	)
	if not rush_snapshot.is_empty():
		_assert_v2_absolute(rush_snapshot, "warrior wild rush")
		assert(
			game._snapshot_strict_ok(rush_snapshot),
			"wild rush snapshot must pass the strict consumer"
		)

	assert(
		game._snapshot_strict_ok(thrust),
		"thrust snapshot must pass the STRICT_V2 consumer"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"warrior production must not touch the legacy counter"
	)

	game.queue_free()
	await get_tree().process_frame
	print("WARRIOR_SNAPSHOT_V2_PRODUCTION_PASS")
	get_tree().quit(0)


func _assert_v2_absolute(snapshot: Dictionary, label: String) -> void:
	assert(
		int(snapshot.get("schema_version", 0)) == Snapshot.SCHEMA_VERSION,
		"%s must be schema V2" % label
	)
	assert(
		str(snapshot.get("coordinate_space", ""))
		== Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"%s must be runtime-map absolute" % label
	)
	assert(
		snapshot.get("runtime_map_id", -1) is int
		and int(snapshot.get("runtime_map_id", -1)) >= 0,
		"%s must carry a typed runtime map id" % label
	)
	assert(
		(snapshot.get("projection_origin_ground_gu", Vector2.INF) as Vector2)
		.is_finite(),
		"%s must carry a finite projection origin" % label
	)
