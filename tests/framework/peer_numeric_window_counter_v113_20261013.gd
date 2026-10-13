extends Node

## Draft standalone runner for the P3 peer numeric window.
## Keep this file outside tests/ until the controller registers it through the
## official runner. It uses real EnemyActor and RuntimeCombatSpatialIndex; it
## does not replace geometry or simulate the cost of a projection.
const EnemyActorScript := preload("res://scripts/enemy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "peer_numeric_window_counter_v113_20261013"
var proof := Proof.new()
var current_map_id := 92013
var _zone_generation := 1
const MAP_ID := 92013
const ZONE_GENERATION := 1

class CountingEnemy extends EnemyActor:
	var position_reads := 0
	var motion_candidate_calls := 0
	var motion_candidate_results: Array[bool] = []
	var motion_candidate_segments: Array[Array] = []
	var destination_calls := 0
	var destination_results: Array[bool] = []
	var destination_points: Array[Vector2] = []

	func spatial_index_position() -> Vector2:
		position_reads += 1
		return super.spatial_index_position()

	func _hc_motion_candidates(a: Vector2, b: Vector2, candidates: Array) -> bool:
		motion_candidate_calls += 1
		var result: bool = super._hc_motion_candidates(a, b, candidates)
		motion_candidate_results.append(result)
		motion_candidate_segments.append([a, b, candidates.size()])
		return result

	func _hc_flank_destination_candidates_clear(point: Vector2, candidates: Array) -> bool:
		destination_calls += 1
		var result: bool = super._hc_flank_destination_candidates_clear(point, candidates)
		destination_results.append(result)
		destination_points.append(point)
		return result

var index := Index.new()
var player: PlayerCharacter
var serial := 0
var projection_calls := 0
var rows: Array[Dictionary] = []
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _ground_to_screen(position: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(position)

func _counted_screen_to_ground(position: Vector2) -> Vector2:
	projection_calls += 1
	return GU.screen_delta_px_to_ground_delta_gu(position)

func _context() -> Dictionary:
	return Terrain.build(MAP_ID)

func _check(ok: bool, message: String) -> void:
	proof.record(ok,message)
	if not ok:
		failures.append(message)

func _new_actor(position: Vector2, counted := true) -> CountingEnemy:
	serial += 1
	var actor := CountingEnemy.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", ZONE_GENERATION)
	var projection := Callable(self, "_counted_screen_to_ground") if counted else Callable(self, "_counted_screen_to_ground")
	actor.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), projection)
	actor.configure_terrain_navigation_context(_context())
	actor.configure_spatial_index(index, serial)
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = player
	actor.primary_target = player
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	# This formal transaction publishes both global position and indexed ground
	# position, leaving the normal per-peer projection cache in the hit state.
	actor.set_combat_position(_ground_to_screen(position), &"p3_window_fixture_spawn")
	return actor

func _new_peer(position: Vector2) -> CountingEnemy:
	return _new_actor(position)

func _destroy(actor: CountingEnemy) -> void:
	if is_instance_valid(actor):
		index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()

func _reset_counters() -> void:
	projection_calls = 0
	for node: Node in get_children():
		if node is CountingEnemy:
			var actor := node as CountingEnemy
			actor.position_reads = 0
			actor.motion_candidate_calls = 0
			actor.motion_candidate_results.clear()
			actor.motion_candidate_segments.clear()
			actor.destination_calls = 0
			actor.destination_results.clear()
			actor.destination_points.clear()

func _invalidate_peer_projection_cache(peers: Array[CountingEnemy]) -> void:
	for peer: CountingEnemy in peers:
		# Deliberately create a projection-cache miss without moving or
		# re-registering the actor. This is a fixture-only probe of the existing
		# cache gate, not a production state transition.
		peer._last_spatial_index_projection = Callable()

