extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
var _profile_events := 0
var _level_events := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.set_process(false)
	PlayerState.profile_changed.connect(func() -> void: _profile_events += 1)
	PlayerState.levels_gained.connect(func(_before: int, _after: int) -> void: _level_events += 1)
	var growth_rows: Array[Dictionary] = []
	var behavior_rows: Array[Dictionary] = []
	# Do not attach a second world. This invokes the real production stat-roll
	# consumer while the live player receives the actual profile-change signal.
	var game := GameRootScript.new()
	for job: String in ProfessionRules.PROFESSIONS:
		PlayerState.reset_progress(false)
		PlayerState.profession = job
		PlayerState.equipment = PlayerState._empty_equipment()
		PlayerState.recalculate_stats(false)
		for checked_level in range(1, 256):
			growth_rows.append({"profession": job, "level": checked_level,
				"stats": ProfessionRules.stats_for_level(job, checked_level)})
		var player := PlayerCharacter.new()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		_check_live_stats(player)
		behavior_rows.append(_observe_combat(player, game))
		for next_level in range(2, 61):
			var profile_before := _profile_events
			var level_before := _level_events
			var requirement := PlayerState.experience_to_next_level()
			# Exercise both real reward entrypoints, including the batched kill
			# settlement used by AOE, without assigning a new level in the test.
			if next_level % 2 == 0:
				PlayerState.add_experience(requirement)
			else:
				var settlement := PlayerState.record_kills_and_experience_batch([
					{"monster_name": "稻草人", "experience": requirement}], true)
				assert(bool(settlement.success))
			assert(PlayerState.level == next_level and PlayerState.experience == 0)
			assert(_profile_events == profile_before + 1 and _level_events == level_before + 1)
			_check_live_stats(player)
			if next_level in [30, 60]:
				behavior_rows.append(_observe_combat(player, game))
		# Both save failures must roll level/data back without notifying the
		# live actor of uncommitted values or granting a level-up effect.
		var snapshot := PlayerState.computed_stats.duplicate(true)
		var failure_profile_events := _profile_events
		var failure_level_events := _level_events
		PlayerState._test_force_atomic_write_failure = true
		PlayerState.add_experience(PlayerState.experience_to_next_level())
		var failed := PlayerState.record_kills_and_experience_batch([
			{"monster_name": "稻草人", "experience": PlayerState.experience_to_next_level()}], true)
		PlayerState._test_force_atomic_write_failure = false
		assert(not bool(failed.success) and str(failed.reason) == "save_failed")
		assert(PlayerState.level == 60 and PlayerState.experience == 0)
		assert(PlayerState.computed_stats == snapshot)
		assert(_profile_events == failure_profile_events and _level_events == failure_level_events)
		_check_live_stats(player)
		player.free()
	game.free()
	var output := {"status": "PASS", "range_is_audit_coverage_not_level_cap": [1, 255],
		"formula_rows": growth_rows, "combat_observations": behavior_rows,
		"live_level_transitions": 177, "save_failure_paths": 6,
		"source_hashes": {}}
	for path in ["scripts/generated/character_base_growth_v1.gd", "scripts/profession_rules.gd",
		"scripts/player_state.gd", "scripts/player.gd", "scripts/game_root.gd",
		"tests/player_growth_live_runtime_test.gd"]:
		output.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	var directory := "res://outputs/repair_v92"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/player_growth_live.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("PLAYER_GROWTH_LIVE_RUNTIME_PASS professions=3 formula_rows=765 live_transitions=177 save_failures=6")
	get_tree().quit(0)


func _check_live_stats(player: PlayerCharacter) -> void:
	var base: Dictionary = PlayerState.base_stats
	for key: String in base:
		assert(PlayerState.computed_stats[key] == base[key], "naked computed mismatch: " + key)
	for key in ["max_hp", "max_mp", "attack_min", "attack_max", "defense_min", "defense_max"]:
		assert(player.get(key) == base[key], "live actor not updated through signal: " + key)
	assert(PlayerState.max_inventory_weight() == int(base.max_bag_weight))
	assert(EquipmentRules.max_wear_weight(PlayerState.profession, PlayerState.level) == int(base.max_wear_weight))
	assert(EquipmentRules.max_hand_weight(PlayerState.profession, PlayerState.level) == int(base.max_hand_weight))


func _observe_combat(player: PlayerCharacter, game: Node) -> Dictionary:
	var base: Dictionary = PlayerState.base_stats
	var profession_id := ProfessionRules.profession_id(PlayerState.profession)
	var primary := "attack" if profession_id == "warrior" else ("magic" if profession_id == "wizard" else "tao")
	game._rng.seed = 20260922
	var low := 2147483647
	var high := -1
	for attempt in range(64):
		var rolled: int = game._canonical_primary_stat_roll(profession_id)
		assert(rolled >= int(base[primary + "_min"]) and rolled <= int(base[primary + "_max"]))
		low = mini(low, rolled)
		high = maxi(high, rolled)
	assert(low == int(base[primary + "_min"]) and high == int(base[primary + "_max"]))
	player.current_hp = player.max_hp
	player._rng.seed = 20260922
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 20260922
	var ac_roll := expected_rng.randi_range(int(base.defense_min), int(base.defense_max))
	var hp_before := player.current_hp
	player.take_damage(10, false)
	var physical_loss := hp_before - player.current_hp
	assert(physical_loss == maxi(1, 10 - ac_roll), "base AC must change actual HP loss")
	player.current_hp = player.max_hp
	hp_before = player.current_hp
	var spell := player.take_direct_spell_damage("wizard.lightning", 15, 9, int(base.magic_defense_max), false)
	var magic_loss := hp_before - player.current_hp
	assert(magic_loss == maxi(0, 15 - int(base.magic_defense_max)), "base MAC must change actual HP loss")
	assert(int(spell.applied_damage) == magic_loss)
	assert(not player._dead)
	var wood := GameData.get_item("木剑")
	var old_capacity := ProfessionRules.base_stat_for_level(PlayerState.profession, 1, "max_bag_weight")
	var sword_count := old_capacity / maxi(1, int(wood.weight)) + 1
	var receipt := PlayerState._build_receive_result("木剑", sword_count, [])
	if PlayerState.level == 1:
		assert(not bool(receipt.success) and str(receipt.reason) == "overweight")
	else:
		assert(bool(receipt.success), "increased bag weight must allow the previously overweight receipt")
	return {"profession": PlayerState.profession, "level": PlayerState.level,
		"base": base.duplicate(), "primary_roll_min": low, "primary_roll_max": high,
		"physical_input": 10, "ac_roll": ac_roll, "physical_hp_loss": physical_loss,
		"magic_input": 15, "mac_roll": int(base.magic_defense_max), "magic_hp_loss": magic_loss,
		"bag_preview_sword_count": sword_count, "bag_preview_success": bool(receipt.success)}
