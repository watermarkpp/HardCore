extends Node

const Background := preload("res://scripts/world_background.gd")
const Replay := preload("res://tests/framework/helpers/static_polygon_replay_job.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const SCENE_ID := "footprint_template_benchmark_v113_20261013"
var proof := Proof.new()
var checks := 0
var failures := 0

class BaselineBackground extends "res://scripts/world_background.gd":
	# Exact pre-change formal branch. No mock of generation or real Index.
	func is_environment_actor_blocked(center_world_px: Vector2,collision_radius_px: float) -> bool:
		if _editor_runtime_collision_snapshot.has("poly_index"):
			if not is_finite(collision_radius_px) or collision_radius_px < 0.0:
				return true
			return Runtime.actor_world(_editor_runtime_collision_snapshot,center_world_px,
				Spatial.actor_footprint_polygon_px(maxf(0.0,collision_radius_px)))
		return super.is_environment_actor_blocked(center_world_px,collision_radius_px)

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	checks += 1
	failures += 0 if ok else 1
	proof.record(ok,label)

func _time(provider: Node,queries: Array,repeats: int) -> Dictionary:
	var count := 0
	var started := Time.get_ticks_usec()
	for repeat in range(repeats):
		for row: Dictionary in queries:
			if provider.is_environment_actor_blocked(row.center_px,row.radius_px):
				count += 1
	return {"usec":Time.get_ticks_usec()-started,"queries":queries.size()*repeats,"blocked":count}

func _run() -> void:
	var reports: Array[Dictionary] = []
	for label: String in ["P2_INPUT_30_FIXED","P2_INPUT_40"]:
		var path := "res://outputs/collision_prepare_next_v113_20261013/"+label+".bin"
		_check(FileAccess.file_exists(path),"original input corpus exists "+label)
		if not FileAccess.file_exists(path): continue
		var corpus: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(path))
		var replay := Replay.new()
		replay.prepare_snapshots([corpus.snapshot])
		var snapshot := {"design_size":corpus.snapshot.design_size,"poly_index":replay.indexes[0]}
		var control := BaselineBackground.new()
		var candidate := Background.new()
		control._editor_runtime_collision_snapshot = snapshot
		candidate._editor_runtime_collision_snapshot = snapshot
		var queries: Array = corpus.queries
		var radius_counts := {}
		for row: Dictionary in queries:
			var old_result: bool = control.is_environment_actor_blocked(row.center_px,row.radius_px)
			var new_result: bool = candidate.is_environment_actor_blocked(row.center_px,row.radius_px)
			_check(old_result == row.blocked and new_result == old_result,"captured provider exact result "+label)
			radius_counts[str(row.radius_px)] = int(radius_counts.get(str(row.radius_px),0))+1
		var pairs: Array[Dictionary] = []
		for pair in range(8):
			var old_time: Dictionary
			var new_time: Dictionary
			if pair % 2 == 0:
				old_time = _time(control,queries,4)
				new_time = _time(candidate,queries,4)
			else:
				new_time = _time(candidate,queries,4)
				old_time = _time(control,queries,4)
			_check(old_time.queries == new_time.queries and old_time.blocked == new_time.blocked,"timed pair preserves completion/result counts")
			pairs.append({"pair":pair,"order":"AB" if pair%2==0 else "BA","control":old_time,"candidate":new_time})
		var cold_pairs: Array[Dictionary] = []
		for pair in range(4):
			candidate._actor_footprint_query = candidate.ActorFootprintQuery.new()
			cold_pairs.append({"control":_time(control,queries,1),"candidate":_time(candidate,queries,1)})
		var churn_queries: Array[Dictionary] = []
		for i in range(256):
			var row: Dictionary = queries[i%queries.size()]
			churn_queries.append({"center_px":row.center_px,"radius_px":8.0+float(i%8)})
		var churn_control := _time(control,churn_queries,8)
		var churn_candidate := _time(candidate,churn_queries,8)
		_check(churn_control.blocked == churn_candidate.blocked,"eviction workload collision parity")
		reports.append({"label":label,"original_query_count":queries.size(),"radius_counts":radius_counts,
			"corpus_sha256":FileAccess.get_sha256(path),"warm_pairs":pairs,"cold_pairs":cold_pairs,
			"eviction_stress":{"control":churn_control,"candidate":churn_candidate,"radii":8,"capacity":4},
			"cache_entries":candidate._actor_footprint_query._templates.size(),"scope":"PC provider replay; includes generator/lookup/metadata/transform/real Index; no live frame claim"})
		control.free()
		candidate.free()
	var result := {"reports":reports,"checks":checks,"failures":failures,
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"framework_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"framework_invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")}
	var file := FileAccess.open("res://outputs/collision_prepare_next_v113_20261013/P2_BENCHMARK.json",FileAccess.WRITE)
	_check(file != null,"benchmark report open")
	if file != null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	var ok := proof.write_receipt(SCENE_ID,checks,failures)
	print("FOOTPRINT_TEMPLATE_BENCHMARK_", "PASS" if failures==0 and ok else "FAIL", " checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 and ok else 1)
