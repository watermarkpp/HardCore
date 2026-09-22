extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const GroundEffect := preload("res://scripts/ground_effect.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const FIXTURE_MONSTER_ID := 19


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var legacy_before := Snapshot.legacy_snapshot_validation_count
	var plan := {
		"skill_id": "wizard.fire_wall",
		"operation": "ground_dot",
		"visual": {"role": "ground_effect"},
		"success": true,
		"release_id": "ground:v2:1",
		"damage": 7,
		"duration_seconds": 5.0,
		"tick_interval_seconds": 1.0,
		"visual_radius_px": 22.08,
		"snapshot_coordinate_context": _absolute_context(9001),
	}
	var effects: Array[GroundSkillEffect] = CasterRuntime.create_ground_effects(
		plan, Vector2.ZERO
	)
	assert(effects.size() == 4, "formal 2x2 ground effects must be created")
	for effect: GroundSkillEffect in effects:
		_assert_v2(effect.skill_footprint_snapshot, "ground effect")
		effect.configure_runtime_resolution(
			null,
			Callable(),
			false,
			Callable(),
			Callable(self, "_screen_to_ground")
		)
		add_child(effect)
	var inside := _target_at(Vector2(0, 0))
	var outside := _target_at(GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(30, 0)
	))
	assert(
		effects[0].runtime_target_is_inside(inside),
		"ground effect must detect a target inside its frozen snapshot"
	)
	assert(
		not effects[0].runtime_target_is_inside(outside),
		"ground effect must not detect an outside target"
	)

	# Map mismatch: a snapshot declared on map 9001 with an expected map 9002
	# must reject the tick instead of falling back to range.
	var mismatch_snapshot := Snapshot.create_circle(
		"wizard.fire_wall",
		"ground:mismatch:1",
		Vector2(1, 1),
		1.0,
		16,
		_absolute_context(9001)
	)
	var mismatch := GroundEffect.new()
	mismatch.setup_ground_unit_effect(
		Vector2.ZERO,
		7,
		0.5,
		5.0,
		Color.WHITE,
		"wizard.fire_wall",
		1.0,
		22.08,
		"ground:mismatch:1",
		mismatch_snapshot,
		_absolute_context(9002)
	)
	mismatch.configure_runtime_resolution(
		null,
		Callable(),
		false,
		Callable(),
		Callable(self, "_screen_to_ground")
	)
	add_child(mismatch)
	assert(
		not mismatch.runtime_target_is_inside(inside),
		"cross-map ground effect must reject the tick"
	)
	assert(
		Snapshot.legacy_snapshot_validation_count == legacy_before,
		"ground effect production must not touch the legacy counter"
	)

	for effect: GroundSkillEffect in effects:
		effect.queue_free()
	mismatch.queue_free()
	inside.queue_free()
	outside.queue_free()
	await get_tree().process_frame
	print("GROUND_EFFECT_SNAPSHOT_V2_PRODUCTION_PASS")
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


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _target_at(screen_position: Vector2) -> EnemyActor:
	var target := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"ground effect fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	target.setup(canonical_data, null, false)
	assert(
		target.monster_id == FIXTURE_MONSTER_ID and not target.is_boss,
		"ground effect fixture must remain an ordinary exact-ID target"
	)
	target.max_hp = 100
	target.current_hp = target.max_hp
	target.global_position = screen_position
	target.combat_radius_gu = 0.1
	add_child(target)
	assert(
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.can_receive_damage(),
		"ground effect fixture target must survive exact-ID admission"
	)
	return target


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
		int(snapshot.get("runtime_map_id", -1)) == 9001,
		"%s must carry the frozen runtime map id" % label
	)
