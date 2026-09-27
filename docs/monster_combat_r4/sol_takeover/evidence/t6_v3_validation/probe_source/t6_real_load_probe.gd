extends Node

## Identical test-only overlay for fixed R3 BASE and CAND. Engine physics owns
## all motion, attack clocks and effect/loot queues. One condition per process.
const SCALES := [10, 20, 30]
const MODES := ["small", "large_pets", "aoe_death_loot"]
const SAMPLE_FRAMES := 600
const SEED := 20260927
const CENTER := Vector2(40.5, 13.5)

# Only the test random-input boundary differs from the production main scene
# (whose root is a childless GameRoot Node2D). All cast/physics/queue code is
# inherited unchanged. Production uses wall time in this seed boundary.
class SeededGameRoot extends "res://scripts/game_root.gd":
	var t6_cast_seed_inputs: Array = []
	func _next_canonical_seed() -> int:
		_canonical_cast_serial += 1
		var value := hash([20260927, _canonical_cast_serial, "r4_t6_fixed"])
		t6_cast_seed_inputs.append({"serial": _canonical_cast_serial, "seed": value})
		return value

var game: Node
var actors: Array[EnemyActor] = []
var pets: Array[SummonActor] = []
var frames: Array = []
var failures: Array = []
var replacements := 0
var deaths := 0
var casts: Array = []
var serial := 0
var mode := ""
var scale := 0
var totals := {}
var previous_counters := {}
var retired_starts := 0
var pet_damage := 0
var previous_hp := {}
var death_signals := 0
var seen_deaths := {}
var corpse_refs: Array[WeakRef] = []
var spawn_seed_inputs: Array = []
var actor_seed_inputs: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	mode = OS.get_environment("HARDCORE_R4_LOAD_MODE")
	scale = int(OS.get_environment("HARDCORE_R4_LOAD_COUNT"))
	assert(MODES.has(mode) and SCALES.has(scale), "pin one valid T6 condition")
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "道士" if mode == "large_pets" else "法师"
	PlayerState.learned_skills = {"火墙": 3, "爆裂火焰": 3, "召唤骷髅": 3, "召唤神兽": 3}
	PlayerState.recalculate_stats()
	# Fixed survivability input survives profile notifications from real loot
	# settlement. Padding only the actor would be clamped back to source HP.
	PlayerState.computed_stats["max_hp"] = 1000000
	PlayerState.computed_stats["max_mp"] = 1000000
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	var started := Time.get_ticks_usec()
	game = SeededGameRoot.new()
	game.name = "GameRoot"
	add_child(game)
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if int(game.current_map_id) >= 0 and game.gameplay_input_is_enabled():
			break
	assert(int(game.current_map_id) >= 0 and game.gameplay_input_is_enabled(), "formal world failed")
	var boot_ms := float(Time.get_ticks_usec() - started) / 1000.0
	# Remove the authored ambient actors via index unregister/free, without a
	# death/drop or respawn signal; measured count is exactly the declared load.
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			game._combat_spatial_index.unregister(node.spatial_actor_runtime_id)
			node.free()
	game._rng.seed = SEED
	seed(SEED)
	game.player._rng.seed = SEED + 1
	PlayerState._durability_rng.seed = SEED + 2
	# SceneTree node_added is before _ready. Pin spawn-facing and audio through
	# existing test hooks without replacing the formal GameRoot factory.
	get_tree().node_added.connect(_pin_spawn_inputs)
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(CENTER))
	game.player.set_physics_process(false)
	game.player.max_hp = 1000000
	game.player.current_hp = game.player.max_hp
	game.player.max_mp = 1000000
	game.player.current_mp = game.player.max_mp
	if mode == "large_pets":
		for skill: String in ["taoist.summon_skeleton", "taoist.summon_divine_beast"]:
			var cast: Dictionary = game._execute_canonical_skill(skill, game.player.global_position, Vector2.RIGHT, 0)
			_check(bool(cast.get("accepted", false)), "formal_pet_cast_rejected:" + skill)
			var pet: SummonActor = game._canonical_main_pet(game._summon_id_for_skill(skill))
			_check(pet != null, "formal_pet_missing:" + skill)
			if pet != null:
				pets.append(pet)
				pet._rng.seed = SEED + 10000 + pets.size()
				actor_seed_inputs.append({"kind": "pet", "ordinal": pets.size(), "seed": str(pet._rng.seed), "initial_state": str(pet._rng.state)})
				pet.max_hp = 1000000
				pet.current_hp = pet.max_hp
	for i in range(scale):
		actors.append(_spawn(i))
	for _warm in range(90):
		await get_tree().physics_frame
		await get_tree().process_frame
	if mode == "aoe_death_loot":
		_cast("wizard.fire_wall")
	var cold_casts := casts.duplicate(true)
	RuntimeDiagnostics.reset_performance_window()
	previous_counters = RuntimeDiagnostics.performance_counters()
	var hp_start: int = game.player.current_hp
	var previous_usec := Time.get_ticks_usec()
	var previous_enemy_usec := RuntimeDiagnostics.performance_counter(&"enemy_physics_usec")
	var initial_positions: Array = []
	for actor: EnemyActor in actors:
		initial_positions.append(actor.global_position)
		previous_hp[actor.get_instance_id()] = actor.current_hp
	var tick_start := Engine.get_physics_frames()
	for frame in range(SAMPLE_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
		_sample_counters()
		var living := 0
		var corpses := 0
		for ref: WeakRef in corpse_refs:
			if is_instance_valid(ref.get_ref()):
				corpses += 1
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			if node is EnemyActor:
				var actor := node as EnemyActor
				if actor.current_hp > 0 and not actor._dying and not actor._death_pending:
					living += 1
				else:
					pass # Death signals own the retained corpse inventory.
		for actor: EnemyActor in actors:
			if is_instance_valid(actor):
				var id := actor.get_instance_id()
				var delta_hp := maxi(0, int(previous_hp.get(id, actor.current_hp)) - actor.current_hp)
				if mode == "large_pets" and delta_hp > 0 and actor._last_damaging_pet != null and is_instance_valid(actor._last_damaging_pet.get_ref()):
					pet_damage += delta_hp
				previous_hp[id] = actor.current_hp
		if mode == "aoe_death_loot":
			for i in range(actors.size()):
				if not is_instance_valid(actors[i]) or actors[i]._dying or actors[i]._death_pending or actors[i].current_hp <= 0:
					if is_instance_valid(actors[i]):
						retired_starts += actors[i]._audio_attack_sequence
					deaths += 1
					actors[i] = _spawn(i)
					previous_hp[actors[i].get_instance_id()] = actors[i].current_hp
					replacements += 1
					living += 1
			if frame % 120 == 0:
				_cast("wizard.exploding_flame")
		var now := Time.get_ticks_usec()
		var enemy_usec := RuntimeDiagnostics.performance_counter(&"enemy_physics_usec")
		var enemy_delta := enemy_usec - previous_enemy_usec if enemy_usec >= previous_enemy_usec else enemy_usec
		frames.append({"tick": Engine.get_physics_frames(), "physics_callback_interval_ms": float(now - previous_usec) / 1000.0,
			"engine_process_monitor_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
			"engine_physics_monitor_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
			"enemy_inclusive_cpu_ms": float(enemy_delta) / 1000.0,
			"live_count": living, "corpse_count": corpses, "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
		_check(living == scale, "load_count_mismatch:%d:%d" % [frame, living])
		_check(not game.player._dead and game.player.max_hp == 1000000, "survivability_input_changed:%d" % frame)
		previous_usec = now
		previous_enemy_usec = enemy_usec
	var actual_starts := retired_starts
	var moved := 0
	for i in range(actors.size()):
		if is_instance_valid(actors[i]):
			actual_starts += actors[i]._audio_attack_sequence
			if actors[i].global_position.distance_to(initial_positions[i]) > 0.1:
				moved += 1
	var pet_attacks := 0
	for pet: SummonActor in pets:
		if is_instance_valid(pet):
			pet_attacks += pet._audio_attack_sequence
	_check(frames.size() == SAMPLE_FRAMES and Engine.get_physics_frames() - tick_start >= SAMPLE_FRAMES, "insufficient_real_hot_frames")
	_check((actual_starts > 0 and hp_start > game.player.current_hp) or deaths > 0 or pet_damage > 0, "inactive_workload")
	if mode == "large_pets":
		_check(pets.size() == 2 and pet_attacks > 0 and pet_damage > 0, "pets_not_actually_attacking")
	if mode == "aoe_death_loot":
		_check(deaths > 0 and replacements > 0 and death_signals > 0 and int(totals.get("drop_roll_count", 0)) > 0 and int(totals.get("death_queue_committed_count", 0)) > 0 and int(totals.get("drop_node_spawn_count", 0)) > 0, "no_real_death_drop_work")
	var result := {"mode": mode, "scale": scale, "seed": SEED, "frames": frames, "boot_ms": boot_ms, "cold_casts": cold_casts,
		"casts": casts, "starts_surviving_actors": actual_starts, "moving_surviving_actors": moved, "player_hp_delta": hp_start - game.player.current_hp,
		"pet_count": pets.size(), "pet_attack_starts": pet_attacks, "pet_actual_damage": pet_damage, "deaths": deaths, "death_signals": death_signals, "replacements": replacements, "counter_deltas": totals,
		"counters_last_window": RuntimeDiagnostics.performance_counters(), "failures": failures,
		"source_head": OS.get_environment("HARDCORE_R4_LOAD_HEAD"), "label": OS.get_environment("HARDCORE_R4_LOAD_LABEL"),
		"gpu": "NOT_RUN", "device": "NOT_RUN", "measurement": "real physics callback spacing and engine monitors; inclusive CPU segments are not additive and monitors are not GPU time"}
	result["random_input_version"] = "all_gameplay_actors_spawn_and_casts.v3"
	result["random_inputs"] = {"game_root_seed": SEED, "global_seed": SEED, "player_seed": SEED + 1,
		"durability_seed": SEED + 2, "actors": actor_seed_inputs, "spawn_hooks": spawn_seed_inputs,
		"canonical_cast_inputs": game.t6_cast_seed_inputs.duplicate(true),
		"canonical_seed_policy": "native hash boundary with fixed time input and fixed test profile token; serial increment unchanged"}
	get_tree().node_added.disconnect(_pin_spawn_inputs)
	FileAccess.open("res://outputs/test_logs/r4_t6_load.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("R4_T6_LOAD_PASS" if failures.is_empty() else "R4_T6_LOAD_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn(slot: int) -> EnemyActor:
	serial += 1
	var angle := TAU * float(slot) / float(scale)
	var ground := CENTER + Vector2.from_angle(angle) * (3.5 if mode != "aoe_death_loot" else 2.0)
	var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(76 if mode == "large_pets" else 24), game._canonical_ground_gu_to_screen_px(ground), false, -1.0,
		{"respawn_enabled": false, "spawn_slot_id": "t6:%d" % serial})
	assert(actor != null and actor.combat_enabled and actor.spatial_actor_runtime_id > 0, "formal load actor rejected")
	actor._rng.seed = SEED + serial
	_check(actor._spawn_facing_seed_override_active, "spawn_seed_hook_not_before_ready")
	actor_seed_inputs.append({"kind": "enemy", "ordinal": serial, "seed": str(actor._rng.seed), "initial_state": str(actor._rng.state)})
	actor.died.connect(_on_death)
	if mode != "aoe_death_loot":
		actor.max_hp = 1000000
		actor.current_hp = actor.max_hp
	return actor

func _pin_spawn_inputs(node: Node) -> void:
	if node is EnemyActor and str(node.get_meta("spawn_slot_id", "")).begins_with("t6:"):
		var actor := node as EnemyActor
		actor.set_spawn_facing_seed_for_test(SEED + 20000 + serial)
		actor.set_audio_seed_for_test(SEED + 30000 + serial)
		spawn_seed_inputs.append({"ordinal": serial, "facing_seed": SEED + 20000 + serial, "audio_seed": SEED + 30000 + serial})

func _on_death(actor: EnemyActor, _data: Dictionary) -> void:
	var id := actor.get_instance_id()
	_check(not seen_deaths.has(id), "duplicate_death_signal:%d" % id)
	seen_deaths[id] = true
	death_signals += 1
	corpse_refs.append(weakref(actor))

func _sample_counters() -> void:
	var current := RuntimeDiagnostics.performance_counters()
	for field: String in RuntimeDiagnostics.PERFORMANCE_COUNTER_FIELDS:
		if field.ends_with("_max"):
			totals[field] = maxf(float(totals.get(field, 0)), float(current.get(field, 0)))
			continue
		var value := int(current.get(field, 0))
		var previous := int(previous_counters.get(field, 0))
		totals[field] = int(totals.get(field, 0)) + (value - previous if value >= previous else value)
	previous_counters = current

func _cast(skill: String) -> void:
	var victim: EnemyActor
	for actor: EnemyActor in actors:
		if is_instance_valid(actor) and not actor._dying and actor.current_hp > 0:
			victim = actor
			break
	if victim == null:
		return
	game._skill_cast_target = victim
	var start := Time.get_ticks_usec()
	var cast: Dictionary = game._execute_canonical_skill(skill, game.player.global_position, Vector2.RIGHT, 0,
		{"primary_stat_roll": 8, "target_tile": Vector2i(41, 14)})
	casts.append({"skill": skill, "accepted": bool(cast.get("accepted", false)), "cpu_ms": float(Time.get_ticks_usec() - start) / 1000.0, "tick": Engine.get_physics_frames()})
	_check(bool(cast.get("accepted", false)), "formal_cast_rejected:" + skill + ":" + str(cast.get("reason", "")))

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
