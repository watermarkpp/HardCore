extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var owner := PlayerCharacter.new()
	add_child(owner)
	var plan := CasterRuntime.resolve("taoist.summon_skeleton", {
		"skill_level": 3,
		"spiritual_stat_roll": 30,
	})
	plan["snapshot_coordinate_context"] = _absolute_context(9001)
	var summon := CasterRuntime.create_summon_actor(
		plan, owner, 30, 40, owner.global_position
	)
	assert(summon != null)
	summon.combat_radius_gu = 0.30
	summon.attack_range_gu = 1.00
	add_child(summon)
	summon.configure_spawn_release_footprint("summon:v2:1")
	var spawn_snapshot: Dictionary = summon.summon_spawn_footprint_snapshot
	_assert_v2(spawn_snapshot, 9001, "summon spawn")

	var target := EnemyActor.new()
	target.setup(
		{"name": "t", "hp": 100, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(1.2, 0)
	)
	add_child(target)
	var attack: Dictionary = summon.create_attack_release_footprint_snapshot(
		target
	)
	_assert_v2(attack, 9001, "summon attack")
	assert(
		summon.attack_release_snapshot_intersects_target(attack, target),
		"summon attack must hit its target through the STRICT consumer"
	)
	assert(
		not summon.attack_release_snapshot_intersects_target(
			attack,
			_other_target(Vector2(9, 0))
		),
		"summon attack must reject a distant target"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"summon production must not touch the legacy counter"
	)
	target.queue_free()
	summon.queue_free()
	owner.queue_free()
	await get_tree().process_frame
	print("SUMMON_SNAPSHOT_V2_PRODUCTION_PASS")
	get_tree().quit(0)


func _absolute_context(map_id: int) -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		map_id,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _other_target(screen_position: Vector2) -> EnemyActor:
	var target := EnemyActor.new()
	target.setup(
		{"name": "t2", "hp": 100, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		screen_position
	)
	add_child(target)
	return target


func _assert_v2(snapshot: Dictionary, map_id: int, label: String) -> void:
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
		int(snapshot.get("runtime_map_id", -1)) == map_id,
		"%s must carry the summon's own map id" % label
	)
