extends Node
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Snapshot := preload("res://scripts/map_editor/polygon/poly_visual_snapshot.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Probe := preload("res://scripts/map_editor/polygon/poly_alignment_probe.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Search := preload("res://scripts/map_editor/polygon/poly_path_search.gd")
var errors: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_RELEASE_ALIGNMENT: " + message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var assets := {"fixture":{"asset_id":"fixture", "asset_type":"large_prop", "anchor_px":[64,128],"image":"res://fixture.png"}}
	var snapshot := {"contract_id":Snapshot.CONTRACT,"assets":assets,"sha256":MapEditorJsonCodec.encode(assets).sha256_text()}
	var runtime := {"precision_contract_id":Snapshot.PRECISION_CONTRACT,"visual_asset_snapshot":snapshot,"instances":[{"asset_id":"fixture"}]}
	check(Snapshot.validate(runtime).is_empty(), "matching published asset snapshot validates")
	check(Snapshot.resolve_asset("fixture",snapshot).anchor_px == [64,128], "published anchor used, not today's catalog")
	var damaged := runtime.duplicate(true)
	damaged.visual_asset_snapshot.assets.fixture.anchor_px[1] = 160
	check(not Snapshot.validate(damaged).is_empty(), "mixed or changed catalog geometry rejected by hash")
	damaged = runtime.duplicate(true)
	damaged.erase("visual_asset_snapshot")
	check(not Snapshot.validate(damaged).is_empty(), "R2 release cannot silently fall back to live catalog")
	check(Snapshot.validate({"instances":[]}).is_empty(), "old releases retain explicit compatibility")
	var radius := .3
	var profile := {"radius_gu":radius,"radius_key":Graph.key_for_radius(radius), "vertices_ground_gu":[[1,1],[11,1],[11,11],[1,1],[11,11],[1,11]],"faces":[[0,1,2],[3,4,5]]}
	var graph := Graph.new()
	check(graph.setup(profile,Vector2i(12,12)).ok, "duplicate equal vertex IDs accepted")
	check(graph.links.size() == 2 and graph.links[0].size() == 1 and graph.links[1].size() == 1, "exact equal vertices welded for connected face adjacency")
	var release := {"build_sha256":"a".repeat(64),"source":{"runtime_map_id":990999},"design":{"design_size":[12,12]},"collision":{
		"coordinate_contract_id":Geo.CONTRACT,"physics_source_id":Geo.PHYSICS_SOURCE,"ground_coordinate_contract_id":"isometric_cell_center_64x32_v2",
		"convex_parts_ground_gu":[],"blocked_count":0,"navigation":{"contract_id":"hc.polygon_nav_faces.v1","profiles":[profile]}}}
	Runtime.clear_loaded_cache()
	var verified := Runtime.compile(release,990999,true)
	check(verified.ok, "complete release collision validates")
	if verified.ok:
		check(not release.collision.is_read_only(), "generic validation does not freeze mutable editor/test input")
		Runtime.remember_validation(release,verified)
		Runtime.seal_loaded(release)
		check(release.collision.is_read_only(), "successful file-load boundary seals published collision")
		var again := Runtime.compile(release,990999,true)
		check(again.ok and is_same(again.snapshot.poly_index,verified.snapshot.poly_index), "loaded collision index reused without rebuilding")
		check(is_same(again.snapshot.poly_graphs,verified.snapshot.poly_graphs), "loaded navigation graphs reused")
		var context := Runtime.context(990999,release,"isometric_cell_center_64x32_v2","fixture")
		var task := Search.new()
		var calls := {"count":0}
		var builder: Callable = func() -> Dictionary: calls.count += 1; return {"goal":Vector2(10,10)}
		task.configure(context,Vector2(2,2),builder,radius)
		check(calls.count == 0, "configure does no synchronous endpoint preparation")
		check(task.advance(1,Time.get_ticks_usec()-1) == "SEARCHING" and calls.count == 0, "expired deadline defers goal preparation rather than terminating job")
		var guard := 0
		while task.state in ["PREPARING","SEARCHING"] and guard < 200:
			task.advance(1)
			guard += 1
		check(task.state == "FOUND" and calls.count == 1, "deadline-deferred job resumes and completes")
	var parent := Node2D.new()
	add_child(parent)
	var body := StaticBody2D.new()
	var shape_node := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	var expected := PackedVector2Array([Vector2(-20.3,10.1),Vector2(18.7,14.125),Vector2(3.3,30.2)])
	shape.points = expected
	shape_node.shape = shape
	body.set_meta("hc_polygon_expected_world",expected)
	body.add_child(shape_node)
	parent.add_child(body)
	check(Probe.actual_physics_report(parent).ok, "actual physics nodes match published world vertices")
	body.position.y = -16.0
	var shifted := Probe.actual_physics_report(parent)
	check(not shifted.ok and absf(shifted.max_actual_physics_vertex_error_px - 16.0) < .01, "probe catches injected northward 16px shift, not just formula equality")
	parent.queue_free()
	Runtime.clear_loaded_cache()
	await get_tree().process_frame
	if errors.is_empty(): print("HC_POLYGON_RELEASE_ALIGNMENT_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)
