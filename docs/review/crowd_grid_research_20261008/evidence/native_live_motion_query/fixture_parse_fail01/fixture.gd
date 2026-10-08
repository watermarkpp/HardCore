extends Node

const EXTENSION_PATH := "res://research/native/crowd_kernel/crowd_kernel.gdextension"
const MANIFEST_PATH := "res://outputs/crowd_native_live_motion_query_20261009/current_run_inputs.json"
const EnemyScript := preload("res://scripts/enemy.gd")
const WorldBackgroundScript := preload("res://scripts/world_background.gd")

class UnknownBackground extends WorldBackground:
	var revision_calls := 0
	func environment_collision_revision() -> int:
		revision_calls += 1
		return super.environment_collision_revision()

class UnknownEnemy extends EnemyActor:
	var position_calls := 0
	var damage_calls := 0
	func spatial_index_position() -> Vector2:
		position_calls += 1
		return super.spatial_index_position()
	func can_receive_damage() -> bool:
		damage_calls += 1
		return super.can_receive_damage()

var checks: Array[Dictionary] = []
var failed := false
var run_binding: Dictionary = {}
var kernel: Object
var old_calls := 0
var owned_nodes: Array[Node] = []
var case_counters: Array[Dictionary] = []
var mutation_owner: EnemyActor = null

func check(ok: bool, id: String, msg: String) -> void:
	checks.append({"id": id, "passed": ok, "message": msg})
	if not ok:
		failed = true
		print("HC_TEST_FAIL ", id, " ", msg)

func make_enemy(script: Script = EnemyScript) -> EnemyActor:
	var e: EnemyActor = script.new()
	owned_nodes.append(e)
	e.runtime_map_id = -1
	e.combat_radius_gu = 0.35
	e.current_hp = 20
	e.behavior_profile = {"worldCollision": true}
	e._body_admission_rejected = false
	e._death_pending = false
	e._dying = false
	e._hc_surround_goal = Vector2.INF
	return e

func candidate(pos: Vector2, script: Script = EnemyScript) -> EnemyActor:
	var e := make_enemy(script)
	e.global_position = pos
	return e

func counter_snapshot() -> Dictionary:
	return RuntimeDiagnostics.performance_counters()

func counter_delta(before: Dictionary, after: Dictionary, names: Array[String]) -> Dictionary:
	var result := {}
	for name: String in names:
		result[name] = int(after.get(name, 0)) - int(before.get(name, 0))
	return result

func old_motion(owner: EnemyActor, a: Vector2, b: Vector2, cs: Array) -> bool:
	old_calls += 1
	if owner.has_method("_hc_motion_candidates_legacy"):
		return bool(owner.call("_hc_motion_candidates_legacy", a, b, cs))
	return bool(owner.call("_hc_motion_candidates", a, b, cs))

func live_motion(owner: EnemyActor, a: Vector2, b: Vector2, cs: Array) -> Variant:
	return kernel.call("motion_candidates_live", owner, a, b, cs)

func compare_case(id: String, a: Vector2, b: Vector2, cs: Array, expected := -1) -> void:
	RuntimeDiagnostics.reset_performance_window()
	var old_result := old_motion(make_enemy(), a, b, cs)
	var old_counts := counter_snapshot()
	RuntimeDiagnostics.reset_performance_window()
	var live_result: Variant = live_motion(make_enemy(), a, b, cs)
	var live_counts := counter_snapshot()
	case_counters.append({"id": id, "old": old_counts, "live": live_counts, "delta": counter_delta(old_counts, live_counts, ["enemy_motion_candidate_checks", "enemy_motion_body_checks", "enemy_projection_calls"])})
	check(live_result != null, id + "-supported", "known owner enters native path")
	if live_result != null:
		check(bool(live_result) == old_result, id + "-result", "native result equals stock result")
	if expected != -1:
		check(old_result == bool(expected), id + "-stock", "stock result matches expected")

func screen_to_ground(v: Vector2) -> Vector2:
	return v

func mutating_screen_to_ground(v: Vector2) -> Vector2:
	if mutation_owner != null:
		mutation_owner.combat_radius_gu = 0.9
	return v

