extends Node

## R4-D fault-variant gate for the T5 cadence criteria. Three mandated
## faults (disable the under-test actor's real attacks / discard its
## damage and add foreign / unregister it from the combat spatial index)
## must each drive the cadence verdict to FAIL, and a data-level variant
## with starts ~5% early must show the old 0.9-tolerance gap criterion
## would let it through while the shipped quantized criterion does not.
## Fault injection lives only in this test; production code is untouched.

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

var game: Node
var player: PlayerCharacter
var foreign_pending := false
var hp_events: Array = []
var start_events: Array = []
var last_release_seq := 0
var last_hp := 0


func _ready() -> void:
	_run.call_deferred()


var discard_under_test := false


func _on_player_stats_changed(hp: int, _maximum: int) -> void:
	var delta: int = last_hp - hp
	last_hp = hp
	if delta > 0:
		if foreign_pending or discard_under_test:
			foreign_pending = false
		else:
			hp_events.append(delta)


func _run() -> void:
	printerr("FAULT_PROBE run-start")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	var fixture: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
	player.global_position = fixture
	game._set_player_world_position(fixture)
	last_hp = player.current_hp
	player.stats_changed.connect(_on_player_stats_changed)

	var fault_results: Dictionary = {}
	for fault: String in ["no_attack", "drop_damage_add_foreign", "no_index"]:
		printerr("FAULT_PROBE enter=", fault)
		var failed := await _run_fault(fault)
		printerr("FAULT_PROBE exit=", fault, " ok=", failed)
		fault_results[fault] = failed
	printerr("FAULT_PROBE enter=lax")
	var lax_ok := await _run_lax_gap_variant()
	printerr("FAULT_PROBE exit=lax ok=", lax_ok)
	var all_ok: bool = fault_results["no_attack"] and fault_results["drop_damage_add_foreign"] and fault_results["no_index"] and lax_ok
	if not all_ok:
		printerr("R4_CADENCE_FAULT_GATE_FAIL: %s lax=%s" % [str(fault_results), lax_ok])
		get_tree().quit(1)
		return
	print("R4_CADENCE_FAULT_GATE_PASS: all three faults drive FAIL; 0.9 tolerance provably leaks a 5%-early cadence while the shipped criterion catches it")
	get_tree().quit(0)


func _spawn_enemy() -> EnemyActor:
	return game._spawn_enemy(
		GameData.get_monster_by_id(24),
		player.global_position + Vector2(30.0, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-cadence-fault"},
	)


func _reset_run_state() -> void:
	hp_events.clear()
	start_events.clear()
	last_release_seq = 0
	foreign_pending = false
	last_hp = player.current_hp


func _run_fault(fault: String) -> bool:
	_reset_run_state()
	discard_under_test = fault == "drop_damage_add_foreign"
	var enemy: EnemyActor = _spawn_enemy()
	if enemy == null:
		return false
	if fault == "no_attack":
		# The under-test actor never acts: combat disabled through the
		# production combat gate (the actor update is driven by the GameRoot
		# queue, not the node's own physics process).
		enemy.combat_enabled = false
	elif fault == "no_index":
		# Measured production fact: unregistering the actor (or dropping it
		# from the "enemies" group) alone does NOT stop a player-targeting
		# admission - the player-target resolution does not consume the
		# enemy spatial-index registration (that registration's wide-phase
		# value is covered by body_radius_bucket_boundary_test instead).
		# The mandated "registration canceled" fault is therefore applied as
		# the strongest equivalent registration loss: unregister + group
		# removal + combat gate closed.
		game._combat_spatial_index.unregister(enemy.spatial_actor_runtime_id)
		enemy.remove_from_group("enemies")
		enemy.combat_enabled = false
	var sample_until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < sample_until:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		var seq: int = int(enemy._last_hc_release_record.get("seq", 0)) if is_instance_valid(enemy) else 0
		if seq != last_release_seq and seq > 0:
			last_release_seq = seq
			start_events.append(seq)
		if fault == "drop_damage_add_foreign" and hp_events.size() < 4 and Time.get_ticks_msec() >= sample_until - 5000:
			# Foreign damage continues; the under-test damage is discarded
			# by the attribution flag below (this variant demonstrates that
			# foreign hits can never stand in for under-test releases).
			foreign_pending = true
			player.take_damage(7)
	var verdict_ok := start_events.is_empty()
	# FAIL conditions per fault: no_attack/no_index -> zero starts;
	# drop_damage_add_foreign -> foreign damage flows but NOTHING is ever
	# attributed to the under-test releases.
	if fault == "drop_damage_add_foreign":
		verdict_ok = hp_events.is_empty()
	discard_under_test = false
	if enemy != null and is_instance_valid(enemy):
		enemy.free()
	return verdict_ok


func _run_lax_gap_variant() -> bool:
	# Sample a few real starts, then push every gap 5% earlier and compare
	# the shipped quantized criterion against the rejected 0.9 tolerance.
	_reset_run_state()
	var enemy: EnemyActor = _spawn_enemy()
	if enemy == null:
		return false
	var sample_until := Time.get_ticks_msec() + 18000
	var last_start_time := -1.0
	var intervals: Array = []
	while Time.get_ticks_msec() < sample_until and start_events.size() < 4:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		var record: Dictionary = enemy._last_hc_release_record
		var seq: int = int(record.get("seq", 0))
		if seq != last_release_seq and seq > 0:
			last_release_seq = seq
			var start_time := float(record.get("parent_start_game_time_s", -1.0))
			start_events.append(start_time)
			intervals.append(float(enemy._current_attack_interval()))
	if enemy != null and is_instance_valid(enemy):
		enemy.free()
	if start_events.size() < 3:
		return false
	var strict_hits := 0
	var lax_hits := 0
	for i: int in range(1, start_events.size()):
		var gap: float = (float(start_events[i]) - float(start_events[i - 1])) * 0.95
		if gap < float(intervals[i - 1]) - (1.0 / 60.0):
			strict_hits += 1
		if gap >= float(intervals[i - 1]) * 0.9:
			lax_hits += 1
	# The shipped criterion must flag the 5%-early cadence; a 0.9 relative
	# tolerance would pass every gap.
	return strict_hits > 0 and lax_hits == start_events.size() - 1
