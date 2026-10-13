extends Node

## Draft-only P3 synchronous numeric-view prototype.
## It wraps the real far-approach implementation: original _hc_motion_clear()
## performs the same identity-pool query and stage-0 predicate in both arms.
## The prototype only replaces later peer numeric getters after a cache-hit
## preflight. This file is not production/tests.
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "p3_numeric_view_prototype_v113_20261013"
var proof := Proof.new()
var failures := 0
var current_map_id := 92014
var _zone_generation := 1
const Background := preload("res://scripts/world_background.gd")
const PolyIndex := preload("res://scripts/map_editor/polygon/poly_index.gd")
var _current_provider: Node
const MAP_ID := 92014

class NumericView extends RefCounted:
	var peers: Array[EnemyActor] = []
	var positions := PackedVector2Array()
	var radii: Array[float] = []

class ViewEnemy extends EnemyActor:
	var reuse_storage := false
	var storage := NumericView.new()
	var fused_stage0 := false
	var prototype_active := false
	var view: NumericView = null
	var verify := false
	var mismatches := 0
	var shadow_checks := 0
	var phase := 0 # 0=stage0, 1=stage1, 2=destination
	var view_fallbacks := 0
	var preflight_usec := 0
	var view_motion_usec := 0
	var view_destination_usec := 0

	func _begin_prototype_far() -> void:
		prototype_active = true
		view = null
		phase = 0

	func _end_prototype_far() -> void:
		prototype_active = false
		view = null
		phase = 0

	func _preflight_view(candidates: Array) -> NumericView:
		var result := storage if reuse_storage else NumericView.new()
		if reuse_storage:
			result.peers.resize(candidates.size())
			result.positions.resize(candidates.size())
			result.radii.resize(candidates.size())
		var ordinal := 0
		for raw: Variant in candidates:
			if not is_instance_valid(raw) or not raw is EnemyActor:
				continue
			var peer := raw as EnemyActor
			if peer == self or peer == target or peer.runtime_map_id != runtime_map_id:
				continue
			if not peer._spatial_index_projection_cache_matches():
				return null
			var position: Vector2 = peer._last_spatial_index_ground_position_gu
			if not position.is_finite():
				return null
			if reuse_storage:
				result.peers[ordinal] = peer
				result.positions[ordinal] = position
				result.radii[ordinal] = float(peer.combat_radius_gu)
			else:
				result.peers.append(peer)
				result.positions.append(position)
				result.radii.append(float(peer.combat_radius_gu))
			ordinal += 1
		if reuse_storage:
			result.peers.resize(ordinal)
			result.positions.resize(ordinal)
			result.radii.resize(ordinal)
		return result

	func _hc_far_approach_waypoint(current: Vector2, anchor: Vector2, cell: Vector2i, preferred_sign: float) -> Vector2:
		if not prototype_active or _hc_surround_goal.is_finite():
			return super._hc_far_approach_waypoint(current, anchor, cell, preferred_sign)
		_begin_prototype_far()
		var result := super._hc_far_approach_waypoint(current, anchor, cell, preferred_sign)
		_end_prototype_far()
		return result

	func _hc_motion_candidates(a: Vector2, b: Vector2, candidates: Array) -> bool:
		if not prototype_active:
			return super._hc_motion_candidates(a, b, candidates)
		if phase == 0:
			var stage0: bool
			if fused_stage0:
				view = _preflight_view(candidates)
				if view != null:
					_record_performance_counter(&"enemy_motion_candidate_checks", candidates.size())
					stage0 = _view_motion(a,b,view)
					if verify:
						shadow_checks += 1
						mismatches += 0 if stage0 == super._hc_motion_candidates(a,b,candidates) else 1
				else:
					view_fallbacks += 1
					stage0 = super._hc_motion_candidates(a,b,candidates)
			else:
				stage0 = super._hc_motion_candidates(a,b,candidates)
				if stage0:
					view = _preflight_view(candidates)
					if view == null: view_fallbacks += 1
			if not stage0:
				view = null
				phase = 0
				return stage0
			phase = 1
			return stage0
		if phase == 1:
			if view == null:
				var live_stage1: bool = super._hc_motion_candidates(a, b, candidates)
				if not live_stage1:
					phase = 0
				return live_stage1
			_record_performance_counter(&"enemy_motion_candidate_checks", candidates.size())
			var stage1 := _view_motion(a, b, view)
			if verify:
				shadow_checks += 1
				mismatches += 0 if stage1 == super._hc_motion_candidates(a,b,candidates) else 1
			phase = 2 if stage1 else 0
			if not stage1:
				view = null
			return stage1
		return super._hc_motion_candidates(a, b, candidates)

	func _hc_flank_destination_candidates_clear(point: Vector2, candidates: Array) -> bool:
		if not prototype_active:
			return super._hc_flank_destination_candidates_clear(point, candidates)
		var result: bool
		if view == null:
			result = super._hc_flank_destination_candidates_clear(point, candidates)
		else:
			result = _view_destination(point, view)
			if verify:
				shadow_checks += 1
				mismatches += 0 if result == super._hc_flank_destination_candidates_clear(point,candidates) else 1
		phase = 0
		view = null
		return result

	func _view_motion(a: Vector2, b: Vector2, view_data: NumericView) -> bool:
		var low := Vector2(minf(a.x,b.x), minf(a.y,b.y))
		var high := Vector2(maxf(a.x,b.x), maxf(a.y,b.y))
		for ordinal in range(view_data.peers.size()):
			var other := view_data.peers[ordinal]
			if other == self or other == target or other.runtime_map_id != runtime_map_id:
				continue
			_record_performance_counter(&"enemy_motion_body_checks")
			var center := view_data.positions[ordinal]
			var peer_radius: float = view_data.radii[ordinal]
			var radius := maxf(0.0, combat_radius_gu + peer_radius) + HCPolicy.EPS
			if center.x < low.x-radius or center.x > high.x+radius or center.y < low.y-radius or center.y > high.y+radius:
				continue
			# Eligibility stays at the original live-read point.
			if not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
				continue
			if HCPolicy.core_crossed(a, b, center, combat_radius_gu, peer_radius):
				return false
		return true

	func _view_destination(point: Vector2, view_data: NumericView) -> bool:
		for ordinal in range(view_data.peers.size()):
			var other := view_data.peers[ordinal]
			if other == self or other == target or other.runtime_map_id != runtime_map_id:
				continue
			var radius := maxf(0.0, combat_radius_gu + view_data.radii[ordinal])
			if point.distance_squared_to(view_data.positions[ordinal]) >= radius * radius - HCPolicy.EPS:
				continue
			if other.can_receive_damage() and bool(other.behavior_profile.get("worldCollision", true)):
				return false
		return true

