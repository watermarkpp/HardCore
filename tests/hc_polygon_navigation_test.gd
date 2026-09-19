extends Node
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Build := preload("res://scripts/map_editor/polygon/poly_build.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Search := preload("res://scripts/map_editor/polygon/poly_path_search.gd")
const ExistingSearch := preload("res://scripts/monster_ai_package/path_search.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
var errors: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_NAVIGATION: " + message)

func _ready() -> void:
	call_deferred("run")

func fixture(polygons: Array, radii: Array) -> Dictionary:
	var entries: Array = []
	for polygon: Array in polygons:
		entries.append(Author.entry("test_%d" % entries.size(), Geo.decode(polygon)))
	var doc := {"design": {"design_size": [12, 12]}, "editor_meta": {"collision_authority": Geo.AUTHORITY}, "layers": {"collision": entries}}
	var prepared := Author.prepare(doc)
	check(prepared.ok, "fixture authoring valid")
	if not prepared.ok:
		return {}
	var index := Index.new()
	check(index.setup(Vector2i(12, 12), prepared.parts), "fixture index valid")
	var profiles: Array = []
	for radius: float in radii:
		var baked := Build._bake(Vector2i(12, 12), prepared.entries, index, radius, Graph.key_for_radius(radius))
		check(baked.ok, "actual engine navigation bake %s" % str(baked.get("errors", [])))
		if not baked.ok:
			return {}
		profiles.append(baked.record)
	var runtime := {"build_sha256": "a".repeat(64), "source": {"runtime_map_id": 990999},
		"design": {"design_size": [12, 12]}, "collision": {
			"coordinate_contract_id": Geo.CONTRACT, "physics_source_id": Geo.PHYSICS_SOURCE,
			"ground_coordinate_contract_id": "isometric_cell_center_64x32_v2", "convex_parts_ground_gu": prepared.parts,
			"blocked_tiles": [], "blocked_count": 0,
			"navigation": {"contract_id": "hc.polygon_nav_faces.v1", "profiles": profiles}}}
	## This hash is a synthetic snapshot identity, NOT a claim of valid published release checksum.
	var encoded := Codec.encode(runtime)
	var decoded := Codec.decode(encoded)
	return {"runtime": decoded, "context": Terrain.build_context(990999, decoded, "isometric_cell_center_64x32_v2")}

func search_path(context: Dictionary, start: Vector2, goal: Vector2, radius: float) -> Search:
	var task := Search.new()
	var builder: Callable = func() -> Dictionary: return {"end": goal}
	task.configure(context, start, builder, radius)
	var calls := 0
	while task.state in ["PREPARING", "SEARCHING"] and calls < 12000:
		var before := task.expansions
		task.advance(3)
		check(task.expansions - before <= 3, "per-advance node expansion bound")
		calls += 1
	check(calls < 12000, "resumable search terminates within bounded fixture graph")
	if task.state == "FOUND":
		var previous := start
		for point: Vector2 in task.path:
			check(Runtime.segment_walkable(context, previous, point, radius), "every returned segment clears full footprint")
			previous = point
		check(previous.distance_to(goal) <= 0.001, "continuous endpoint reaches requested goal")
	return task

func run() -> void:
	## Corridor spans y=4.05..4.75. Radius .30 fits at y=4.4, but no y=n+.5 center fits.
	var fixture_data := fixture([[[0,0],[12,0],[12,4.05],[0,4.05]], [[0,4.75],[12,4.75],[12,12],[0,12]]], [.30, .36])
	if not fixture_data.is_empty():
		var context: Dictionary = fixture_data.context
		check(Terrain.context_valid(context, 990999), "polygon context preserves actual coordinate_contract_id")
		check(not Terrain.context_valid(context, 990998), "foreign map context rejected")
		check(Terrain.point_walkable(context, Vector2(1,4.4), .30), "continuous narrow corridor valid")
		check(not Terrain.cell_walkable(context, Vector2i(1,4), .30), "old grid center genuinely not a route")
		check(not Terrain.point_walkable(context, Vector2(1,4.4), .36), "larger body cannot fit")
		var task := search_path(context, Vector2(1,4.4), Vector2(10,4.4), .30)
		check(task.state == "FOUND", "nav graph resolves corridor without a traversable old cell center")
		var wrapper := ExistingSearch.new()
		wrapper.set_polygon_origin(Vector2(1,4.4))
		var goal_builder: Callable = func() -> Dictionary: return {"end": Vector2(10,4.4)}
		wrapper.configure_deferred(context, Vector2i(1,4), goal_builder, .30, Callable())
		var guard := 0
		while wrapper.state in ["PREPARING", "SEARCHING"] and guard < 4000:
			wrapper.advance(8)
			guard += 1
		check(wrapper.state == "FOUND", "existing HC scheduler-compatible search delegates to continuous graph")
		var wrong_radius := Search.new()
		wrong_radius.configure(context, Vector2(1,4.4), goal_builder, .3001)
		check(wrong_radius.state == "UNSUPPORTED_POLYGON_RADIUS", "never round radius down to smaller nav profile")
		var foreign: Dictionary = fixture_data.runtime.duplicate(true)
		foreign.collision.physics_source_id = "wrong"
		check(not Runtime.compile(foreign, 990999, true).ok, "malformed new contract rejected")
		foreign = fixture_data.runtime.duplicate(true)
		foreign.collision.navigation.profiles[0].radius_key = "0".repeat(16)
		check(not Runtime.compile(foreign, 990999, true).ok, "mismatched radius bytes rejected")
	var detour := fixture([[[5,0],[5.08,0],[5.08,8],[5,8]]], [.30])
	if not detour.is_empty():
		check(not Runtime.segment_walkable(detour.context, Vector2(2,4), Vector2(9,4), .30), "direct route blocked by thin wall")
		check(search_path(detour.context, Vector2(2,4), Vector2(9,4), .30).state == "FOUND", "continuous graph detours around wall end")
	var disconnected := fixture([[[5,0],[5.08,0],[5.08,12],[5,12]]], [.30])
	if not disconnected.is_empty():
		check(search_path(disconnected.context, Vector2(2,4), Vector2(9,4), .30).state == "NO_ROUTE_FOR_CURRENT_GRAPH", "disconnected components do not tunnel")
	if errors.is_empty():
		print("HC_POLYGON_NAVIGATION_TEST_PASS checks=", checks)
	get_tree().quit(0 if errors.is_empty() else 1)
