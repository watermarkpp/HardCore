extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Diagnostics := preload("res://scripts/runtime_diagnostics.gd")
@export var monster_count := 10
@export var profile_hot_paths := false
const HOT_NAMES: Array[String] = ["neighbor", "crowd_goal", "motion_clear", "footprint_miss", "contact_flank", "near_batch",
	"walkable_entry", "walkable_cache_hit", "walkable_cache_miss", "walkable_cache_bypass", "walkable_invalid",
	"walkable_backend", "walkable_miss_backend", "walkable_bypass_backend",
	"world_entry", "world_cache_hit", "world_cache_miss", "world_backend", "query_scope", "scope_reuse", "scope_build",
	"crowd_walkable_entry", "crowd_walkable_backend", "crowd_world_entry", "crowd_world_backend", "crowd_query_scope",
	"scope_from_walkable", "scope_from_world"]
class ProfiledActor extends EnemyActor:
	var hot: Dictionary = {}
	var crowd_profile_depth := 0
	var query_profile_depth := 0
	var walkable_profile_depth := 0
	var world_profile_depth := 0
	var walkable_backend_serial := 0
	var walkable_backend_usec := 0
	var walkable_entry_scope_serial := 0
	var walkable_backend_depth := 0
	var world_backend_serial := 0
	func add_hot(key: String, started: int) -> void:
		var row: Array = hot.get(key,[0,0])
		row[0] += 1
		row[1] += maxi(0,Time.get_ticks_usec()-started)
		hot[key] = row
	func add_causal_elapsed(key: String, elapsed: int) -> void:
		# Fixed metric names; no per-query event records or retained geometry.
		var raw: Variant = hot.get(key)
		if raw is Array:
			var row: Array = raw
			row[0] += 1
			row[1] += maxi(0, elapsed)
		else:
			hot[key] = [1, maxi(0, elapsed)]
	func _hc_point_walkable(point: Vector2) -> bool:
		var finite := point.is_finite()
		var before_backend := walkable_backend_serial
		var before_backend_usec := walkable_backend_usec
		var before_entry_scope := walkable_entry_scope_serial
		var in_crowd := crowd_profile_depth > 0
		query_profile_depth += 1
		walkable_profile_depth += 1
		var started := Time.get_ticks_usec()
		var result := super._hc_point_walkable(point)
		var elapsed := maxi(0, Time.get_ticks_usec() - started)
		walkable_profile_depth -= 1
		query_profile_depth -= 1
		add_causal_elapsed("walkable_entry", elapsed)
		if not finite:
			add_causal_elapsed("walkable_invalid", elapsed)
		elif walkable_backend_serial == before_backend:
			add_causal_elapsed("walkable_cache_hit", elapsed)
		elif walkable_entry_scope_serial != before_entry_scope:
			add_causal_elapsed("walkable_cache_miss", elapsed)
			add_causal_elapsed("walkable_miss_backend", walkable_backend_usec - before_backend_usec)
		else:
			add_causal_elapsed("walkable_cache_bypass", elapsed)
			add_causal_elapsed("walkable_bypass_backend", walkable_backend_usec - before_backend_usec)
		if in_crowd:
			add_causal_elapsed("crowd_walkable_entry", elapsed)
		return result
	func _hc_world_between(a: Vector2, b: Vector2) -> bool:
		var before_backend := world_backend_serial
		var in_crowd := crowd_profile_depth > 0
		query_profile_depth += 1
		world_profile_depth += 1
		var started := Time.get_ticks_usec()
		var result := super._hc_world_between(a, b)
		var elapsed := maxi(0, Time.get_ticks_usec() - started)
		world_profile_depth -= 1
		query_profile_depth -= 1
		add_causal_elapsed("world_entry", elapsed)
		if world_backend_serial == before_backend:
			add_causal_elapsed("world_cache_hit", elapsed)
		else:
			add_causal_elapsed("world_cache_miss", elapsed)
		if in_crowd:
			add_causal_elapsed("crowd_world_entry", elapsed)
		return result
	func _world_attack_path_is_clear(source_ground_gu: Vector2, target_ground_gu: Vector2,
		source_world_px: Vector2 = Vector2.INF, target_world_px: Vector2 = Vector2.INF,
		allow_cache := true, target_instance_id := 0, record_request := true) -> bool:
		if world_profile_depth <= 0:
			return super._world_attack_path_is_clear(source_ground_gu, target_ground_gu, source_world_px, target_world_px, allow_cache, target_instance_id, record_request)
		world_backend_serial += 1
		var started := Time.get_ticks_usec()
		var result := super._world_attack_path_is_clear(source_ground_gu, target_ground_gu, source_world_px, target_world_px, allow_cache, target_instance_id, record_request)
		var elapsed := maxi(0, Time.get_ticks_usec() - started)
		add_causal_elapsed("world_backend", elapsed)
		if crowd_profile_depth > 0:
			add_causal_elapsed("crowd_world_backend", elapsed)
		return result
	func _hc_static_query_scope(include_safe_zone_owner: bool) -> Array:
		if query_profile_depth <= 0:
			return super._hc_static_query_scope(include_safe_zone_owner)
		# An eligible walkable entry validates its scope before its backend.
		# Backend safe-zone scope calls cannot turn a bypass into a cache miss.
		if walkable_profile_depth > 0 and walkable_backend_depth <= 0:
			walkable_entry_scope_serial += 1
		var prior: Array = _hc_safe_scope if include_safe_zone_owner else _hc_world_scope
		var started := Time.get_ticks_usec()
		var result: Array = super._hc_static_query_scope(include_safe_zone_owner)
		var elapsed := maxi(0, Time.get_ticks_usec() - started)
		add_causal_elapsed("query_scope", elapsed)
		add_causal_elapsed("scope_reuse" if is_same(prior, result) else "scope_build", elapsed)
		if walkable_profile_depth > 0:
			add_causal_elapsed("scope_from_walkable", elapsed)
		elif world_profile_depth > 0:
			add_causal_elapsed("scope_from_world", elapsed)
		if crowd_profile_depth > 0:
			add_causal_elapsed("crowd_query_scope", elapsed)
		return result
	func _hc_neighbor(current: Vector2,hit_target: Node2D,direct: Vector2i) -> Vector2i:
		var started := Time.get_ticks_usec()
		var result := super._hc_neighbor(current,hit_target,direct)
		add_hot("neighbor",started)
		return result
	func _hc_crowd_position_goal(hit_target: Node2D) -> Vector2:
		var started := Time.get_ticks_usec()
		crowd_profile_depth += 1
		var result := super._hc_crowd_position_goal(hit_target)
		crowd_profile_depth -= 1
		add_hot("crowd_goal",started)
		return result
	func _hc_motion_clear(a: Vector2,b: Vector2) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_motion_clear(a,b)
		add_hot("motion_clear",started)
		return result
	func _hc_point_walkable_uncached(point: Vector2) -> bool:
		walkable_backend_serial += 1
		walkable_backend_depth += 1
		var started := Time.get_ticks_usec()
		var result := super._hc_point_walkable_uncached(point)
		var elapsed := maxi(0, Time.get_ticks_usec() - started)
		walkable_backend_depth -= 1
		walkable_backend_usec += elapsed
		add_causal_elapsed("walkable_backend", elapsed)
		add_hot("footprint_miss",started)
		if crowd_profile_depth > 0:
			add_causal_elapsed("crowd_walkable_backend", elapsed)
		return result
	func _hc_contact_flank(current: Vector2,anchor: Vector2,victim_anchor: Vector2,hit_target: Node2D,cell: Vector2i,preferred_sign: float) -> Vector2:
		var started := Time.get_ticks_usec()
		var result := super._hc_contact_flank(current,anchor,victim_anchor,hit_target,cell,preferred_sign)
		add_hot("contact_flank",started)
		return result
	func _hc_prepare_flank_batch(current: Vector2,anchor: Vector2,cell: Vector2i) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._hc_prepare_flank_batch(current,anchor,cell)
		add_hot("near_batch",started)
		return result

