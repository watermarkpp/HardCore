extends Node
const Core := preload("res://tests/framework/helpers/multicore_pursuit_pool_core_20261014.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const OriginalCamera := preload("res://scripts/map_editor/map_diamond_camera_constraint_service.gd")
const CameraPublication := preload("res://scripts/gameplay/world/world_camera_constraint_publication.gd")
var proof := Proof.new()
var checks := 0
var failures := 0
var host: Object
var tick := 0
var closing := false
var deadline := 0
var reported := false

func check(value: bool, name: String) -> void:
	checks += 1; failures += 0 if value else 1; proof.record(value, name)

func _ready() -> void:
	var path := "res://assets/data/runtime/map_editor/bich_corpse_king_hall.runtime.json"
	var runtime: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var size := Vector2i(runtime.design.design_size[0], runtime.design.design_size[1])
	var index := Index.new()
	check(index.setup(size, runtime.collision.convex_parts_ground_gu), "actual published collision index setup")
	var profile: Dictionary = runtime.collision.navigation.profiles[0]
	for row: Dictionary in runtime.collision.navigation.profiles:
		if float(row.radius_gu) < float(profile.radius_gu): profile = row
	var graph := Graph.new()
	check(graph.setup(profile, size).ok, "actual published exact radius navigation setup")
	var values := {"valid":true,"kind":"polygon","design_size":size,"build_sha256":runtime.build_sha256,
		"index":{"parts":index.parts,"padded_boxes":index._padded_boxes,"first_buckets":index._first_buckets,"buckets":index.buckets},
		"graph":{"radius_key":graph.radius_key,"radius_gu":graph.radius_gu,"faces":graph.faces,"centers":graph.centers,"links":graph.links,"buckets":graph.buckets}}
	var navigation := {graph.radius_key:values}
	var predicates := {"contract_id":"hardcore.pursuit.frozen_static_hints.v1","ok":true,"source_sha256":FileAccess.get_sha256(path),
		"world_parts_ground_gu":index.parts,"safe_zone_polygons_ground_gu":[],"safe_zone_circles":[]}
	var expected: Array[Dictionary] = []
	for design: Vector2i in [Vector2i(32,32),Vector2i(200,200),Vector2i(600,600)]:
		for center: Vector2 in [Vector2.ZERO, Vector2(100,50), Vector2(12000,4000),Vector2(-40,-80)]:
			var half := Vector2(799,360)
			var zoom := Vector2(1.1,1.1)
			var extent := Vector3(32,64,16)
			expected.append({"design":design,"center":center,"half":half,"zoom":zoom,"extent":extent,
				"strict":OriginalCamera.resolve_strict_follow_cached(design,half,zoom,center),"guarded":OriginalCamera.apply_player_visibility_guard(design,half,zoom,center,extent)})
	var publication := CameraPublication.capture_original_main()
	check(not publication.is_empty(), "actual Main camera static cache captured")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":1,"runtime_map_id":int(runtime.source.runtime_map_id),"profile_id":"actual_pool_fixture"}
	host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,
		"bridge_generation":71,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),
		"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb"))*256,
		"primitive_request_capacity":65536,"primitive_result_capacity":65536,"live_primitive_capacity":4}
	deadline = Time.get_ticks_usec() + 8000000
	var runtime_graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var runtime_copy: Dictionary = runtime_graph.capture({Vector2i(3,4):[Vector2(1,2)]},true,false)
	var content_check: Dictionary = runtime_graph.validate({Vector2i(3,4):[]},true)
	check(runtime_copy.success and runtime_copy.value.has(Vector2i(3,4)) and not content_check.success, "runtime GU key admitted and original content key restriction retained")
	var started: bool = host.start_clock_fixture(Core,{"world_identity":world,"navigation":navigation,"predicates":predicates,"radius":graph.radius_gu,"radius_key":graph.radius_key,
		"camera_publication":publication,"camera_expected":expected},config)
	check(started, "actual Godot S owner and worker pool start")
	if not started:
		host = null
		proof.write_receipt("multicore_pursuit_pool_20261014",checks,failures)
		print("MULTICORE_PURSUIT_POOL_FAIL")
		get_tree().quit(1)

func _process(_delta: float) -> void:
	if host == null: return
	var presentation: Dictionary = host.acquire_presentation(tick+1,32)
	if not presentation.is_empty():
		tick = int(presentation.tick)
		host.ack_events(int(presentation.through_ordinal))
		var frame: Dictionary = presentation.frame
		if frame.done and not closing:
			check(frame.valid, "all real worker batches and exact camera results valid")
			check(frame.camera_valid and frame.camera_checks == 24, "camera same original formulas after owner migration")
			check(frame.rows_checked == 280 and frame.batches.size() == 8, "all 30/40 rows retained for direct and real A star paths")
			print("PURSUIT_ACTUAL_POOL_ROWS ",frame.batches)
			closing = true; host.request_close()
	if not reported and Time.get_ticks_usec() > deadline:
		reported = true; check(false,"component deadline; accepted Host retained")
		print("PURSUIT_ACTUAL_POOL_DEADLINE ",host.status())
		host.request_close()
	if closing and host.status().join_complete:
		check(host.close_and_join(), "accepted groups reclaimed and actual Host safely closed")
		host = null
		var written := proof.write_receipt("multicore_pursuit_pool_20261014",checks,failures)
		print("MULTICORE_PURSUIT_POOL_", "PASS" if written and failures == 0 else "FAIL")
		get_tree().quit(0 if written and failures == 0 else 1)
