extends Node2D
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Profile := preload("res://tests/source176_r3/causal_query_profile_test.gd")
const WALKABLE_CLASSES: Array[String] = ["walkable_cache_hit", "walkable_cache_miss", "walkable_cache_bypass", "walkable_invalid"]
var actor: Profile.ProfiledActor
var baseline: EnemyActor
var victim: PlayerCharacter
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func count(key: String) -> int:
	var row: Array = actor.hot.get(key, [0, 0])
	return int(row[0])

func walkable_query(point: Vector2, expected_class: String) -> bool:
	var prior: Dictionary = {}
	for key: String in WALKABLE_CLASSES:
		prior[key] = count(key)
	var before_entry := count("walkable_entry")
	var before_backend := count("walkable_backend")
	var actual := actor._hc_point_walkable(point)
	# The unprofiled actor queries the same real terrain/physics path afterwards.
	check(actual == baseline._hc_point_walkable(point), "profiled walkable result differed from baseline")
	check(count("walkable_entry") == before_entry + 1, "walkable entry was not counted exactly once")
	for key: String in WALKABLE_CLASSES:
		check(count(key) == int(prior[key]) + (1 if key == expected_class else 0), "walkable class mismatch: " + expected_class + "/" + key)
	var backend_expected := 0 if expected_class in ["walkable_cache_hit", "walkable_invalid"] else 1
	check(count("walkable_backend") == before_backend + backend_expected, "walkable backend was not called exactly once for the chosen class")
	return actual

func world_query(a: Vector2, b: Vector2, expected_class: String) -> void:
	var before_entry := count("world_entry")
	var before_hit := count("world_cache_hit")
	var before_miss := count("world_cache_miss")
	var before_backend := count("world_backend")
	var actual := actor._hc_world_between(a, b)
	check(actual == baseline._hc_world_between(a, b), "profiled WORLD result differed from baseline")
	check(count("world_entry") == before_entry + 1, "WORLD entry was not counted exactly once")
	check(count("world_cache_hit") == before_hit + (1 if expected_class == "world_cache_hit" else 0), "WORLD hit classification differed")
	check(count("world_cache_miss") == before_miss + (1 if expected_class == "world_cache_miss" else 0), "WORLD miss classification differed")
	check(count("world_backend") == before_backend + (1 if expected_class == "world_cache_miss" else 0), "WORLD backend was not called exactly once for a miss")

func immutable_context() -> Dictionary:
	var context := F.open_context()
	(context["blocked_cells"] as Dictionary).make_read_only()
	context.make_read_only()
	return context

func configure_both(context: Dictionary) -> void:
	actor.configure_terrain_navigation_context(context)
	baseline.configure_terrain_navigation_context(context)

func run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	victim = F.player(self, Vector2(25, 25))
	actor = F.enemy(self, 64, Vector2(28, 25), victim, {}, Profile.ProfiledActor.new()) as Profile.ProfiledActor
	baseline = F.enemy(self, 64, Vector2(28, 25), victim)
	actor.visual.set_process(false)
	baseline.visual.set_process(false)
	var position := actor.global_position
	var rng := actor._rng.state
	var attack_timer := actor._attack_timer
	var attack_serial := actor._attack_logic_serial
	var collision_layer_before := actor.collision_layer
	var collision_mask_before := actor.collision_mask
	var point := Vector2(27.125, 25.375)
	# Mutable fixture bypasses even when its backend invokes safe-zone scope.
	configure_both(F.open_context())
	var scope_before := count("query_scope")
	walkable_query(point, "walkable_cache_bypass")
	walkable_query(point, "walkable_cache_bypass")
	check(count("query_scope") > scope_before, "bypass counterexample did not exercise nested safe-zone scope")
	# Immutable terrain cache supports both true and false result hits.
	configure_both(immutable_context())
	walkable_query(point, "walkable_cache_miss")
	walkable_query(point, "walkable_cache_hit")
	walkable_query(point + Vector2(0.001, 0), "walkable_cache_miss")
	walkable_query(point + Vector2(0.001, 0), "walkable_cache_hit")
	var outside := Vector2(-10, -10)
	check(not walkable_query(outside, "walkable_cache_miss"), "outside point was walkable on the first query")
	check(not walkable_query(outside, "walkable_cache_hit"), "false cached result became walkable")
	walkable_query(Vector2.INF, "walkable_invalid")
	# Same-tick footprint, context and scope authority changes remain visible.
	actor.combat_radius_gu += 0.01
	baseline.combat_radius_gu = actor.combat_radius_gu
	walkable_query(point, "walkable_cache_miss")
	walkable_query(point, "walkable_cache_hit")
	actor.collision_radius_px += 0.01
	baseline.collision_radius_px = actor.collision_radius_px
	walkable_query(point, "walkable_cache_miss")
	configure_both(immutable_context())
	walkable_query(point, "walkable_cache_miss")
	actor.set_meta("zone_generation", 2)
	baseline.set_meta("zone_generation", 2)
	var build_before := count("scope_build")
	walkable_query(point, "walkable_cache_miss")
	check(count("scope_build") > build_before, "same-tick generation change did not rebuild scope")
	# WORLD entry hit is distinct from the attack LOS backend cache counters.
	var a := Vector2(28.125, 25.375)
	var b := Vector2(25.125, 25.375)
	world_query(a, b, "world_cache_miss")
	world_query(a, b, "world_cache_hit")
	world_query(a, b + Vector2(0.001, 0), "world_cache_miss")
	actor.set_meta("zone_generation", 3)
	baseline.set_meta("zone_generation", 3)
	world_query(a, b, "world_cache_miss")
	world_query(a, b, "world_cache_hit")
	# Native physics tick eviction, with both actors' AI still disabled.
	await get_tree().physics_frame
	walkable_query(point, "walkable_cache_miss")
	world_query(a, b, "world_cache_miss")
	check(actor.global_position == position and actor._rng.state == rng, "queries changed position or RNG")
	check(actor._attack_timer == attack_timer and actor._attack_logic_serial == attack_serial, "queries changed attack state")
	check(actor.collision_layer == collision_layer_before and actor.collision_mask == collision_mask_before, "queries changed collision participation")
	check(actor.crowd_profile_depth == 0 and actor.query_profile_depth == 0 and actor.walkable_profile_depth == 0 and actor.world_profile_depth == 0 and actor.walkable_backend_depth == 0, "diagnostic depth did not unwind")
	var metrics: Dictionary = actor.hot.duplicate(true)
	actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	F.dispose(baseline, victim)
	var evidence_written := F.write_evidence("causal_query_profile_probe", {"errors": failures, "checks": checks, "metrics": metrics,
		"scope": "Real query paths; mutable/immutable, false hit, small move, radii/context/generation/tick counterexamples; not a performance acceptance run"})
	if not evidence_written:
		failures.append("causal probe trace could not be written")
	print("R3_CAUSAL_QUERY_PROFILE_PROBE_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " errors=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