var hot_samples: Array = []
var last_hot: Dictionary = {}
func hot_totals() -> Dictionary:
	var result: Dictionary = {}
	for key: String in HOT_NAMES: result[key] = [0,0]
	for actor: EnemyActor in actors:
		if actor is ProfiledActor:
			for key: String in HOT_NAMES:
				var row: Array = actor.hot.get(key,[0,0])
				result[key][0] += int(row[0])
				result[key][1] += int(row[1])
	return result
var actors: Array[EnemyActor] = []
var victim: PlayerCharacter
var collecting := false
var frame_cpu_us: Array = []
var frame_wall_us: Array = []
var last_cpu := 0
var last_wall := 0
var sample_tick := 0
var motion_kind := "static"
var rows: Array = []
var index := F.Spatial.new()
var origin := Vector2(25,25)
var errors: Array[String] = []
func _ready() -> void:
	process_physics_priority = 10000
	run.call_deferred()
func percentile(values: Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[int((sorted.size()-1)*p)])/1000.0
func _physics_process(delta: float) -> void:
	if not collecting:
		return
	var cpu := Diagnostics.performance_counter(&"enemy_physics_usec")
	var wall := Time.get_ticks_usec()
	frame_cpu_us.append(maxi(0,cpu-last_cpu))
	frame_wall_us.append(maxi(0,wall-last_wall))
	last_cpu = cpu
	last_wall = wall
	if profile_hot_paths:
		var totals := hot_totals()
		var sample: Dictionary = {}
		for key: String in HOT_NAMES:
			sample[key] = [int(totals[key][0])-int(last_hot[key][0]),int(totals[key][1])-int(last_hot[key][1])]
		last_hot = totals
		if hot_samples.size()<180: hot_samples.append(sample)
	sample_tick += 1
	# Explicit benchmark trajectory, identical in baseline and candidate.
	# This is measurement input, not a natural-approach acceptance fixture.
	if motion_kind=="lateral":
		victim.global_position = F.to_screen(origin+Vector2(0,sin(sample_tick*delta*2.0)))
	elif motion_kind=="reverse":
		victim.global_position = F.to_screen(origin+Vector2(sin(sample_tick*delta*4.0),0))
