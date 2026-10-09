extends Node

const MONSTER_ID := 76
const WORLD_READY_FRAMES := 1800
const DEATH_WAIT_FRAMES := 1800
const RNG_SEED := 20261009
const FrameBudgetScript := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const RECEIPT_DIR := "res://outputs/wake_drop_v108_repair_20261009/natural_process"

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = false
	PlayerState.reset_progress(false)
	var creation_result := PlayerState.create_character(
		"NaturalDrop%06d" % (Time.get_ticks_msec() % 1000000),
		"战士",
		"男",
	)
	assert(creation_result.is_empty(), "isolated PlayerState character creation failed: %s" % creation_result)
	var created_profile_id: String = PlayerState.active_profile_id
	assert(not created_profile_id.is_empty(), "formal character creation did not publish a profile id")
	# Character creation writes the profile, while select_character is the formal
	# activation boundary that loads the world-clock baseline used by deaths.
	var activated: bool = PlayerState.select_character(created_profile_id)
	assert(activated, "formal character activation failed: %s" % PlayerState.last_load_result)
	assert(
		PlayerState._world_clock_snapshot_sequence >= 0,
		"formal activation did not load a world-clock baseline: %s" % PlayerState.last_load_result,
	)
	var preview_rng := RandomNumberGenerator.new()
	preview_rng.seed = RNG_SEED
	var preview: Dictionary = LootRuntime.roll_monster_drops(MONSTER_ID, preview_rng, true)
	assert(bool(preview.get("configured", false)), "known producing profile is not configured: %s" % preview)
	assert(
		(not (preview.get("items", []) as Array).is_empty())
		or not (preview.get("gold_drops", []) as Array).is_empty(),
		"fixed-seed producing profile returned no reward: %s" % preview
	)

	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var ready := false
	for _frame: int in range(WORLD_READY_FRAMES):
		await get_tree().process_frame
		if (
			not bool(_game._world_bootstrap_in_progress)
			and not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY
		):
			ready = true
			break
	assert(ready, "main bootstrap did not reach READY")
	assert(_game.is_processing(), "natural process path is disabled")
	assert(is_instance_valid(_game.player), "production player is unavailable")
	assert(is_instance_valid(_game._loot_pickup_runtime_manager), "production loot manager is unavailable")
	assert(_game._loot_pickup_runtime_manager.is_processing(), "production loot manager process is disabled")

	_game._rng.seed = RNG_SEED
	var canonical: Dictionary = GameData.get_monster_by_id(MONSTER_ID)
	assert(not canonical.is_empty(), "known producing monster is missing")
	var enemy := EnemyActor.new()
	enemy.setup(canonical, _game.player, str(canonical.get("classification", "")) == "boss")
	enemy.configure_runtime_map_projection(
		_game.current_map_id,
		Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	var death_position: Vector2 = _game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	assert(death_position.is_finite(), "formal death anchor projection is unavailable")
	enemy.global_position = death_position
	enemy.set_meta("spawn_serial", 9910109)
	enemy.set_meta("spawn_position", death_position)
	enemy.set_meta("zone_generation", _game._zone_generation)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_context", {})
	_game.add_child(enemy)
	enemy.died.connect(_game._on_enemy_died)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.current_hp = 1
	enemy.take_damage(1)

	assert(enemy._death_pending, "production Enemy did not enter death_pending")
	var terminal: Dictionary = {}
	for _frame: int in range(DEATH_WAIT_FRAMES):
		await get_tree().process_frame
		terminal = _latest_terminal_death()
		if str(terminal.get("state", "")) == "COMMITTED":
			break
	_write_receipt({
		"status": "OBSERVED_COMMITTED" if str(terminal.get("state", "")) == "COMMITTED" else "FAIL",
		"test_mode": PlayerState.test_mode,
		"terminal": terminal,
		"manager": _game._loot_pickup_runtime_manager.diagnostics_snapshot(),
		"frame_budget": FrameBudgetScript.snapshot(),
		"player_state": {
			"active_profile_id": PlayerState.active_profile_id,
			"world_clock_generation": PlayerState._world_clock_generation,
			"world_clock_snapshot_sequence": PlayerState._world_clock_snapshot_sequence,
			"last_load_result": PlayerState.last_load_result,
		},
	})
	assert(
		str(terminal.get("state", "")) == "COMMITTED",
		"natural death queue did not commit: %s budget=%s" % [terminal, FrameBudgetScript.snapshot()],
	)
	assert(str(terminal.get("reward_status", "")) == "committed", "death committed without reward: %s" % terminal)
	assert(int(terminal.get("materialized_node_count", 0)) > 0, "natural death produced no ground node: %s" % terminal)
	var manager_snapshot: Dictionary = _game._loot_pickup_runtime_manager.diagnostics_snapshot()
	assert(int(manager_snapshot.get("manager_registration_check_count", 0)) > 0, "loot manager performed no natural registration check")
	assert(int(manager_snapshot.get("registered_pickup_count", 0)) > 0, "natural ground node was not registered")

	var logout: Dictionary = _game._prepare_safe_logout()
	assert(bool(logout.get("success", false)), "safe logout failed after natural committed death: %s terminal=%s" % [logout, terminal])
	assert(_game._last_death_logout_failure.is_empty(), "logout failure ledger was populated: %s" % _game._last_death_logout_failure)
	_write_receipt({
		"status": "PASS",
		"test_mode": PlayerState.test_mode,
		"terminal": terminal,
		"manager": manager_snapshot,
		"frame_budget": FrameBudgetScript.snapshot(),
		"logout": logout,
		"wait_frames": DEATH_WAIT_FRAMES,
	})
	print("DEATH_NATURAL_PROCESS_REPAIR_PASS")
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _latest_terminal_death() -> Dictionary:
	if not is_instance_valid(_game) or _game._enemy_death_terminal_jobs.is_empty():
		return {}
	return (_game._enemy_death_terminal_jobs[-1] as Dictionary).duplicate(true)


func _write_receipt(receipt: Dictionary) -> void:
	var directory_result := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(RECEIPT_DIR)
	)
	assert(directory_result == OK or directory_result == ERR_ALREADY_EXISTS, "receipt directory unavailable")
	var path := "%s/receipt_%d_%d.json" % [RECEIPT_DIR, Time.get_ticks_usec(), OS.get_process_id()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "receipt file unavailable: %s" % path)
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()
