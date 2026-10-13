extends "res://tests/framework/crowd_compute_density_v113_20261013.gd"

## Instrumented original-input capture, never used as a performance result.
const Recorder := preload("res://tests/framework/helpers/static_polygon_query_recorder.gd")
var _input_queries: Array[Dictionary] = []
var _query_proxy: QueryProxy
var _snapshot_numeric: Dictionary = {}
var _environment_revision_before := 0

class CaptureProof extends "res://tests/framework/helpers/check_receipt.gd":
	func write_receipt(_scene_id: String,reported_checks: int,reported_failures: int) -> bool:
		return super.write_receipt("footprint_input_capture_v113_20261013",reported_checks,reported_failures)

func _init() -> void:
	_proof = CaptureProof.new()

class QueryProxy:
	extends Node
	var provider: Node
	var apparatus: Node
	func is_environment_actor_blocked(center: Vector2,radius: float) -> bool:
		var result: bool = provider.is_environment_actor_blocked(center,radius)
		if apparatus._sampling:
			apparatus._input_queries.append({"center_px":center,"radius_px":radius,
				"blocked":result,"tick":Engine.get_physics_frames()-apparatus._sample_start_physics_frame})
		return result
	func is_environment_point_blocked(point: Vector2) -> bool:
		return provider.is_environment_point_blocked(point)
	func is_environment_segment_blocked_ground(a: Vector2,b: Vector2,step := 0.25) -> bool:
		return provider.is_environment_segment_blocked_ground(a,b,step)
	func environment_collision_revision() -> int:
		return provider.environment_collision_revision()

func _ready_map_safe(expected_map: int) -> bool:
	var ready: bool = await super._ready_map_safe(expected_map)
	if ready and expected_map == MAP_ID and _query_proxy == null:
		_query_proxy = QueryProxy.new()
		_query_proxy.provider = _game.background
		_query_proxy.apparatus = self
		add_child(_query_proxy)
		var snapshot: Dictionary = _game.background._editor_runtime_collision_snapshot
		_snapshot_numeric = Recorder.numeric_snapshot(snapshot.poly_index)
		_environment_revision_before = _game.background.environment_collision_revision()
		for actor: EnemyActor in get_tree().get_nodes_in_group("enemies"):
			actor.environment_blocker = _query_proxy
		_game.player.environment_blocker = _query_proxy
	return ready

func _build_report(layout: Dictionary,enemies: Array,final_census: Dictionary,counters: Dictionary) -> Dictionary:
	var report: Dictionary = super._build_report(layout,enemies,final_census,counters)
	_check(not _input_queries.is_empty(),"original center/radius capture has actual provider calls")
	_check(_environment_revision_before == _game.background.environment_collision_revision(),"environment revision stable during capture")
	var current := Recorder.numeric_snapshot(_game.background._editor_runtime_collision_snapshot.poly_index)
	_check(var_to_bytes(current) == var_to_bytes(_snapshot_numeric),"complete numeric index unchanged during capture")
	var corpus := {"schema":"hardcore.footprint_producer_input.v1","snapshot":_snapshot_numeric,
		"queries":_input_queries,"layout":layout,"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"framework_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"framework_invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"fixture_sha256":FileAccess.get_sha256("res://tests/framework/footprint_input_capture_v113_20261013.gd"),
		"environment_revision":_environment_revision_before,"instrumented":true,"performance_claim":"NOT_RUN"}
	var bytes := var_to_bytes(corpus)
	var path := "res://outputs/collision_prepare_next_v113_20261013/" + _label + ".bin"
	var file := FileAccess.open(path,FileAccess.WRITE)
	_check(file != null,"producer corpus file opened")
	if file != null:
		file.store_buffer(bytes)
		file.close()
		_check(FileAccess.get_file_as_bytes(path) == bytes,"producer corpus exact binary roundtrip")
	report["producer_capture"] = {"path":path,"bytes":bytes.size(),"sha256":Recorder.bytes_sha256(bytes),
		"query_count":_input_queries.size(),"instrumented":true,"frame_benefit":"NOT_RUN"}
	return report