func run() -> void:
	if monster_count != 30 or not profile_hot_paths or Engine.physics_ticks_per_second != 60:
		push_error("Causal profile requires exactly thirty actors, profiling enabled and sixty native physics ticks per second")
		get_tree().quit(1)
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Diagnostics.set_device_lab_performance_enabled(true)
	for temperature: String in ["cold","warm"]:
		for kind: String in ["static","lateral","reverse"]:
			motion_kind = kind
			victim = F.player(self,origin)
			for n in range(monster_count):
				var p := origin+Vector2.from_angle(TAU*n/float(monster_count))*4.5
				var actor := F.enemy(self,64,p,victim,{},ProfiledActor.new()) if profile_hot_paths else F.enemy(self,64,p,victim)
				actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
				actor.combat_spatial_index = index
				index.register(actor.spatial_actor_runtime_id,1,F.to_ground(actor.global_position),actor.combat_radius_gu,1,actor)
				actor._rng.seed = 20260930+n
				actor.visual.set_process(false)
				if temperature=="cold":
					actor.visual.active_resources = {}
				actors.append(actor)
			for actor: EnemyActor in actors:
				actor.set_physics_process(true)
			# 60 real frames of warmup; clocks and cadence are never hand driven.
			for n in range(60):
				await get_tree().physics_frame
			var counters_before := Diagnostics.performance_counters()
			last_cpu = Diagnostics.performance_counter(&"enemy_physics_usec")
			last_wall = Time.get_ticks_usec()
			frame_cpu_us = []
			frame_wall_us = []
			sample_tick = 0
			hot_samples = []
			last_hot = hot_totals() if profile_hot_paths else {}
			collecting = true
			for n in range(180):
				await get_tree().physics_frame
			collecting = false
			var starts := 0
			var movement := 0.0
			for actor: EnemyActor in actors:
				actor.set_physics_process(false)
				starts += actor._hc_starts
				movement += F.to_ground(actor.global_position).distance_to(F.to_ground(actor.get_meta("spawn_position")))
				if actor is ProfiledActor:
					if actor.crowd_profile_depth != 0 or actor.query_profile_depth != 0 or actor.walkable_profile_depth != 0 or actor.world_profile_depth != 0 or actor.walkable_backend_depth != 0:
						errors.append("causal diagnostic depth did not unwind")
					if actor.hot.size() > HOT_NAMES.size():
						errors.append("causal metrics exceeded their fixed bound")
			var counters_after := Diagnostics.performance_counters()
			var counters: Dictionary = {}
			for key: String in counters_after:
				counters[key] = int(counters_after[key])-int(counters_before.get(key,0))
			if frame_cpu_us.size()!=180 or movement<=.1:
				errors.append("missing native samples or real AI movement")
			rows.append({"count":monster_count,"motion":kind,"temperature":temperature,"samples":frame_cpu_us.size(),
				"cpu_p50_ms":percentile(frame_cpu_us,.5),"cpu_p95_ms":percentile(frame_cpu_us,.95),"cpu_p99_ms":percentile(frame_cpu_us,.99),
				"frame_interval_p95_ms":percentile(frame_wall_us,.95),"frame_interval_p99_ms":percentile(frame_wall_us,.99),
				"starts":starts,"hp_delta":victim.max_hp-victim.current_hp,"motion_gu":movement,"counters":counters,
				"cpu_samples_us":frame_cpu_us,"frame_intervals_us":frame_wall_us})
			if profile_hot_paths:
				if hot_samples.size()!=180: errors.append("bounded hot-path samples incomplete")
				rows[-1]["hot_path_samples"] = hot_samples
			for actor: EnemyActor in actors:
				index.unregister(actor.spatial_actor_runtime_id)
				actor.free()
			actors.clear()
			victim.free()
	var evidence_written := F.write_evidence("causal_query_profile_"+str(monster_count),{"errors":errors,"rows":rows,
		"causal_query_profile": true,
		"causal_metric_names": HOT_NAMES,
		"causal_query_scope": "Test-owned single-super wrappers; walkable/WORLD entries and nested scope validation; backend seam classifies actual hits; fixed aggregate metrics only; no production mutation",
		"causal_query_limits": "Nested inclusive spans overlap; diagnostic wrapper/counter/collector overhead retained; wall-clock deadlines may shift under instrumentation; no performance or behavior acceptance from this trace alone",
		"profile_hot_paths":profile_hot_paths,"profile_scope":"inclusive nested diagnostic times only; matching instrumentation; not uninstrumented performance acceptance","scope":"PC headless native physics 60; drawing disabled; explicit same benchmark trajectory; DEVICE TEST NOT_RUN"})
	if not evidence_written:
		errors.append("causal trace could not be written")
	print(("R3_CAUSAL_QUERY_PROFILE_PASS" if errors.is_empty() else "R3_CAUSAL_QUERY_PROFILE_FAIL")+" count="+str(monster_count)+" cases="+str(rows.size())+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
