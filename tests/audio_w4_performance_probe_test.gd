extends Node


const FORMAL_MAP_ID := 910004
const FORMAL_MAP_KEY := "world_wooma_forest"
const FIXED_SEED := 20260909
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 64
const FRAME_DELTA := 1.0 / 60.0


class AudioProxy extends Node:
	var backing: Node
	var request_count := 0
	var play_count := 0

	func play_monster_event(
		monster_id: int,
		semantic_event: String,
		context: Dictionary = {},
	) -> Dictionary:
		request_count += 1
		var raw_result: Variant = backing.call(
			"play_monster_event",
			monster_id,
			semantic_event,
			context,
		)
		var result := raw_result as Dictionary
		if str(result.get("status", "")) == "played":
			play_count += 1
		return result

	func play_monster_combat_prompt(
		monster_id: int,
		audio_owner_key: String,
		context: Dictionary = {},
	) -> Dictionary:
		request_count += 1
		var raw_result: Variant = backing.call(
			"play_monster_combat_prompt",
			monster_id,
			audio_owner_key,
			context,
		)
		var result := raw_result as Dictionary
		if str(result.get("status", "")) == "played":
			play_count += 1
		return result

	func end_monster_combat_session(audio_owner_key: String, reason := "") -> Dictionary:
		var raw_result: Variant = backing.call(
			"end_monster_combat_session",
			audio_owner_key,
			reason,
		)
		return raw_result as Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var all_results: Array[Dictionary] = []
	var game := await _build_formal_game()
	var service: Node = game.get("_audio_runtime_service")
	assert(service != null, "formal GameRoot audio service missing")
	var candidate_api_seen := service.has_method("set_sfx_enabled")
	var full_cohort: Array[Node] = await _retain_formal_cohort(game, 50)
	assert(full_cohort.size() == 50, "formal map lacks the 50 actor cohort")
	var proxy := AudioProxy.new()
	proxy.name = "AudioPerformanceProxy"
	proxy.backing = service
	service.remove_from_group(&"audio_runtime_service")
	proxy.add_to_group(&"audio_runtime_service")
	game.add_child(proxy)
	EnemyActor._audio_runtime_service = null
	EnemyActor._audio_service_retry_after_msec = 0

	for actor_count in [20, 50]:
		var cohort := _prefix_cohort(full_cohort, actor_count)
		var modes: Array = (
			["candidate_on"] if candidate_api_seen else ["legacy_on", "legacy_off"]
		)
		for mode: String in modes:
			var condition := await _sample_condition(
				game,
				service,
				proxy,
				cohort,
				mode,
				actor_count,
			)
			all_results.append(condition)
	proxy.queue_free()
	EnemyActor._audio_runtime_service = null
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame

	assert(not all_results.is_empty(), "formal performance probe produced no conditions")
	var payload := {
		"contract_id": "audio.runtime_budget.v1",
		"probe": "formal_map_actor_cohort_headless",
		"map_key": FORMAL_MAP_KEY,
		"map_id": FORMAL_MAP_ID,
		"seed": FIXED_SEED,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"conditions": all_results,
		"runtime_flavor": "candidate" if candidate_api_seen else "legacy",
		"comparison_note": "Run this same test once at cf1d legacy and once at the W4 candidate; legacy emits legacy_on/off, candidate emits candidate_on.",
		"headless_limitations": [
			"仅测正式地图实例化后的EnemyActor逐帧CPU与音频服务请求路径",
			"headless不代表真实扬声器混音延迟、硬件音频线程、渲染提交或Android设备行为",
			"两次运行共用固定地图/actor数量/种子/热身与采样窗口，输出目录按工作树隔离",
		],
	}
	print("AUDIO_W4_PERF_COMPARE_JSON=" + JSON.stringify(payload))
	print("AUDIO_W4_PERF_COMPARE_PASS：cf1d基准与W4候选固定正式地图20/50 actor采样入口完成")
	PlayerState.test_mode = previous_test_mode
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
	# travel_to_map is the public void wrapper; the private request returns the
	# synchronous acceptance bit that this probe needs to distinguish a rejected
	# setup from a map that is still loading.
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


func _retain_formal_cohort(game: Node, actor_count: int) -> Array[Node]:
	var regular: Array[Node] = []
	var all_enemies: Array[Node] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(candidate):
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


func _prefix_cohort(full_cohort: Array[Node], actor_count: int) -> Array[Node]:
	var result: Array[Node] = []
	for index in mini(actor_count, full_cohort.size()):
		result.append(full_cohort[index])
	return result


func _sort_spawn_serial(left: Node, right: Node) -> bool:
	return int(left.get_meta("spawn_serial", 0)) < int(right.get_meta("spawn_serial", 0))


