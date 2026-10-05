extends Node

## Common test-only wrapper at the actual record-consuming call boundary.
## It observes super's synchronous result; zero HP is NOT inferred to be miss.
## CAND's full-identity ledger provides the separate positive/fault acceptance.
const GU := preload("res://scripts/ground_unit_space.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const MAP_ID := 9001
const CENTER := Vector2(16.5, 16.5)

class BoundaryEnemy extends EnemyActor:
	var actual_rows: Array = []
	func _hc_settle(record: Dictionary) -> void:
		var victim: Node = record.target.get_ref()
		var before: int = victim.current_hp if is_instance_valid(victim) else -1
		var frozen := record.duplicate(true)
		frozen.erase("target")
		frozen["source_instance_id"] = get_instance_id()
		frozen["physics_tick"] = Engine.get_physics_frames()
		frozen["effective_interval_s"] = _current_attack_interval()
		super._hc_settle(record)
		frozen["hp_before"] = before
		frozen["hp_after"] = victim.current_hp if is_instance_valid(victim) else -1
		frozen["hp_delta"] = before - int(frozen.hp_after)
		frozen["result_scope"] = "actual synchronous settlement boundary; zero delta is unclassified, never synthetic miss"
		actual_rows.append(frozen)

func _ready() -> void:
	_run.call_deferred()

func _to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

func _run() -> void:
	var start_usec := Time.get_ticks_usec()
	var mid := int(OS.get_environment("HARDCORE_R4_COMPARE_ID"))
	assert(mid in [24, 76, 238, 239])
	var chase := OS.get_environment("HARDCORE_R4_COMPARE_CHASE") == "1"
	var expected := 1 if chase else 20
	assert(not chase or mid == 24)
	var observer: Variant = null
	var observe := OS.get_environment("HARDCORE_R4_COMPARE_OBSERVER") == "1"
	if observe:
		# BASE has no observer implementation. This branch is CAND-only; the
		# actual settlement wrapper and workload remain byte-identical.
		observer = load("res://scripts/damage_ledger_observer.gd")
		observer.reset()
		observer.recording_enabled = true
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.position = _to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	player._rng.seed = 240927
	var index := Index.new()
	var enemy := BoundaryEnemy.new()
	enemy.setup(GameData.get_monster_by_id(mid), player, false)
	enemy.set_meta("safe_zones", [])
	enemy.set_meta("zone_generation", 1)
	enemy.configure_runtime_map_projection(MAP_ID, _to_screen, _to_ground)
	enemy.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	enemy.configure_spatial_index(index, 1)
	var spawn := CENTER + Vector2(4.0 if chase else 1.4, 0)
	enemy.set_combat_position(_to_screen(spawn), &"r4_common_test_factory")
	enemy.set_meta("spawn_position", enemy.position)
	enemy.set_spawn_facing_seed_for_test(20260928)
	enemy.set_audio_seed_for_test(20260929)
	add_child(enemy)
	# _ready owns randomize; pin the actual gameplay stream after it returns.
	enemy._rng.seed = 20260927
	index.register(1, MAP_ID, spawn, enemy.combat_radius_gu, 1, enemy)
	var boot_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var sample_start := Time.get_ticks_usec()
	# Compare 20 legal-position starts, and test genuine pursuit separately.
	# Both use real physics; no source interval or clock is shortened.
	var deadline := Time.get_ticks_msec() + 55000
	var moved := 0
	var previous := enemy.position
	while enemy.actual_rows.size() < expected and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if previous.distance_to(enemy.position) > 0.01:
			moved += 1
		previous = enemy.position
	enemy.set_physics_process(false)
	var sample_ms := float(Time.get_ticks_usec() - sample_start) / 1000.0
	var failures: Array = []
	if enemy.actual_rows.size() != expected or enemy._hc_starts != expected:
		failures.append("wrong_natural_starts_and_settlements")
	for i in range(1, enemy.actual_rows.size()):
		var before: Dictionary = enemy.actual_rows[i-1]
		var after: Dictionary = enemy.actual_rows[i]
		if float(after.parent_start_game_time_s) - float(before.parent_start_game_time_s) < float(before.effective_interval_s) - 1.0/60.0:
			failures.append("early_start:%d" % i)
		if int(after.seq) != int(before.seq) + 1:
			failures.append("sequence_gap:%d" % i)
	if chase and moved < 10:
		failures.append("out_of_range_chase_missing")
	var result := {"id": mid, "rows": enemy.actual_rows, "rng_final": str(enemy._rng.state), "player_rng_final": str(player._rng.state), "hp": player.current_hp,
		"starts": enemy._hc_starts, "settlements": enemy._hc_settlements, "position_changes": moved, "failures": failures,
		"boot_ms": boot_ms, "sample_ms": sample_ms, "head": OS.get_environment("HARDCORE_R4_COMPARE_HEAD"),
		"factory_scope": "same canonical Enemy.setup, actual projection, terrain, index and engine physics through test subclass; full GameRoot factory separately covered by CAND natural scenes",
		"baseline_terminal_attribution": "NOT_RUN; R3 lacks full ledger; zero settlement HP never mislabeled as miss"}
	result["observer_enabled"] = observe
	result["chase"] = chase
	result["expected_starts"] = expected
	result["enemy_seed"] = 20260927
	result["player_seed"] = 240927
	result["observer_event_count"] = observer.events.size() if observe else 0
	result["observer_overflowed"] = observer.overflowed if observe else false
	if observe:
		observer.recording_enabled = false
	var write_start := Time.get_ticks_usec()
	FileAccess.open("res://outputs/test_logs/r4_common_natural.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("R4_COMMON_WRITE_MS ", float(Time.get_ticks_usec() - write_start) / 1000.0)
	var cleanup_start := Time.get_ticks_usec()
	index.unregister(1)
	enemy.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("R4_COMMON_CLEANUP_MS ", float(Time.get_ticks_usec() - cleanup_start) / 1000.0)
	print("R4_COMMON_NATURAL_PASS" if failures.is_empty() else "R4_COMMON_NATURAL_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