func configure_cache(e: EnemyActor, ground: Vector2, projection: Callable) -> void:
	e.runtime_map_id = 913203
	e.runtime_screen_to_ground_position_px = projection
	e._last_spatial_index_screen_position_px = e.global_position
	e._last_spatial_index_ground_position_gu = ground
	e._last_spatial_index_runtime_map_id = e.runtime_map_id
	e._last_spatial_index_zone_generation = int(e.get_meta("zone_generation", -1))
	e._last_spatial_index_environment_revision = 0
	e._last_spatial_index_projection = projection
	e.environment_blocker = WorldBackgroundScript.new()
	owned_nodes.append(e.environment_blocker)

func finish() -> void:
	var root := OS.get_environment("HARDCORE_AUDIT_EVIDENCE_ROOT")
	if root.is_empty(): root = ProjectSettings.globalize_path("res://outputs/crowd_native_live_motion_query_20261009")
	DirAccess.make_dir_recursive_absolute(root)
	var receipt := {"test":"crowd_native_live_motion_query_contract_20261009", "passed":not failed, "checks":checks, "old_calls":old_calls, "case_counters":case_counters, "run_binding":run_binding}
	if kernel != null and kernel.has_method("get_live_motion_stats"): receipt["live_motion_stats"] = kernel.call("get_live_motion_stats")
	var f := FileAccess.open(root.path_join("direct_result.json"), FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(receipt, "\t")); f.close()
	for node: Node in owned_nodes:
		if is_instance_valid(node): node.free()
	print("HC_CROWD_NATIVE_LIVE_MOTION_QUERY_CONTRACT_20261009_", "FAIL" if failed else "PASS", " checks=", checks.size())
	get_tree().quit(1 if failed else 0)