func _run_one(label: String, actor: CountingEnemy, peers: Array[CountingEnemy], current: Vector2, anchor: Vector2, invalidate_cache: bool) -> void:
	if invalidate_cache:
		_invalidate_peer_projection_cache(peers)
	_reset_counters()
	var revision_before := index.bucket_membership_revision
	var query_before := index.index_query_count
	var started := Time.get_ticks_usec()
	var waypoint := actor._hc_far_approach_waypoint(current, anchor, Vector2i(current.floor()), 1.0)
	var elapsed_usec := Time.get_ticks_usec() - started
	var row := {
		"label": label,
		"cache_mode": "miss" if invalidate_cache else "hit",
		"waypoint": str(waypoint),
		"waypoint_finite": waypoint.is_finite(),
		"elapsed_usec": elapsed_usec,
		"actor_position_reads": actor.position_reads,
		"actor_motion_candidate_calls": actor.motion_candidate_calls,
		"actor_motion_candidate_results": actor.motion_candidate_results.duplicate(),
		"actor_motion_candidate_segments": actor.motion_candidate_segments.duplicate(true),
		"actor_destination_calls": actor.destination_calls,
		"actor_destination_results": actor.destination_results.duplicate(),
		"actor_destination_points": actor.destination_points.duplicate(),
		"peer_position_reads": [],
		"peer_projection_calls": projection_calls,
		"index_query_count_delta": index.index_query_count - query_before,
		"membership_revision_before": revision_before,
		"membership_revision_after": index.bucket_membership_revision,
	}
	for peer: CountingEnemy in peers:
		(row["peer_position_reads"] as Array).append(peer.position_reads)
	rows.append(row)

func _all_pass_row(row: Dictionary) -> bool:
	if not bool(row.get("waypoint_finite", false)):
		return false
	if int(row.get("actor_motion_candidate_calls", 0)) <= 0:
		return false
	if int(row.get("actor_destination_calls", 0)) <= 0:
		return false
	for result: bool in row.get("actor_motion_candidate_results", []):
		if not result:
			return false
	for result: bool in row.get("actor_destination_results", []):
		if not result:
			return false
	return true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.name = "P3WindowPlayer"
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", ZONE_GENERATION)
	player.global_position = _ground_to_screen(Vector2(26.5, 20.5))
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	await get_tree().physics_frame

	# Twelve real registered peers lie in the neighbouring coarse buckets. Their
	# perpendicular offset keeps them outside the exact route while keeping them
	# present in the complete identity pool.
	var peers: Array[CountingEnemy] = []
	for i in range(12):
		var x := 20.5 + float(i % 6)
		var y := 18.75 if i < 6 else 22.25
		peers.append(_new_peer(Vector2(x, y)))
	var actor := _new_actor(Vector2(20.5, 20.5))
	var current := actor.spatial_index_position()
	var anchor := Vector2(26.5, 20.5)
	_run_one("all_clear_cache_hit", actor, peers, current, anchor, false)
	_run_one("all_clear_cache_miss", actor, peers, current, anchor, true)
	_check(_all_pass_row(rows[0]), "all-clear cache-hit did not execute a fully passing stage 0/1/2 path")
	_check(_all_pass_row(rows[1]), "all-clear cache-miss did not execute a fully passing stage 0/1/2 path")

	for peer: CountingEnemy in peers:
		_destroy(peer)
	await get_tree().process_frame
	peers.clear()
	# A live blocker on the first side-order waypoint makes stage 0 fail for one
	# actual candidate. The real far-approach routine must then try its next side;
	# no result is forced.
	var blocker := _new_peer(Vector2(21.5, 21.5))
	var blocked_actor := actor
	_run_one("stage0_blocked", blocked_actor, [blocker], blocked_actor.spatial_index_position(), anchor, false)
	var blocked_row: Dictionary = rows.back()
	var has_stage0_false := false
	for i in range(blocked_actor.motion_candidate_segments.size()):
		var segment: Array = blocked_actor.motion_candidate_segments[i]
		if segment[1] == Vector2(21.5, 21.5) and not bool(blocked_actor.motion_candidate_results[i]):
			has_stage0_false = true
	_check(has_stage0_false, "stage0 blocker did not produce a real failed chord predicate")
	_check(int(blocked_row.get("actor_motion_candidate_calls", 0)) > 0, "blocked far approach did not call real motion candidate stage")

	for peer: CountingEnemy in peers:
		_destroy(peer)
	_destroy(actor)
	_destroy(blocker)
	await get_tree().process_frame
	var evidence := {"schema": "p3_peer_numeric_window_v113_20261013_v1", "rows": rows, "failures": failures}
	evidence["source_content_sha256"] = OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	evidence["framework_run_id"] = OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	evidence["framework_invocation_id"] = OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var out := FileAccess.open("res://outputs/collision_prepare_next_v113_20261013/P3_COUNTS.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(evidence, "  "))
		out.close()
	print("P3_PEER_NUMERIC_WINDOW_", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify(evidence))
	var receipt_ok := proof.write_receipt(SCENE_ID,proof.records.size(),failures.size())
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)

