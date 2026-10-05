extends Node

const Ground := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
var failures: Array[String] = []
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _project(value: Vector2) -> Vector2:
	return Ground.ground_delta_gu_to_screen_delta_px(value)

func _seed_for_roll_zero() -> int:
	var candidate := RandomNumberGenerator.new()
	for value in range(200):
		candidate.seed = value
		if candidate.randi_range(0, 9) == 0:
			return value
	return -1

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var original_stats: Dictionary = PlayerState.computed_stats.duplicate(true)
	var default_points := int(original_stats.get("anti_magic_points", -1))
	_expect(default_points == 1, "legacy fixture actually starts with one anti-magic point")
	var seed_value := _seed_for_roll_zero()
	_expect(seed_value >= 0, "deterministic first real roll must exist")
	# Use separate actors for each outcome. No clock/cooldown/pending writes,
	# manual physics calls, or injected damage results.
	for points in [default_points, 0, 10]:
		await _sample(points, seed_value)
	PlayerState.computed_stats = original_stats
	var result := {"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures, "rows": rows, "default_anti_magic_points": default_points,
		"source_sha256": FileAccess.get_sha256("res://tests/classic_boss_area_magic_outcomes_test.gd"),
		"enemy_sha256": FileAccess.get_sha256("res://scripts/enemy.gd"),
		"player_sha256": FileAccess.get_sha256("res://scripts/player.gd")}
	var file := FileAccess.open("res://outputs/test_logs/classic_boss_area_magic_outcomes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	if failures.is_empty():
		print("CLASSIC_BOSS_AREA_MAGIC_OUTCOMES_PASS natural_hit_and_legal_miss=3")
	else:
		printerr("CLASSIC_BOSS_AREA_MAGIC_OUTCOMES_FAIL %s" % failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _sample(points: int, seed_value: int) -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = player.max_hp
	player.max_mp = 0
	player.current_mp = 0
	player.damage_reduction = 0.0
	player.global_position = _project(Terrain.CENTER_GROUND_GU) + Vector2(100, 0)
	# All real magic preconditions are fixed before the first natural sample.
	PlayerState.computed_stats["anti_magic_points"] = points
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	player._rng.seed = seed_value
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster_by_id(124).duplicate(true), player, true)
	boss.configure_runtime_map_projection(1, Callable(self, "_project"), Ground.screen_delta_px_to_ground_delta_gu)
	boss.configure_terrain_navigation_context(Terrain.build(1))
	boss.global_position = _project(Terrain.CENTER_GROUND_GU)
	add_child(boss)
	var hp_before := player.current_hp
	var release_id := ""
	var frozen_records: Array = []
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 8000 and boss.last_magic_attack_resolution.is_empty():
		await get_tree().physics_frame
		if not boss._area_magic_footprint_snapshot.is_empty():
			release_id = str(boss._area_magic_footprint_snapshot.release_id)
			frozen_records = boss._area_magic_release_records.duplicate(true)
	boss.set_physics_process(false)
	var resolution := boss.last_magic_attack_resolution.duplicate(true)
	var hp_after := player.current_hp
	var snapshot := boss._last_attack_footprint_snapshot.duplicate(true)
	_expect(not resolution.is_empty(), "points=%d natural delivery must finish" % points)
	_expect(not release_id.is_empty() and str(snapshot.get("release_id", "")) == release_id, "points=%d release identity" % points)
	_expect(frozen_records.size() == 1 and int(frozen_records[0].target_instance_id) == player.get_instance_id(), "points=%d real frozen victim" % points)
	_expect(int(resolution.get("source_monster_id", -1)) == 124 and str(resolution.get("delivery_kind", "")) == "area_magic", "points=%d real source/channel" % points)
	_expect(int(resolution.get("anti_magic_roll", -1)) == 0, "points=%d real seeded player roll" % points)
	_expect(str(snapshot.get("range_shape", "")) == "chebyshev_axis_aligned_square_exclusive", "points=%d real footprint" % points)
	var evaded := points > 0
	_expect(bool(resolution.get("magic_evaded", false)) == evaded, "points=%d expected evasion" % points)
	_expect(hp_before - hp_after == int(resolution.get("applied_damage", -1)), "points=%d HP conservation" % points)
	if evaded:
		_expect(hp_after == hp_before and int(resolution.get("applied_damage", -1)) == 0, "points=%d legal miss preserves HP" % points)
	else:
		_expect(hp_after < hp_before and int(resolution.get("final_damage", 0)) > 0, "zero evasion must actually damage")
	rows.append({"points": points, "seed": seed_value, "elapsed_ms": Time.get_ticks_msec() - started,
		"hp_before": hp_before, "hp_after": hp_after, "legacy_unconditional_hp_drop_predicate": hp_after < hp_before,
		"resolution": resolution, "release_id": release_id, "frozen_records": frozen_records, "settled_snapshot": snapshot})
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame
