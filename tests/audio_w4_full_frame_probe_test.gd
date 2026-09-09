extends Node


const FORMAL_MAP_ID := 910004
const FORMAL_MAP_KEY := "world_wooma_forest"
const FIXED_SEED := 20260909
const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 240
const FORMAL_MAP_SIZE := Vector2(56.0, 56.0)
const MIN_SOURCE_SPACING_GU := 1.8
const MIN_PLAYER_DISTANCE_GU := 2.8
const MAX_SOURCE_OFFSET_X_PX := 680.0
const MAX_SOURCE_OFFSET_Y_PX := 285.0
const TARGET_DIRECTION_GU := [
	Vector2.RIGHT,
	Vector2.LEFT,
	Vector2.DOWN,
	Vector2.UP,
]


class ProbeCombatTarget extends Node2D:
	# This target is a real Node2D combat target in the formal map. It is kept
	# out of combat_targets so each actor retains the target assigned by the
	# fixture and production retarget/attack code still runs.
	var runtime_map_id: int = 910004
	var agility := 1
	var anti_poison := 0
	var damage_events := 0

	func take_damage(_amount: int = 0) -> void:
		damage_events += 1

	func is_stealthed() -> bool:
		return false


class FrameRecorder extends Node:
	var recording := false
	var samples: Array[float] = []
	var physics_ticks := 0

	func _process(delta: float) -> void:
		if recording:
			samples.append(maxf(0.0, delta) * 1000.0)

	func _physics_process(_delta: float) -> void:
		if recording:
			physics_ticks += 1

	func begin() -> void:
		samples.clear()
		physics_ticks = 0
		recording = true

	func end() -> void:
		recording = false


class AudioProxy extends Node:
	var backing: Node
	var request_count := 0
	var play_count := 0
	var rejected_count := 0
	var attack_start_request_count := 0
	var attack_frame_request_count := 0
	var combat_prompt_request_count := 0
	var other_request_count := 0
	var attack_start_requests_by_owner: Dictionary = {}
	var attack_start_requests_by_monster: Dictionary = {}
	var attack_frame_requests_by_monster: Dictionary = {}
	var request_counts_by_semantic: Dictionary = {}
	var play_counts_by_semantic: Dictionary = {}
	var rejection_reasons: Dictionary = {}
	var close_session_request_count := 0
	var service_call_samples_ms: Array[float] = []

	func reset() -> void:
		request_count = 0
		play_count = 0
		rejected_count = 0
		attack_start_request_count = 0
		attack_frame_request_count = 0
		combat_prompt_request_count = 0
		other_request_count = 0
		attack_start_requests_by_owner.clear()
		attack_start_requests_by_monster.clear()
		attack_frame_requests_by_monster.clear()
		request_counts_by_semantic.clear()
		play_counts_by_semantic.clear()
		rejection_reasons.clear()
		close_session_request_count = 0
		service_call_samples_ms.clear()

	func play_monster_event(
		monster_id: int,
		semantic_event: String,
		context: Dictionary = {},
	) -> Dictionary:
		var result := _forward_event(monster_id, semantic_event, context)
		_record_event(monster_id, semantic_event, context, result)
		return result

	func play_monster_combat_prompt(
		monster_id: int,
		audio_owner_key: String,
		context: Dictionary = {},
	) -> Dictionary:
		var prompt_context := context.duplicate(true)
		prompt_context["audio_owner_key"] = audio_owner_key
		var result: Dictionary = {}
		if backing != null and backing.has_method("play_monster_combat_prompt"):
			var started_usec := Time.get_ticks_usec()
			var raw_result: Variant = backing.call(
				"play_monster_combat_prompt",
				monster_id,
				audio_owner_key,
				context,
			)
			service_call_samples_ms.append(
				float(maxi(0, Time.get_ticks_usec() - started_usec)) / 1000.0
			)
			result = raw_result if raw_result is Dictionary else {}
		else:
			result = {"status": "unsupported", "reason": "legacy_service"}
		_record_event(monster_id, "combat_prompt", prompt_context, result)
		return result

	func end_monster_combat_session(
		audio_owner_key: String,
		reason := "explicit_disengage",
	) -> Dictionary:
		close_session_request_count += 1
		if backing == null or not backing.has_method("end_monster_combat_session"):
			return {"status": "unsupported", "reason": "legacy_service"}
		var raw_result: Variant = backing.call(
			"end_monster_combat_session",
			audio_owner_key,
			reason,
		)
		return raw_result if raw_result is Dictionary else {}

	func _forward_event(
		monster_id: int,
		semantic_event: String,
		context: Dictionary,
	) -> Dictionary:
		if backing == null or not backing.has_method("play_monster_event"):
			return {"status": "unsupported", "reason": "missing_service"}
		var started_usec := Time.get_ticks_usec()
		var raw_result: Variant = backing.call(
			"play_monster_event",
			monster_id,
			semantic_event,
			context,
		)
		service_call_samples_ms.append(
			float(maxi(0, Time.get_ticks_usec() - started_usec)) / 1000.0
		)
		return raw_result if raw_result is Dictionary else {}

	func _record_event(
		monster_id: int,
		semantic_event: String,
		context: Dictionary,
		result: Dictionary,
	) -> void:
		request_count += 1
		var semantic_key := semantic_event if not semantic_event.is_empty() else "<empty>"
		request_counts_by_semantic[semantic_key] = (
			int(request_counts_by_semantic.get(semantic_key, 0)) + 1
		)
		var status := str(result.get("status", "invalid_result"))
		if status == "played":
			play_count += 1
			play_counts_by_semantic[semantic_key] = (
				int(play_counts_by_semantic.get(semantic_key, 0)) + 1
			)
		else:
			rejected_count += 1
			var reason := str(result.get("reason", status))
			rejection_reasons[reason] = int(rejection_reasons.get(reason, 0)) + 1
		if semantic_event == "attack_start":
			attack_start_request_count += 1
			var owner_key := str(context.get("audio_owner_key", "")).strip_edges()
			if not owner_key.is_empty():
				attack_start_requests_by_owner[owner_key] = int(
					attack_start_requests_by_owner.get(owner_key, 0)
				) + 1
			var monster_key := str(monster_id)
			attack_start_requests_by_monster[monster_key] = int(
				attack_start_requests_by_monster.get(monster_key, 0)
			) + 1
		elif semantic_event == "attack_frame":
			attack_frame_request_count += 1
			var frame_key := str(monster_id)
			attack_frame_requests_by_monster[frame_key] = int(
				attack_frame_requests_by_monster.get(frame_key, 0)
			) + 1
		elif semantic_event == "combat_prompt":
			combat_prompt_request_count += 1
		else:
			other_request_count += 1

	func backing_metrics() -> Dictionary:
		if backing != null and backing.has_method("metrics_snapshot"):
			var raw_metrics: Variant = backing.call("metrics_snapshot")
			return raw_metrics if raw_metrics is Dictionary else {}
		if backing == null:
			return {}
		var request_serial: Variant = backing.get("_request_serial")
		return {
			"request_serial": int(request_serial) if request_serial is int or request_serial is float else 0,
		}

	func snapshot() -> Dictionary:
		return {
			"requests": request_count,
			"plays": play_count,
			"rejected": rejected_count,
			"attack_start_requests": attack_start_request_count,
			"attack_frame_requests": attack_frame_request_count,
			"combat_prompt_requests": combat_prompt_request_count,
			"other_requests": other_request_count,
			"close_session_requests": close_session_request_count,
			"requests_by_semantic": request_counts_by_semantic.duplicate(true),
			"plays_by_semantic": play_counts_by_semantic.duplicate(true),
			"attack_start_requests_by_owner": attack_start_requests_by_owner.duplicate(true),
			"attack_start_requests_by_monster": attack_start_requests_by_monster.duplicate(true),
			"attack_frame_requests_by_monster": attack_frame_requests_by_monster.duplicate(true),
			"rejection_reasons": rejection_reasons.duplicate(true),
			"service_call_samples_ms": service_call_samples_ms.duplicate(),
		}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(
		RuntimeDiagnostics.set_device_lab_performance_enabled(true),
		"Debug/Device Lab performance gate could not be enabled",
	)
	var all_results: Array[Dictionary] = []
	var saved_sfx_mute := false
	var saved_sfx_mute_captured := false

	var game: Node = await _build_formal_game()
	var service: Node = game.get("_audio_runtime_service")
	assert(service != null, "formal GameRoot audio service missing")
	var bus_index := AudioServer.get_bus_index(&"SFX")
	assert(bus_index >= 0, "formal SFX bus missing")
	saved_sfx_mute = AudioServer.is_bus_mute(bus_index)
	saved_sfx_mute_captured = true

	var player := game.get("player") as Node2D
	assert(player != null, "formal map player missing")
	var player_was_combat_target := player.is_in_group(&"combat_targets")
	if player_was_combat_target:
		player.remove_from_group(&"combat_targets")
	var camera_ground := await _place_player_and_camera(game)

	var proxy := AudioProxy.new()
	proxy.name = "AudioW4FullFrameProxy"
	proxy.backing = service
	service.remove_from_group(&"audio_runtime_service")
	proxy.add_to_group(&"audio_runtime_service")
	game.add_child(proxy)
	var frame_recorder := FrameRecorder.new()
	frame_recorder.name = "AudioW4FullFrameRecorder"
	game.add_child(frame_recorder)
	EnemyActor._audio_runtime_service = null
	EnemyActor._audio_service_retry_after_msec = 0

	var modes: Array[String] = []
	if service.has_method("set_sfx_enabled"):
		modes.append("candidate_on")
	else:
		modes.append("legacy_on")
		modes.append("legacy_off")

	# Keep both actor-count conditions in one GameRoot instance. A second main
	# scene would reconnect the HUD viewport signal and create an unrelated
	# duplicate-connection engine error in the strict runner.
	for actor_count in [50, 20]:
		var cohort: Array[Node] = await _retain_formal_cohort(game, actor_count)
		assert(
			cohort.size() == actor_count,
			"formal map did not retain exactly %d regular actors" % actor_count,
		)
		EnemyActor.reset_performance_diagnostics()
		var layout: Array[Dictionary] = _build_layout(game, cohort, camera_ground)
		assert(
			layout.size() == actor_count,
			"formal map could not produce %d legal visible source/target pairs (got %d)"
			% [actor_count, layout.size()],
		)

		for mode: String in modes:
			var condition := await _sample_condition(
				game,
				service,
				proxy,
				frame_recorder,
				cohort,
				layout,
				mode,
				actor_count,
			)
			all_results.append(condition)

	if player_was_combat_target and is_instance_valid(player):
		player.add_to_group(&"combat_targets")
	proxy.queue_free()
	EnemyActor._audio_runtime_service = null
	game.queue_free()
	await get_tree().process_frame

	if saved_sfx_mute_captured:
		var final_bus_index := AudioServer.get_bus_index(&"SFX")
		if final_bus_index >= 0:
			AudioServer.set_bus_mute(final_bus_index, saved_sfx_mute)
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	PlayerState.test_mode = previous_test_mode
	assert(not all_results.is_empty(), "formal full-frame probe produced no conditions")
	var payload := {
		"contract_id": "audio.runtime_budget.v1",
		"probe": "formal_map_full_frame_real_physics",
		"map_key": FORMAL_MAP_KEY,
		"map_id": FORMAL_MAP_ID,
		"seed": FIXED_SEED,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"conditions": all_results,
		"runtime_flavor": "candidate" if all_results[0].get("candidate_api", false) else "legacy",
		"comparison_note": (
			"cf1d runs legacy_on/legacy_off; W4 runs candidate_on. "
			+ "The 20 and 50 actor conditions reuse one formal GameRoot in descending "
			+ "cohort order; each condition resets actor positions, targets, sessions "
			+ "and counters before measuring. Legacy on/off conditions also reuse the "
			+ "same retained cohort and layout."
		),
		"target_fixture": (
			"Each retained EnemyActor receives one dedicated legal Node2D target "
			+ "with take_damage; targets are not combat_targets, so production target "
			+ "assignment, LOS, range, attack timer, animation and audio calls execute. "
			+ "The player is removed from combat_targets only to prevent a competing "
			+ "retarget candidate; this is a controlled formal-map fixture, not natural gameplay."
		),
		"headless_limitations": [
			"这是真实Godot process_frame/physics路径和正式地图实例化后的CPU/请求采样",
			"headless不代表扬声器混音延迟、硬件音频线程、GPU渲染提交或Android设备行为",
			"服务播放与拒绝仍由正式AudioRuntimeService预算/资源准入决定，探针不直调资源",
		],
	}
	print("AUDIO_W4_FULL_FRAME_COMPARE_JSON=" + JSON.stringify(payload))
	print("AUDIO_W4_FULL_FRAME_COMPARE_PASS：正式地图20/50每actor真实physics攻击与音频request证据完成")
	get_tree().quit(0)


func _build_formal_game() -> Node:
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "formal main scene missing")
	var game: Node = packed.instantiate()
	add_child(game)
	var deadline := 600
	while (
		int(game.get("current_map_id")) < 0
		or bool(game.get("_world_bootstrap_in_progress"))
	) and deadline > 0:
		await get_tree().process_frame
		deadline -= 1
	assert(int(game.get("current_map_id")) >= 0, "initial formal world did not become ready")
	var accepted: Variant = game.call("_request_map_travel", FORMAL_MAP_ID)
	assert(accepted is bool and bool(accepted), "formal map travel request rejected")
	deadline = 900
	while (
		int(game.get("current_map_id")) != FORMAL_MAP_ID
		or bool(game.get("_map_transition_in_progress"))
	) and deadline > 0:
		await get_tree().process_frame
		deadline -= 1
	assert(int(game.get("current_map_id")) == FORMAL_MAP_ID, "formal map did not become ready")
	if game.get("player") != null:
		(game.get("player") as Node).set_physics_process(false)
	return game


func _place_player_and_camera(game: Node) -> Vector2:
	var player := game.get("player") as Node2D
	var background := game.get("background") as Node
	assert(player != null and background != null, "formal camera fixture missing player/background")
	var existing_ground: Variant = game.call(
		"_canonical_screen_px_to_ground_gu",
		player.global_position,
	)
	var candidates: Array[Vector2] = [Vector2(27.5, 27.5)]
	if existing_ground is Vector2 and (existing_ground as Vector2).is_finite():
		candidates.push_front(existing_ground as Vector2)
	for radius in range(0, 6):
		for direction: Vector2 in TARGET_DIRECTION_GU:
			candidates.append(Vector2(27.5, 27.5) + direction * float(radius))
	for ground_position: Vector2 in candidates:
		if not _ground_inside_formal_map(ground_position):
			continue
		var screen_position: Variant = game.call(
			"_canonical_ground_gu_to_screen_px",
			ground_position,
		)
		if not screen_position is Vector2 or not (screen_position as Vector2).is_finite():
			continue
		var blocked := bool(background.call(
			"is_environment_actor_blocked",
			screen_position,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX,
		))
		if blocked:
			continue
		game.call("_set_player_world_position", screen_position)
		await get_tree().process_frame
		await get_tree().process_frame
		player.set_physics_process(false)
		return ground_position
	assert(false, "formal map has no legal player camera ground point")
	return Vector2.INF