func _ready() -> void:
	var mf := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	check(mf != null, "binding-manifest", "producer manifest exists before native load")
	if mf == null: finish(); return
	var parsed: Variant = JSON.parse_string(mf.get_as_text())
	check(parsed is Dictionary, "binding-json", "manifest is a JSON object")
	if not parsed is Dictionary: finish(); return
	run_binding = parsed
	run_binding["manifest_sha256"] = FileAccess.get_sha256(MANIFEST_PATH)
	run_binding["engine_actual_path"] = OS.get_executable_path()
	run_binding["engine_actual_sha256"] = FileAccess.get_sha256(OS.get_executable_path())
	for input_path: String in run_binding.get("source_sha256", {}):
		check(FileAccess.get_sha256("res://" + input_path) == str(run_binding.source_sha256[input_path]), "binding-source-" + input_path, "source hash matches")
	check(FileAccess.get_sha256(OS.get_executable_path()) == str(run_binding.get("engine_sha256", "")), "binding-engine", "engine hash matches")
	var dll_path := str(run_binding.get("dll_path", "res://research/native/crowd_kernel/bin/crowd_melee_kernel.windows.template_debug.x86_64.dll"))
	if not dll_path.begins_with("res://"): dll_path = "res://" + dll_path
	check(FileAccess.get_sha256(dll_path) == str(run_binding.get("dll_sha256", "")), "binding-dll", "DLL hash matches")
	var extension = load(EXTENSION_PATH)
	kernel = ClassDB.instantiate("CrowdMeleeKernel")
	check(extension != null, "ABI-load", "extension resource loads")
	check(kernel != null, "ABI-class", "CrowdMeleeKernel registered")
	if kernel == null: finish(); return
	for method_name: String in ["configure_live_motion_scripts", "motion_candidates_live", "get_live_motion_stats", "reset_live_motion_stats"]:
		check(kernel.has_method(method_name), "api-" + method_name, "required API exists")
	if failed: finish(); return
	kernel.call("configure_live_motion_scripts", EnemyScript, WorldBackgroundScript)
	kernel.call("reset_live_motion_stats")
	var unsupported_node := Node.new(); owned_nodes.append(unsupported_node)
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.set_device_lab_detail_mode(RuntimeDiagnostics.DEVICE_LAB_DETAIL_FULL)
	RuntimeDiagnostics.reset_performance_window()
	var unsupported := kernel.call("motion_candidates_live", unsupported_node, Vector2.ZERO, Vector2.ONE, [])
	check(unsupported == null, "unsupported-owner-null", "unsupported owner returns nil")
	var stats: Dictionary = kernel.call("get_live_motion_stats")
	check(int(stats.get("unsupported_owner", 0)) == 1, "unsupported-owner-stats", "unsupported owner counted without old counter")
	compare_case("clear-empty", Vector2(-1,0), Vector2(1,0), [], 1)
	compare_case("crossing-first", Vector2(-1,0), Vector2(1,0), [candidate(Vector2.ZERO)], 0)
	compare_case("overlap-exit", Vector2(-0.4,0), Vector2(-0.9,0), [candidate(Vector2.ZERO)], 1)
	compare_case("tangent", Vector2(-1,0.7), Vector2(1,0.7), [candidate(Vector2.ZERO)], 1)
	var non_enemy := Node2D.new(); owned_nodes.append(non_enemy)
	var freed := Node2D.new(); freed.free()
	compare_case("invalid-freed-skip", Vector2(-1,0), Vector2(1,0), [null, non_enemy, freed, candidate(Vector2.ZERO)], 0)
	var dead := candidate(Vector2.ZERO); dead.current_hp = 0
	var pending := candidate(Vector2.ZERO); pending._death_pending = true
	var dying := candidate(Vector2.ZERO); dying._dying = true
	var rejected := candidate(Vector2.ZERO); rejected._body_admission_rejected = true
	compare_case("eligibility", Vector2(-1,0), Vector2(1,0), [dead,pending,dying,rejected], 1)
	var w0 := candidate(Vector2.ZERO); w0.behavior_profile = {"worldCollision":0}
	var w1 := candidate(Vector2.ZERO); w1.behavior_profile = {"worldCollision":1}
	var ws := candidate(Vector2.ZERO); ws.behavior_profile = {"worldCollision":"1"}
	var wv := candidate(Vector2.ZERO); wv.behavior_profile = {"worldCollision":Vector2.ONE}
	compare_case("variant-world-zero", Vector2(-1,0), Vector2(1,0), [w0], 1)
	compare_case("variant-world-one", Vector2(-1,0), Vector2(1,0), [w1], 0)
	compare_case("variant-world-string", Vector2(-1,0), Vector2(1,0), [ws], 0)
	compare_case("variant-world-vector", Vector2(-1,0), Vector2(1,0), [wv], 0)
	var self_owner := make_enemy(); var self_candidate := candidate(Vector2.ZERO)
	var self_old := old_motion(self_owner, Vector2(-1,0), Vector2(1,0), [self_owner, self_candidate])
	var self_live := live_motion(self_owner, Vector2(-1,0), Vector2(1,0), [self_owner, self_candidate])
	check(self_live != null and bool(self_live) == self_old, "self-skip", "same owner identity is skipped")
	var target_owner := make_enemy(); var target_candidate := candidate(Vector2.ZERO); target_owner.target = target_candidate
	var target_old := old_motion(target_owner, Vector2(-1,0), Vector2(1,0), [target_candidate])
	var target_live := live_motion(target_owner, Vector2(-1,0), Vector2(1,0), [target_candidate])
	check(target_live != null and bool(target_live) == target_old, "target-skip", "target identity is skipped")
	var map_candidate := candidate(Vector2.ZERO); map_candidate.runtime_map_id = 913203
	compare_case("map-mismatch", Vector2(-1,0), Vector2(1,0), [map_candidate], 1)
	var queued := candidate(Vector2.ZERO); queued.queue_free()
	compare_case("queued-skip", Vector2(-1,0), Vector2(1,0), [queued], 1)
	var projection := Callable(self, "screen_to_ground")
	var owner := make_enemy(); owner.global_position = Vector2(8,9); configure_cache(owner, Vector2.ZERO, projection)
	var cached := candidate(Vector2.ZERO); configure_cache(cached, Vector2.ZERO, projection)
	var old_cache := old_motion(owner, Vector2(-1,0), Vector2(1,0), [cached])
	var live_cache := live_motion(owner, Vector2(-1,0), Vector2(1,0), [cached])
	check(live_cache != null and bool(live_cache) == old_cache, "known-cache-hit", "known cache hit preserves result")
	cached.global_position = Vector2(32,32)
	var old_move := old_motion(owner, Vector2(-1,0), Vector2(1,0), [cached])
	var live_move := live_motion(owner, Vector2(-1,0), Vector2(1,0), [cached])
	check(live_move != null and bool(live_move) == old_move, "cache-position-mismatch", "position mismatch uses live position")
	cached.global_position = Vector2.ZERO
	configure_cache(cached, Vector2.ZERO, projection)
	var old_provider_candidate := candidate(Vector2.ZERO); configure_cache(old_provider_candidate, Vector2.ZERO, projection); old_provider_candidate.environment_blocker = UnknownBackground.new(); owned_nodes.append(old_provider_candidate.environment_blocker)
	var live_provider_candidate := candidate(Vector2.ZERO); configure_cache(live_provider_candidate, Vector2.ZERO, projection); live_provider_candidate.environment_blocker = UnknownBackground.new(); owned_nodes.append(live_provider_candidate.environment_blocker)
	var old_provider := old_motion(owner, Vector2(-1,0), Vector2(1,0), [old_provider_candidate])
	var old_provider_calls := (old_provider_candidate.environment_blocker as UnknownBackground).revision_calls
	var live_provider := live_motion(owner, Vector2(-1,0), Vector2(1,0), [live_provider_candidate])
	var live_provider_calls := (live_provider_candidate.environment_blocker as UnknownBackground).revision_calls
	check(live_provider != null and bool(live_provider) == old_provider, "unknown-provider-legacy", "unknown provider remains at original helper point")
	check(old_provider_calls == live_provider_calls and live_provider_calls == 1, "unknown-provider-once", "unknown provider is called once at the original helper point")
	var mismatch_candidate := candidate(Vector2.ZERO); configure_cache(mismatch_candidate, Vector2.ZERO, projection)
	for mismatch_id: String in ["map", "generation", "revision", "callable"]:
		if mismatch_id == "map": mismatch_candidate._last_spatial_index_runtime_map_id = 7
		elif mismatch_id == "generation": mismatch_candidate.set_meta("zone_generation", 2)
		elif mismatch_id == "revision": mismatch_candidate._last_spatial_index_environment_revision = 9
		else: mismatch_candidate._last_spatial_index_projection = Callable(self, "screen_to_ground")
		var mismatch_old := old_motion(owner, Vector2(-1,0), Vector2(1,0), [mismatch_candidate])
		var mismatch_live := live_motion(owner, Vector2(-1,0), Vector2(1,0), [mismatch_candidate])
		check(mismatch_live != null and bool(mismatch_live) == mismatch_old, "cache-mismatch-" + mismatch_id, "cache mismatch follows old projection path")
		configure_cache(mismatch_candidate, Vector2.ZERO, projection)
	mutation_owner = owner
	var mutating_candidate := candidate(Vector2.ZERO); configure_cache(mutating_candidate, Vector2.ZERO, Callable(self, "mutating_screen_to_ground")); mutating_candidate._last_spatial_index_projection = Callable()
	var mutating_old := old_motion(owner, Vector2(-1,0), Vector2(1,0), [mutating_candidate])
	var mutating_live := live_motion(owner, Vector2(-1,0), Vector2(1,0), [mutating_candidate])
	check(mutating_live != null and bool(mutating_live) == mutating_old, "projection-reentry-reread", "projection mutation preserves legacy reread timing")
	mutation_owner = null
	var unknown_owner := make_enemy(UnknownEnemy)
	check(live_motion(unknown_owner, Vector2(-1,0), Vector2(1,0), []) == null, "unsupported-owner-subclass", "unknown owner returns nil before old execution")
	var old_unknown_candidate := make_enemy(UnknownEnemy); old_unknown_candidate.global_position = Vector2.ZERO
	var live_unknown_candidate := make_enemy(UnknownEnemy); live_unknown_candidate.global_position = Vector2.ZERO
	var old_unknown_result := old_motion(make_enemy(), Vector2(-1,0), Vector2(1,0), [old_unknown_candidate])
	var live_unknown_result := live_motion(make_enemy(), Vector2(-1,0), Vector2(1,0), [live_unknown_candidate])
	check(live_unknown_result != null and bool(live_unknown_result) == old_unknown_result, "unknown-candidate-legacy", "unknown candidate stays at original loop point")
	check(live_unknown_candidate.position_calls == old_unknown_candidate.position_calls and live_unknown_candidate.damage_calls == old_unknown_candidate.damage_calls, "unknown-candidate-callback-order", "unknown candidate callback counts match original")
	finish()
