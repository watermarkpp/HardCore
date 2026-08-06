extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")


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
		"proj:v2:1"
	)
	var projectile: SkillProjectile
	for child: Node in game.get_children():
		if child is SkillProjectile:
			projectile = child
			break
	assert(projectile != null)
	var release_snapshot: Dictionary = projectile.skill_footprint_snapshot
	_assert_v2(release_snapshot, "projectile release")
	assert(
		int(release_snapshot.get("runtime_map_id", -1))
		== int(game.current_map_id),
		"projectile release must freeze the runtime map id"
	)
	projectile._physics_process(0.1)
	var segment: Dictionary = projectile.last_segment_footprint_snapshot
	_assert_v2(segment, "projectile segment")
	assert(
		str(segment.get("parent_snapshot_id", ""))
		== str(release_snapshot.get("snapshot_id", "")),
		"segment must link to its parent snapshot id"
	)

	# Cross-map rejection: a projectile frozen on map 1 must not validate
	# against map 2 and must stop.
	var cross := Projectile.new()
	cross.setup_ground_unit_projectile(
		Vector2.ZERO,
		Vector2.RIGHT,
		8.0,
		1,
		4.0,
		0.25,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"proj:cross:1"
	)
	cross.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen")
	)
	add_child(cross)
	var cross_context := Snapshot.make_absolute_runtime_context(
		2,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)
	cross_context["expected_runtime_map_id"] = 2
	assert(
		not bool(Snapshot.validate_for_consumer(
			cross.skill_footprint_snapshot,
			cross_context,
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false)),
		"cross-map projectile snapshot must be rejected"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"projectile production must not touch the legacy counter"
	)

	projectile.queue_free()
	cross.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("PROJECTILE_SNAPSHOT_V2_PRODUCTION_PASS")
	get_tree().quit(0)


func _assert_v2(snapshot: Dictionary, label: String) -> void:
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


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
