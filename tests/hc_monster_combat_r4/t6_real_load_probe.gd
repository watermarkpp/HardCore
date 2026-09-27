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
	const DROP_SESSION := "20260927000000000000000000000000"
	var t6_cast_seed_inputs: Array = []
	var t6_death_identity_inputs: Array = []
	var t6_item_identity_inputs: Array = []
	var t6_planned_death_keys := {}

	# The native callback enqueues a unique identity and schedules deferred work.
	# Pin this input while still QUEUED, before any transaction or affix consumer.
	# Damage attribution continues to use the real actor ID; do not alter actors.
	func _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
		var previous_sequence := _enemy_death_sequence
		super._on_enemy_died(enemy, monster_data)
		assert(_enemy_death_sequence == previous_sequence + 1, "native death was not queued")
		var death: Dictionary = _pending_enemy_deaths.back()
		assert(int(death.sequence) == _enemy_death_sequence and death.state == DEATH_STATE_QUEUED)
		var slot := str(enemy.get_meta("spawn_slot_id", ""))
		assert(slot.begins_with("t6:") and slot.trim_prefix("t6:").is_valid_int())
		var ordinal := int(slot.trim_prefix("t6:"))
		assert(ordinal > 0)
		var native_key := str(death.death_key)
		var fixed_key := "death:%d:%d:%d:%d" % [death.origin_map_id, death.origin_generation, death.sequence, ordinal]
		death["death_key"] = fixed_key
		t6_death_identity_inputs.append({"sequence": death.sequence, "spawn_ordinal": ordinal,
			"map_id": death.origin_map_id, "generation": death.origin_generation,
			"native_key": native_key, "fixed_key": fixed_key})

	# Observe the actual native result; no filtering, rerolling or payload writes.
	func _plan_enemy_death_item(death: Dictionary) -> bool:
		var completed := super._plan_enemy_death_item(death)
		if completed and str(death.state) == DEATH_STATE_PLANNED:
			t6_planned_death_keys[str(death.death_key)] = (death.drop_plan.requests as Array).size()
			var item_index := 0
			for request: Dictionary in death.drop_plan.requests:
				if not request.has("item_record"):
					continue
				var record: Dictionary = request.item_record
				var instance: Dictionary = record.get("item_instance", {})
				if not instance.is_empty():
					var key := "%s:%s:item:%d" % [DROP_SESSION, death.death_key, item_index]
					var digest := ("item.drop.instance.v1|%d|%s" % [instance.item_id, key]).sha256_text().to_lower()
					assert(str(instance.drop_key_digest) == digest, "native affix seed input drift")
					t6_item_identity_inputs.append({"sequence": death.sequence, "item_index": item_index,
						"item_id": instance.item_id, "stable_key": key, "digest": digest,
						"instance_id": instance.instance_id, "modifiers": instance.modifiers.duplicate(true)})
				item_index += 1
		return completed
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
var detail_mode := "full"
var native_loot_nodes_created := 0
var trace_fixture_spawns := false
var fixture_spawn_events: Array = []
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
var scheduler_identity_inputs: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	trace_fixture_spawns = OS.get_environment("HARDCORE_R4_LOAD_FIXTURE_TRACE") == "1"
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
	detail_mode = OS.get_environment("HARDCORE_R4_LOAD_DETAIL")
	if detail_mode.is_empty():
		detail_mode = RuntimeDiagnostics.DEVICE_LAB_DETAIL_FULL
	assert(RuntimeDiagnostics.set_device_lab_detail_mode(detail_mode), "invalid observation detail")
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	var started := Time.get_ticks_usec()
	game = SeededGameRoot.new()
	game._drop_instance_session_key = SeededGameRoot.DROP_SESSION
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
	# Bootstrap isolation must not bypass production hot-path death throttling
	# or asynchronous loot transactions. Each process owns a distinct profile
	# under the runner's isolated userdata, never an existing player's save.
	PlayerState.active_profile_id = "r4-t6-" + OS.get_environment("HARDCORE_R4_LOAD_LABEL")
	var profile_namespace := OS.get_environment("HARDCORE_R4_LOAD_NAMESPACE")
	assert(not profile_namespace.is_empty() and profile_namespace.is_valid_filename())
	var isolated_root := "user://r4_t6/" + profile_namespace + "/" + OS.get_environment("HARDCORE_R4_LOAD_LABEL")
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(isolated_root)), "refuse existing profile/journal input")
	PlayerState.profile_directory = isolated_root.path_join("characters")
	PlayerState.profile_index_path = isolated_root.path_join("profiles.json")
	PlayerState.character_name = "R4T6"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK)
	PlayerState.test_mode = false
	# A real death transaction requires the initial formal world-clock snapshot.
	# Save through the normal API before sampling; do not fake its sequence.
	assert(PlayerState.save_game(false), "isolated production profile initialization failed: " + str(PlayerState.last_save_result))
	for _warm in range(90):
		await get_tree().physics_frame
		await get_tree().process_frame
	if mode == "aoe_death_loot":
		_cast("wizard.fire_wall")
	var cold_casts := casts.duplicate(true)
	# Observation-only boundaries, never gameplay counters or combat clocks.
	native_loot_nodes_created = 0
	game.t6_planned_death_keys.clear()
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
		frames.append({"sample_start_usec": previous_usec if trace_fixture_spawns else null, "sample_end_usec": now if trace_fixture_spawns else null, "tick": Engine.get_physics_frames(), "physics_callback_interval_ms": float(now - previous_usec) / 1000.0,
			"engine_process_monitor_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
			"engine_physics_monitor_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
			"enemy_inclusive_cpu_ms": float(enemy_delta) / 1000.0 if detail_mode == "full" else null,
			"live_count": living, "corpse_count": corpses, "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
		_check(living == scale, "load_count_mismatch:%d:%d" % [frame, living])
		_check(not game.player._dead and game.player.max_hp == 1000000, "survivability_input_changed:%d" % frame)
		_check(not PlayerState.test_mode, "production_hot_mode_bypassed:%d" % frame)
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
		_check(deaths > 0 and replacements > 0 and death_signals > 0 and not game.t6_planned_death_keys.is_empty() and native_loot_nodes_created > 0, "no_native_death_plan_or_materialized_loot")
		if detail_mode == "full":
			_check(int(totals.get("drop_roll_count", 0)) > 0 and int(totals.get("death_queue_committed_count", 0)) > 0 and int(totals.get("drop_node_spawn_count", 0)) > 0, "no_real_death_drop_work")
	var final_death_queue: Dictionary = game.death_work_queue_snapshot()
	for terminal: Dictionary in final_death_queue.get("terminal", []):
		_check(str(terminal.get("state", "")) != "FAILED", "production_death_transaction_failed:" + str(terminal.get("last_error", "")))
	if mode == "aoe_death_loot":
		_check(game.t6_death_identity_inputs.size() == death_signals, "death_identity_input_missing")
		_check(not game.t6_item_identity_inputs.is_empty(), "no_real_equipment_affix_work")
	var result := {"mode": mode, "scale": scale, "seed": SEED, "frames": frames, "boot_ms": boot_ms, "cold_casts": cold_casts,
		"casts": casts, "starts_surviving_actors": actual_starts, "moving_surviving_actors": moved, "player_hp_delta": hp_start - game.player.current_hp,
		"pet_count": pets.size(), "pet_attack_starts": pet_attacks, "pet_actual_damage": pet_damage, "deaths": deaths, "death_signals": death_signals, "replacements": replacements, "counter_deltas": totals,
		"counters_last_window": RuntimeDiagnostics.performance_counters(), "failures": failures,
		"source_head": OS.get_environment("HARDCORE_R4_LOAD_HEAD"), "label": OS.get_environment("HARDCORE_R4_LOAD_LABEL"),
		"gpu": "NOT_RUN", "device": "NOT_RUN", "measurement": "real physics callback spacing and engine monitors; inclusive CPU segments are not additive and monitors are not GPU time"}
	result["fixture_spawn_trace_enabled"] = trace_fixture_spawns
	result["fixture_spawn_events"] = fixture_spawn_events
	result["native_planned_death_keys"] = game.t6_planned_death_keys.duplicate()
	result["native_loot_nodes_created"] = native_loot_nodes_created
	result["observation_detail_mode"] = RuntimeDiagnostics.device_lab_detail_mode()
	result["enemy_cpu_attribution"] = "PASS" if detail_mode == "full" else "NOT_RUN"
	_check(RuntimeDiagnostics.device_lab_detail_mode() == detail_mode, "observation_detail_changed")
	result["random_input_version"] = "all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5"
	result["production_hot_test_mode"] = PlayerState.test_mode
	result["isolated_profile_id"] = PlayerState.active_profile_id
	result["isolated_profile_namespace"] = profile_namespace
	result["last_save_result"] = PlayerState.last_save_result.duplicate(true)
	result["death_queue_at_end"] = final_death_queue
	result["random_inputs"] = {"game_root_seed": SEED, "global_seed": SEED, "player_seed": SEED + 1,
		"durability_seed": SEED + 2, "actors": actor_seed_inputs, "spawn_hooks": spawn_seed_inputs,
		"drop_session": SeededGameRoot.DROP_SESSION,
		"death_identity_inputs": game.t6_death_identity_inputs.duplicate(true),
		"equipment_identity_inputs": game.t6_item_identity_inputs.duplicate(true),
		"canonical_cast_inputs": game.t6_cast_seed_inputs.duplicate(true),
		"canonical_seed_policy": "native hash boundary with fixed time input and fixed test profile token; serial increment unchanged"}
	# Observe allocation-dependent staggering without clearing/resetting clocks,
	# actor IDs or cooldowns to make work counts artificially equal.
	result["scheduler_identity_inputs"] = scheduler_identity_inputs
	get_tree().node_added.disconnect(_pin_spawn_inputs)
	FileAccess.open("res://outputs/test_logs/r4_t6_load.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerState.test_mode = true
	print("R4_T6_LOAD_PASS" if failures.is_empty() else "R4_T6_LOAD_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn(slot: int) -> EnemyActor:
	var fixture_start_usec := Time.get_ticks_usec() if trace_fixture_spawns else 0
	serial += 1
	var angle := TAU * float(slot) / float(scale)
	var ground := CENTER + Vector2.from_angle(angle) * (3.5 if mode != "aoe_death_loot" else 2.0)
	var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(76 if mode == "large_pets" else 24), game._canonical_ground_gu_to_screen_px(ground), false, -1.0,
		{"respawn_enabled": false, "spawn_slot_id": "t6:%d" % serial})
	assert(actor != null and actor.combat_enabled and actor.spatial_actor_runtime_id > 0, "formal load actor rejected")
	actor._rng.seed = SEED + serial
	_check(actor._spawn_facing_seed_override_active, "spawn_seed_hook_not_before_ready")
	actor_seed_inputs.append({"kind": "enemy", "ordinal": serial, "seed": str(actor._rng.seed), "initial_state": str(actor._rng.state)})
	scheduler_identity_inputs.append({"ordinal": serial, "native_instance_id": str(actor.get_instance_id()),
		"mod7": posmod(actor.get_instance_id(), 7), "mod11": posmod(actor.get_instance_id(), 11),
		"mod13": posmod(actor.get_instance_id(), 13), "retarget_timer": actor._retarget_timer,
		"crowd_timer": actor._crowd_steering_timer, "background_timer": actor._background_ai_timer,
		"environment_timer": actor._environment_guard_timer})
	actor.died.connect(_on_death)
	if mode != "aoe_death_loot":
		actor.max_hp = 1000000
		actor.current_hp = actor.max_hp
	if trace_fixture_spawns:
		assert(fixture_spawn_events.size() < 20000, "bounded fixture trace overflow")
		fixture_spawn_events.append({"ordinal": serial, "tick": Engine.get_physics_frames(), "start_usec": fixture_start_usec, "end_usec": Time.get_ticks_usec()})
	return actor

func _pin_spawn_inputs(node: Node) -> void:
	if node is LootPickup:
		native_loot_nodes_created += 1
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
	if detail_mode != "full":
		return
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