func _ground_to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

func _make_actor(index: Index, player: PlayerCharacter, serial: int, position: Vector2) -> ViewEnemy:
	var actor := ViewEnemy.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.set_meta("safe_zones", [])
	actor.environment_blocker = _current_provider
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, Callable(self,"_ground_to_screen"), Callable(self,"_screen_to_ground"))
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = player
	actor.primary_target = player
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	actor.set_combat_position(_ground_to_screen(position), &"p3_view_benchmark_spawn")
	return actor

func _case(peer_count: int, fused: bool, reused: bool, all_clear: bool) -> Dictionary:
	var index := Index.new()
	var provider := Background.new()
	var geometry := PolyIndex.new()
	_check(geometry.setup(Vector2i(128,128),[]),"formal polygon Index setup")
	provider._editor_runtime_collision_snapshot = {"design_size":Vector2i(128,128),"poly_index":geometry}
	_current_provider = provider
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(Vector2(36.5,20.5))
	add_child(player)
	player.set_physics_process(false)
	var peers: Array[ViewEnemy] = []
	for i in range(peer_count):
		var x := 30.5 + float(i % 10)
		var y := (18.75 if i % 2 == 0 else 22.25) if all_clear else (19.3 if i % 2 == 0 else 21.7)
		peers.append(_make_actor(index, player, i+1, Vector2(x,y)))
	var actor := _make_actor(index, player, peer_count+1, Vector2(30.5,20.5))
	actor.fused_stage0 = fused
	actor.reuse_storage = reused
	var current := actor.spatial_index_position()
	var anchor := Vector2(36.5,20.5)
	actor.prototype_active = false
	var expected := actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
	actor.prototype_active = true
	actor.verify = true
	var observed := actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
	_check(expected == observed,"waypoint equality %d" % peer_count)
	_check(actor.mismatches == 0 and actor.shadow_checks > 0,"actual stage predicates match %d" % peer_count)
	actor.verify = false
	var pairs: Array[Dictionary] = []
	var completion := 0
	for pair in range(8):
		var old_usec := 0
		var new_usec := 0
		for arm in ([false,true] if pair%2==0 else [true,false]):
			actor.prototype_active = arm
			actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
			actor.prototype_active = arm
			var started := Time.get_ticks_usec()
			for repeat in range(128):
				actor.prototype_active = arm
				var value := actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
				completion += 1 if value == expected else 0
			var elapsed := Time.get_ticks_usec()-started
			if arm: new_usec = elapsed
			else: old_usec = elapsed
		pairs.append({"pair":pair,"order":"AB" if pair%2==0 else "BA","control_usec":old_usec,"prototype_usec":new_usec,"calls_each":128})
	_check(completion == 8*2*128,"equal actual completion %d" % peer_count)
	var result := {"fused_stage0":fused,"reused_storage":reused,"environment_provider":"actual WorldBackground revision/actor methods","all_clear":all_clear,"internal_timing_hooks":false,"peer_count":peer_count,"actual_scratch_count":actor._hc_motion_scratch.size(),"pairs":pairs,"complete_equal_calls":completion,"prototype_preflight_usec":actor.preflight_usec,"prototype_view_motion_usec":actor.view_motion_usec,"prototype_view_destination_usec":actor.view_destination_usec,"prototype_fallbacks":actor.view_fallbacks,"predicate_checks":actor.shadow_checks,"predicate_mismatches":actor.mismatches,"production_safety":"NOT_PROVEN: fixture has pure projection and no external callbacks"}
	for peer: ViewEnemy in peers:
		index.unregister(peer.spatial_actor_runtime_id)
		peer.queue_free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
	player.queue_free()
	provider.free()
	_current_provider = null
	return result

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	failures += 0 if ok else 1

func _run() -> void:
	PlayerState.test_mode = true
	var rows: Array = []
	for count in [4,12,30,40]:
		for all_clear: bool in [false,true]:
			for variant in [[true,true]]:
				rows.append(_case(count,variant[0],variant[1],all_clear))
				await get_tree().process_frame
	var result := {"rows":rows,"status":"EXPERIMENT_ONLY","source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"framework_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"framework_invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"failures":failures}
	var file := FileAccess.open("res://outputs/collision_prepare_next_v113_20261013/P3_BENCHMARK.json",FileAccess.WRITE)
	_check(file != null,"prototype report opened")
	if file != null:
		file.store_string(JSON.stringify(result,"\t"));file.close()
	var ok := proof.write_receipt(SCENE_ID,proof.records.size(),failures)
	print("P3_NUMERIC_VIEW_", "PASS" if failures==0 and ok else "FAIL", " experimental_only ",JSON.stringify(result))
	get_tree().quit(0 if failures==0 and ok else 1)