func _sample_condition(
	game: Node,
	service: Node,
	proxy: AudioProxy,
	cohort: Array[Node],
	mode: String,
	actor_count: int,
) -> Dictionary:
	var bus_index := AudioServer.get_bus_index(&"SFX")
	assert(bus_index >= 0, "SFX bus missing in formal scene")
	if service.has_method("set_sfx_enabled"):
		service.call("set_sfx_enabled", true)
		AudioServer.set_bus_mute(bus_index, false)
	else:
		AudioServer.set_bus_mute(bus_index, mode == "legacy_off")
	proxy.request_count = 0
	proxy.play_count = 0
	if service.has_method("reset_metrics_for_test"):
		service.call("reset_metrics_for_test", true)

	get_tree().paused = true
	var player := game.get("player") as Node2D
	assert(player != null, "formal map player missing")
	var audio_targeted_actor_count := 0
	var audio_unlistenable_actor_count := 0
	for index: int in cohort.size():
		var enemy := cohort[index]
		if enemy.has_method("_reset_monster_audio_observer"):
			enemy.set("target", null)
			enemy.call("_reset_monster_audio_observer")
		else:
			enemy.set("_audio_appear_emitted", false)
		var authored_position: Variant = enemy.get_meta("spawn_position", enemy.global_position)
		if authored_position is Vector2 and enemy.has_method("set_combat_position"):
			enemy.call("set_combat_position", authored_position, &"audio_performance_probe")
		if enemy.has_method("set_audio_seed_for_test"):
			enemy.call("set_audio_seed_for_test", FIXED_SEED + index)
		if enemy.has_method("_leave_background_deep_sleep"):
			enemy.call("_leave_background_deep_sleep")
		enemy.set_physics_process(true)
		enemy.visible = true
		# Preserve the production viewport audibility gate while making the real
		# service path observable: an off-screen actor has no combat edge in this
		# probe, while an actor already in the viewport gets the same target edge
		# that gameplay would deliver.
		if bool(enemy.call("_audio_is_listenable")):
			audio_targeted_actor_count += 1
			enemy.set("target", player)
		else:
			audio_unlistenable_actor_count += 1

	var warmup_samples: Array[float] = []
	var audio_debug: Array[Dictionary] = []
	for debug_index in mini(5, cohort.size()):
		var debug_enemy := cohort[debug_index]
		audio_debug.append({
			"monster_id": int(debug_enemy.get("monster_id")),
			"target_valid": is_instance_valid(debug_enemy.get("target")),
			"process_mode": int(debug_enemy.process_mode),
			"physics_processing": debug_enemy.is_physics_processing(),
			"visible": debug_enemy.visible,
			"visible_in_tree": debug_enemy.is_visible_in_tree(),
			"background_deep_sleeping": _bool_property(debug_enemy, "_background_deep_sleeping"),
			"background_maintenance_running": _bool_property(debug_enemy, "_background_maintenance_running"),
			"dying": _bool_property(debug_enemy, "_dying"),
			"death_pending": _bool_property(debug_enemy, "_death_pending"),
			"current_hp": int(debug_enemy.get("current_hp")),
			"burrowed": _bool_property(debug_enemy, "_burrowed"),
			"global_position": debug_enemy.global_position,
			"canvas_position": debug_enemy.get_global_transform_with_canvas().origin,
			"viewport_rect": debug_enemy.get_viewport().get_visible_rect(),
			"listenable": bool(debug_enemy.call("_audio_is_listenable")),
			"entry_seen": _bool_property(debug_enemy, "_audio_combat_entry_seen"),
			"session_active": _bool_property(debug_enemy, "_audio_combat_session_active"),
		})
	for _warmup in range(WARMUP_FRAMES):
		var warmup_started := Time.get_ticks_usec()
		for enemy: Node in cohort:
			enemy.call("_physics_process", FRAME_DELTA)
		warmup_samples.append(float(Time.get_ticks_usec() - warmup_started) / 1000.0)
	var full_frame_samples: Array[float] = []
	for _sample in range(SAMPLE_FRAMES):
		var frame_started := Time.get_ticks_usec()
		for enemy: Node in cohort:
			enemy.call("_physics_process", FRAME_DELTA)
		full_frame_samples.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
	var audio_cpu_samples: Array[float] = []
	for _sample in range(SAMPLE_FRAMES):
		var audio_started := Time.get_ticks_usec()
		for enemy: Node in cohort:
			if enemy.has_method("_audio_try_enter_combat_session"):
				enemy.call("_audio_try_enter_combat_session")
			if enemy.has_method("_audio_observe_visual_state"):
				enemy.call("_audio_observe_visual_state")
		audio_cpu_samples.append(float(Time.get_ticks_usec() - audio_started) / 1000.0)
	get_tree().paused = false

	var service_metrics: Dictionary = {}
	if service.has_method("metrics_snapshot"):
		service_metrics = service.call("metrics_snapshot")
	else:
		service_metrics = {"request_serial": int(service.get("_request_serial"))}
	var visible_count := 0
	for enemy: Node in cohort:
		if enemy.has_method("_audio_is_listenable") and bool(enemy.call("_audio_is_listenable")):
			visible_count += 1
	return {
		"map_key": FORMAL_MAP_KEY,
		"map_id": FORMAL_MAP_ID,
		"actor_count": actor_count,
		"mode": mode,
		"seed": FIXED_SEED,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"visible_audio_actor_count": visible_count,
		"audio_targeted_actor_count": audio_targeted_actor_count,
		"audio_unlistenable_actor_count": audio_unlistenable_actor_count,
		"audio_debug_first_five": audio_debug,
		"service_requests_via_proxy": proxy.request_count,
		"service_plays_via_proxy": proxy.play_count,
		"service_metrics": service_metrics,
		"warmup_frame_ms": _summary(warmup_samples),
		"full_frame_ms": _summary(full_frame_samples),
		"audio_cpu_ms": _summary(audio_cpu_samples),
	}


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


func _bool_property(node: Node, property_name: String) -> bool:
	var raw_value: Variant = node.get(property_name)
	return bool(raw_value) if raw_value is bool else false


func _percentile(sorted: Array[float], fraction: float) -> float:
	var index := clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return float(sorted[index])