func _retain_formal_cohort(game: Node, actor_count: int) -> Array[Node]:
	var regular: Array[Node] = []
	var all_enemies: Array[Node] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if int(candidate.get("runtime_map_id")) != FORMAL_MAP_ID:
			continue
		all_enemies.append(candidate)
		if not bool(candidate.get("is_boss")):
			regular.append(candidate)
	regular.sort_custom(Callable(self, "_sort_spawn_serial"))
	assert(regular.size() >= actor_count, "formal map lacks requested regular actor count")
	var cohort: Array[Node] = []
	for index in regular.size():
		if index < actor_count:
			cohort.append(regular[index])
		else:
			regular[index].queue_free()
	for enemy: Node in all_enemies:
		if enemy not in cohort:
			enemy.queue_free()
	await get_tree().process_frame
	var live_cohort: Array[Node] = []
	for enemy: Node in cohort:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.set_physics_process(false)
			live_cohort.append(enemy)
	return live_cohort


func _sort_spawn_serial(left: Node, right: Node) -> bool:
	return int(left.get_meta("spawn_serial", 0)) < int(right.get_meta("spawn_serial", 0))


func _build_layout(
	game: Node,
	cohort: Array[Node],
	camera_ground: Vector2,
) -> Array[Dictionary]:
	var background := game.get("background") as Node
	assert(background != null, "formal background missing for layout validation")
	var radius_probe := ProbeCombatTarget.new()
	game.add_child(radius_probe)
	var contact_distances: Array[float] = []
	for enemy: Node in cohort:
		var raw_contact: Variant = enemy.call(
			"_contact_distance_gu_to_target",
			radius_probe,
		)
		assert(raw_contact is int or raw_contact is float, "enemy contact distance missing")
		contact_distances.append(float(raw_contact))
	radius_probe.queue_free()

	var camera_screen := _ground_to_screen(game, camera_ground)
	var base_ground := Vector2(roundf(camera_ground.x), roundf(camera_ground.y))
	var candidate_records: Array[Dictionary] = []
	var order := 0
	for y in range(-18, 19):
		for x in range(-18, 19):
			var ground := base_ground + Vector2(float(x) + 0.5, float(y) + 0.5)
			if not _ground_inside_formal_map(ground):
				continue
			candidate_records.append({
				"ground": ground,
				"distance": ground.distance_to(camera_ground),
				"order": order,
			})
			order += 1
	candidate_records.sort_custom(Callable(self, "_sort_layout_candidates"))

	var chosen_sources: Array[Vector2] = []
	var layout: Array[Dictionary] = []
	for actor_index in cohort.size():
		var contact_distance := contact_distances[actor_index]
		var chosen := false
		for candidate: Dictionary in candidate_records:
			var raw_source_ground: Variant = candidate.get("ground", Vector2.INF)
			if not raw_source_ground is Vector2:
				continue
			var source_ground := raw_source_ground as Vector2
			if not source_ground.is_finite():
				continue
			if source_ground.distance_to(camera_ground) < MIN_PLAYER_DISTANCE_GU:
				continue
			var source_screen := _ground_to_screen(game, source_ground)
			if not _source_is_visible_from_camera(source_screen, camera_screen):
				continue
			if _source_is_too_close(source_ground, chosen_sources):
				continue
			if bool(background.call(
				"is_environment_actor_blocked",
				source_screen,
				ArtSpec.MONSTER_COLLISION_RADIUS_PX,
			)):
				continue
			for direction: Vector2 in TARGET_DIRECTION_GU:
				var target_ground := source_ground + direction * contact_distance
				if not _ground_inside_formal_map(target_ground):
					continue
				var target_screen := _ground_to_screen(game, target_ground)
				if not target_screen.is_finite():
					continue
				if bool(background.call("is_environment_point_blocked", target_screen)):
					continue
				if background.has_method("is_environment_segment_blocked_ground") and bool(background.call(
					"is_environment_segment_blocked_ground",
					source_ground,
					target_ground,
					0.125,
				)):
					continue
				if not _source_is_visible_from_camera(target_screen, camera_screen):
					continue
				chosen_sources.append(source_ground)
				layout.append({
					"source_ground": source_ground,
					"source_screen": source_screen,
					"target_ground": target_ground,
					"target_screen": target_screen,
					"contact_distance_gu": contact_distance,
				})
				chosen = true
				break
			if chosen:
				break
		assert(chosen, "no legal visible source/target pair for actor %d" % actor_index)
	return layout


func _sort_layout_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_distance := float(left.get("distance", INF))
	var right_distance := float(right.get("distance", INF))
	if not is_equal_approx(left_distance, right_distance):
		return left_distance < right_distance
	return int(left.get("order", 0)) < int(right.get("order", 0))


func _source_is_too_close(source_ground: Vector2, chosen_sources: Array[Vector2]) -> bool:
	for chosen: Vector2 in chosen_sources:
		if source_ground.distance_to(chosen) < MIN_SOURCE_SPACING_GU:
			return true
	return false


func _ground_inside_formal_map(ground_position: Vector2) -> bool:
	return (
		ground_position.is_finite()
		and ground_position.x >= 1.0
		and ground_position.y >= 1.0
		and ground_position.x <= FORMAL_MAP_SIZE.x - 1.0
		and ground_position.y <= FORMAL_MAP_SIZE.y - 1.0
	)


func _ground_to_screen(game: Node, ground_position: Vector2) -> Vector2:
	var raw_screen: Variant = game.call(
		"_canonical_ground_gu_to_screen_px",
		ground_position,
	)
	if raw_screen is Vector2:
		return raw_screen as Vector2
	return Vector2.INF


func _source_is_visible_from_camera(
	source_screen: Vector2,
	camera_screen: Vector2,
) -> bool:
	if not source_screen.is_finite() or not camera_screen.is_finite():
		return false
	var offset := source_screen - camera_screen
	return (
		absf(offset.x) <= MAX_SOURCE_OFFSET_X_PX
		and absf(offset.y) <= MAX_SOURCE_OFFSET_Y_PX
	)


func _sample_condition(
	game: Node,
	service: Node,
	proxy: AudioProxy,
	frame_recorder: FrameRecorder,
	cohort: Array[Node],
	layout: Array[Dictionary],
	mode: String,
	actor_count: int,
) -> Dictionary:
	var bus_index := AudioServer.get_bus_index(&"SFX")
	assert(bus_index >= 0, "SFX bus missing in formal scene")
	if service.has_method("set_sfx_enabled"):
		assert(mode == "candidate_on", "candidate probe received unsupported mode")
		service.call("set_sfx_enabled", true)
		AudioServer.set_bus_mute(bus_index, false)
	else:
		AudioServer.set_bus_mute(bus_index, mode == "legacy_off")

	var targets: Array[Node] = []
	if service.has_method("reset_metrics_for_test"):
		service.call("reset_metrics_for_test", true)
	for actor_index in cohort.size():
		var enemy := cohort[actor_index]
		if enemy.has_method("_reset_monster_audio_observer"):
			enemy.set("target", null)
			enemy.call("_reset_monster_audio_observer")
		else:
			enemy.set("_audio_appear_emitted", false)
		enemy.set("primary_target", null)
		var actor_layout := layout[actor_index]
		var source_screen: Vector2 = actor_layout["source_screen"]
		enemy.set_meta("spawn_position", source_screen)
		enemy.call("set_combat_position", source_screen, &"audio_w4_full_frame_probe")
		enemy.set("velocity", Vector2.ZERO)
		if enemy.has_method("set_audio_seed_for_test"):
			enemy.call("set_audio_seed_for_test", FIXED_SEED + actor_index)
		if enemy.has_method("_leave_background_deep_sleep"):
			enemy.call("_leave_background_deep_sleep")
		enemy.visible = true
		enemy.set_physics_process(true)
		var target := ProbeCombatTarget.new()
		target.name = "AudioW4Target_%d_%d" % [actor_count, actor_index]
		target.set_meta("runtime_map_id", FORMAL_MAP_ID)
		game.add_child(target)
		target.global_position = actor_layout["target_screen"]
		targets.append(target)
	assert(targets.size() == cohort.size(), "formal target fixture count mismatch")

	# Assign the target through the production property setter. The player is
	# deliberately absent from primary_target and combat_targets, so each actor
	# retains this independent target through its ordinary retarget cadence.
	for actor_index in cohort.size():
		cohort[actor_index].set("target", targets[actor_index])

	# Let target-edge prompts and the first ordinary physics ticks happen before
	# the measurement window. No actor physics method is called directly here.
	await _await_real_tick()
	for _warmup_index in range(WARMUP_FRAMES):
		await _await_real_tick()
	var sequence_before: Dictionary = {}
	for enemy: Node in cohort:
		sequence_before[enemy.get_instance_id()] = int(enemy.get("_audio_attack_sequence"))
	proxy.reset()
	if service.has_method("reset_metrics_for_test"):
		# Keep active combat sessions intact; this only starts a clean request and
		# budget counter window after the real target edge has been crossed.
		service.call("reset_metrics_for_test", false)
	assert(RuntimeDiagnostics.reset_performance_window().get("diagnostics_enabled", false), "performance window disabled")
	frame_recorder.begin()
	for _sample_index in range(SAMPLE_FRAMES):
		await _await_real_tick()
	frame_recorder.end()
	assert(
		frame_recorder.physics_ticks >= SAMPLE_FRAMES,
		"real physics-frame recorder captured %d/%d ticks" % [frame_recorder.physics_ticks, SAMPLE_FRAMES],
	)
	assert(
		frame_recorder.samples.size() >= SAMPLE_FRAMES,
		"real process-frame recorder captured only %d/%d frames" % [frame_recorder.samples.size(), SAMPLE_FRAMES],
	)

	var performance_window := RuntimeDiagnostics.read_performance_window({
		"probe": "audio_w4_full_frame_probe",
		"actor_count": actor_count,
		"mode": mode,
	})
	assert(int(performance_window.get("frame_count", 0)) >= SAMPLE_FRAMES, "DeviceLab frame window is incomplete")
	assert(int(performance_window.get("enemy_physics_calls", 0)) >= actor_count, "real enemy physics did not run")
	var expected_attack_starts := 0
	var expected_by_monster: Dictionary = {}
	var actor_proof: Array[Dictionary] = []
	for actor_index in cohort.size():
		var enemy := cohort[actor_index]
		var actor_id := enemy.get_instance_id()
		var before := int(sequence_before.get(actor_id, 0))
		var after := int(enemy.get("_audio_attack_sequence"))
		var attack_delta := after - before
		assert(attack_delta >= 1, "actor %d had no real attack start in sample window" % actor_index)
		assert(enemy.is_physics_processing(), "actor %d physics was disabled during sample" % actor_index)
		assert(enemy.visible and enemy.is_visible_in_tree(), "actor %d became invisible" % actor_index)
		assert(bool(enemy.call("_audio_is_listenable")), "actor %d was outside audible viewport" % actor_index)
		assert(enemy.get("target") == targets[actor_index], "actor %d lost its independent target" % actor_index)
		var owner_key := ""
		if enemy.has_method("_audio_owner_key_for_actor"):
			owner_key = str(enemy.call("_audio_owner_key_for_actor"))
		var owner_requests := int(proxy.attack_start_requests_by_owner.get(owner_key, 0))
		var monster_key := str(int(enemy.get("monster_id")))
		var monster_requests := int(proxy.attack_start_requests_by_monster.get(monster_key, 0))
		expected_attack_starts += attack_delta
		expected_by_monster[monster_key] = int(expected_by_monster.get(monster_key, 0)) + attack_delta
		if not owner_key.is_empty():
			assert(owner_requests == attack_delta, "candidate owner request count mismatch for actor %d" % actor_index)
		actor_proof.append({
			"actor_index": actor_index,
			"spawn_serial": int(enemy.get_meta("spawn_serial", -1)),
			"monster_id": int(enemy.get("monster_id")),
			"owner_key": owner_key,
			"attack_sequence_before": before,
			"attack_sequence_after": after,
			"attack_start_delta": attack_delta,
			"attack_start_requests_by_owner": owner_requests,
			"attack_start_requests_by_monster": monster_requests,
			"target_damage_events": int((targets[actor_index] as ProbeCombatTarget).damage_events),
			"source_ground": _vec2_payload(layout[actor_index]["source_ground"]),
			"target_ground": _vec2_payload(layout[actor_index]["target_ground"]),
			"source_canvas": _vec2_payload(enemy.get_global_transform_with_canvas().origin),
		})
	if proxy.attack_start_request_count != expected_attack_starts:
		assert(
			false,
			"attack_start service request count %d != real attack starts %d"
			% [proxy.attack_start_request_count, expected_attack_starts],
		)
	if not service.has_method("set_sfx_enabled"):
		for monster_key: String in expected_by_monster.keys():
			assert(
				int(proxy.attack_start_requests_by_monster.get(monster_key, 0)) == int(expected_by_monster[monster_key]),
				"legacy attack-start request count mismatch for monster %s" % monster_key,
			)

	var layout_records: Array[Dictionary] = []
	for actor_index in layout.size():
		layout_records.append({
			"actor_index": actor_index,
			"source_ground": _vec2_payload(layout[actor_index]["source_ground"]),
			"target_ground": _vec2_payload(layout[actor_index]["target_ground"]),
			"contact_distance_gu": float(layout[actor_index]["contact_distance_gu"]),
		})
	var service_metrics := proxy.backing_metrics()
	var proxy_metrics := proxy.snapshot()
	var bus_muted := AudioServer.is_bus_mute(bus_index)
	return {
		"candidate_api": service.has_method("set_sfx_enabled"),
		"map_key": FORMAL_MAP_KEY,
		"map_id": FORMAL_MAP_ID,
		"actor_count": actor_count,
		"mode": mode,
		"seed": FIXED_SEED,
		"sfx_bus_muted": bus_muted,
		"sfx_enabled": bool(service.call("is_sfx_enabled")) if service.has_method("is_sfx_enabled") else not bus_muted,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"sampled_physics_ticks": frame_recorder.physics_ticks,
		"real_process_frame_count": frame_recorder.samples.size(),
		"full_frame_ms": {
			"p50": float(performance_window.get("frame_ms_p50", 0.0)),
			"p95": float(performance_window.get("frame_ms_p95", 0.0)),
			"p99": float(performance_window.get("frame_ms_p99", 0.0)),
			"samples": int(performance_window.get("frame_count", 0)),
		},
		"frame_recorder_ms": _summary(frame_recorder.samples),
		"runtime_performance_window": performance_window,
		"service_requests_via_proxy": proxy_metrics["requests"],
		"service_plays_via_proxy": proxy_metrics["plays"],
		"service_rejected_via_proxy": proxy_metrics["rejected"],
		"audio_cpu_ms": _summary(proxy.service_call_samples_ms),
		"audio_cpu_scope": "production AudioRuntimeService admission/resource call time per observed request",
		"request_attribution": (
			"candidate_exact_owner_and_monster"
			if service.has_method("set_sfx_enabled")
			else "legacy_monster_id_and_global_event"
		),
		"attack_start_requests": proxy_metrics["attack_start_requests"],
		"attack_frame_requests": proxy_metrics["attack_frame_requests"],
		"combat_prompt_requests": proxy_metrics["combat_prompt_requests"],
		"service_proxy": proxy_metrics,
		"service_metrics": service_metrics,
		"expected_attack_starts": expected_attack_starts,
		"layout_signature": _layout_signature(layout),
		"layout": layout_records,
		"actor_proof": actor_proof,
	}


func _await_real_tick() -> void:
	# Headless idle frames can run faster than the fixed physics clock. Pair one
	# real physics-frame boundary with the following process-frame boundary so
	# the measured window includes a deterministic number of production physics
	# ticks and process callbacks without calling either callback directly.
	await get_tree().physics_frame
	await get_tree().process_frame


func _vec2_payload(value: Variant) -> Dictionary:
	if not value is Vector2 or not (value as Vector2).is_finite():
		return {"x": null, "y": null}
	return {"x": float((value as Vector2).x), "y": float((value as Vector2).y)}


func _layout_signature(layout: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for item: Dictionary in layout:
		var source: Vector2 = item["source_ground"]
		var target: Vector2 = item["target_ground"]
		parts.append(
			"%.3f,%.3f>%.3f,%.3f"
			% [source.x, source.y, target.x, target.y]
		)
	return "|".join(parts)


func _summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"p50": 0.0, "p95": 0.0, "p99": 0.0, "min": 0.0, "max": 0.0, "samples": 0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	return {
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"min": float(sorted[0]),
		"max": float(sorted[sorted.size() - 1]),
		"samples": sorted.size(),
	}


func _percentile(sorted: Array[float], fraction: float) -> float:
	var index := clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return float(sorted[index])
