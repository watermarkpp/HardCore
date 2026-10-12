extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Ready := preload("res://tests/helpers/formal_initial_ready.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Camera := preload("res://scripts/map_editor/map_diamond_camera_constraint_service.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const ItemTextures := preload("res://scripts/ui_item_texture_cache.gd")

class ProbeWorld extends "res://scripts/game_root.gd":
	var measured: Dictionary = {}
	func _process(delta: float) -> void:
		measured.clear()
		var started := Time.get_ticks_usec()
		super._process(delta)
		measured["root_process_usec"] = Time.get_ticks_usec() - started
	func _update_world_camera_constraint(delta := 1.0 / 60.0) -> void:
		var started := Time.get_ticks_usec()
		super._update_world_camera_constraint(delta)
		measured["camera_usec"] = Time.get_ticks_usec() - started
	func _pump_passive_monster_wakeup() -> void:
		var started := Time.get_ticks_usec()
		super._pump_passive_monster_wakeup()
		measured["passive_wake_usec"] = Time.get_ticks_usec() - started
	func _pump_pending_warm_textures() -> void:
		var started := Time.get_ticks_usec()
		super._pump_pending_warm_textures()
		measured["warm_textures_usec"] = Time.get_ticks_usec() - started
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var game: Node

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 38
	PlayerState.recalculate_stats()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	get_tree().root.size = Vector2i(2664, 1200)
	# main.tscn contains exactly GameRoot; overrides only time the real super
	# callbacks. No work, actors, collisions or cadence are replaced.
	game = ProbeWorld.new()
	add_child(game)
	await Ready.wait_for_initial_ready(self, game, "mengzhong_exit")
	# Actual production transition must publish a new complete birth plan.
	# test_mode's synchronous map hook cannot provide that acceptance evidence.
	PlayerState.test_mode = false
	check(game._request_map_travel(910003), "travel through the formal map transition")
	var deadline := Time.get_ticks_msec() + 60000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.current_map_id == 910003 and game.gameplay_input_is_enabled(), "formal Mengzhong READY")
	await get_tree().process_frame
	var population := map_population()
	var ready_summary: Dictionary = game._world_bootstrap_coordinator.ready_contract_summary()
	check(population >= 37, "the complete authored map population is retained")
	check(game._check_world_ready_contract(), "production READY contract remains valid before measurement")
	check(game.background._source_mask_image == null, "formal polygon map has no legacy collision chunk rebuild")
	var direction := Vector2(1.0, -1.0).normalized()
	var center := Vector2(41.0, 37.0)
	var boundary := center
	for step in range(1, 240):
		var point := center + direction * (float(step) * 0.25)
		if not Spatial.point_inside_safe_zones_ground_gu(point, game._active_safe_zones):
			boundary = point
			break
	check(boundary != center, "right-hand route reaches authored safe boundary")
	var start := boundary - direction * 1.0
	var perpendicular := Vector2(direction.y, -direction.x)
	for offset in [0.0, 0.25, -0.25, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0]:
		var candidate: Vector2 = boundary - direction * 1.0 + perpendicular * float(offset)
		var candidate_px: Vector2 = game._canonical_ground_gu_to_screen_px(candidate)
		if Spatial.point_inside_safe_zones_ground_gu(candidate, game._active_safe_zones) and not game.background.is_environment_actor_blocked(candidate_px, ArtSpec.PLAYER_COLLISION_RADIUS_PX):
			start = candidate
			break
	var start_px: Vector2 = game._canonical_ground_gu_to_screen_px(start)
	check(not game.background.is_environment_actor_blocked(start_px, ArtSpec.PLAYER_COLLISION_RADIUS_PX), "right-hand exit fixture begins on legal walkable ground")
	for pass_index in 3:
		game.player.set_touch_vector(Vector2.ZERO)
		game._set_player_world_position(start_px)
		game.player.velocity = Vector2.ZERO
		game._update_world_camera_constraint(0.0)
		var crossed := false
		var previous: Vector2 = game.player.global_position
		for tick in 100:
			game.player.set_touch_vector(Vector2.RIGHT)
			var started := Time.get_ticks_usec()
			await get_tree().physics_frame
			await get_tree().process_frame
			var frame_cpu_usec := Time.get_ticks_usec() - started
			var position: Vector2 = game.player.global_position
			var ground: Vector2 = game._canonical_screen_px_to_ground_gu(position)
			var inside: bool = game._player_inside_active_safe_zone()
			var camera_started := Time.get_ticks_usec()
			game._update_world_camera_constraint(0.0)
			var camera_usec := Time.get_ticks_usec() - camera_started
			var center_px: Vector2 = game._world_camera.get_screen_center_position()
			var presented: Vector2 = game._world_camera_presented_center
			samples.append({"pass":pass_index, "tick":tick, "frame_interval_usec":frame_cpu_usec,
				"ground":[ground.x,ground.y], "player_step_px":[position.x-previous.x,position.y-previous.y],
				"inside":inside, "camera_update_usec":camera_usec,
				"camera_px":[center_px.x,center_px.y], "presented_px":[presented.x,presented.y],
				"passive_candidates_used":game._passive_wake_candidates_used,
				"enemy_count":map_population(), "combat_target_count":game._active_enemy_cache.size(), "player_hp":game.player.current_hp,
				"measured":game.measured.duplicate(true), "item_texture_pending":ItemTextures.threaded_pending_count(),
				"budget":Budget.snapshot(),
				"camera_cache_builds":Camera.strict_cache_build_count()})
			check(center_px.distance_to(presented) < 0.05, "camera publishes the final presented center pass=%d tick=%d" % [pass_index,tick])
			previous = position
			if not inside:
				crossed = true
				break
		check(crossed, "natural rightward physics movement crosses safe boundary pass=%d" % pass_index)
	game.player.set_touch_vector(Vector2.ZERO)
	var file := FileAccess.open("res://outputs/test_logs/framework/mengzhong_safe_zone_world_exit_probe_test.observations.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"map_id":910003, "authored_spawn_markers":37, "population":population,
			"ready_summary":ready_summary, "zone_generation":game._zone_generation,
			"viewport":str(get_viewport().get_visible_rect().size), "boundary_ground":str(boundary),
			"samples":samples, "failures":failures, "device_test":"NOT_RUN"}, "  "))
		file.close()
	if not proof.write_receipt("mengzhong_safe_zone_world_exit_probe_test", checks, failures.size()): failures.append("receipt")
	print("MENGZHONG_SAFE_ZONE_WORLD_EXIT_PROBE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func map_population() -> int:
	var count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and int(enemy.get("runtime_map_id")) == 910003 and int(enemy.get_meta("zone_generation", -1)) == game._zone_generation:
			count += 1
	return count
