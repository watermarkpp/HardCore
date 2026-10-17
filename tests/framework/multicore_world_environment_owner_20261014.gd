extends Node

## Direct original-algorithm helper comparison. This receipt cannot grant native
## physics ownership, lifecycle integration, loading, APK or device acceptance.
const OriginalSpatial := preload("res://scripts/world_spatial_rules.gd")
const OriginalMapper := preload("res://scripts/map_coordinate_mapper.gd")
const OriginalCollision := preload("res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd")
const OriginalBackground := preload("res://scripts/world_background.gd")
const OriginalCatalog := preload("res://scripts/environment_catalog.gd")
const Spatial := preload("res://scripts/gameplay/world/world_environment_spatial_rules.gd")
const Mapper := preload("res://scripts/gameplay/world/world_environment_coordinate_mapper.gd")
const Collision := preload("res://scripts/gameplay/world/world_environment_collision_geometry.gd")
const Background := preload("res://scripts/gameplay/world/world_environment_model.gd")
const Maps := preload("res://scripts/gameplay/world/world_environment_runtime_maps.gd")
const Catalog := preload("res://scripts/gameplay/world/world_environment_catalog.gd")
const Footprint := preload("res://scripts/gameplay/world/world_environment_footprint_query.gd")
const Mask := preload("res://scripts/gameplay/world/world_environment_mask_values.gd")
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Polygon := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_runtime.gd")

class HelperHost:
	extends RefCounted
	var faults: Array[Dictionary] = []
	var bodies: Array[Dictionary] = []
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func fault(code: String, details: Dictionary) -> void: faults.append({"code": code, "details": details})
	func environment_generation_token(staged: int) -> int: return staged
	func environment_generation_is_current(_staged: int) -> bool: return true
	func set_environment_stage(_stage: String) -> void: pass
	func create_environment_static_body(transform: Transform2D, shapes: Array[Dictionary], layer: int, mask: int, metadata: Dictionary) -> Dictionary:
		bodies.append({"transform": transform, "shapes": shapes, "layer": layer, "mask": mask, "metadata": metadata})
		return {"ok": true, "created": true, "id": bodies.size()}
	func retire_environment_static_body(_id: int) -> bool: return true
	func ensure_gothic_environment_bodies(_entries: Array, _generation: int) -> Dictionary: return {"ok": false}
	func timing_start() -> int: return 0
	func timing_elapsed_usec(_start: int) -> int: return 0
	func increment_performance_counter(_name: StringName) -> void: pass
	func record_timing_usec(_name: StringName, _start: int) -> void: pass
	func record_performance_max(_name: StringName, _value: float) -> void: pass

class HelperActorAccess:
	extends RefCounted
	func owner_thread_id() -> int: return OS.get_thread_caller_id()

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var _checks: Array[Dictionary] = []
func _check(name: String, value: bool) -> void:
	proof.record(value, name)
	_checks.append({"name": name, "status": "PASS" if value else "FAIL"})

func _ready() -> void:
	var host: RefCounted = HelperHost.new()
	var spatial: RefCounted = Spatial.new()
	_check("spatial_owner_configure", spatial.configure_owner(host))
	var map_id := 910777
	# The real WorldBackground constructor publishes typed collision arrays;
	# preserve their constructor types through the existing value codec.
	var bich_shapes: Array[Dictionary] = []
	var tomb_shapes: Array[Dictionary] = []
	var publication := {"contract_id": "world.environment.publication.v1", "map_load_order": [map_id],
		"runtime_maps": {map_id: {"formal_playable": false, "has_runtime_map": false, "runtime_path": "", "runtime": {}, "world_has_map": false, "world_content": {}}},
		"profiles": {4: OriginalCatalog.get_map_profile(4)},
		"themes": {}, "resource_exists": {}, "region_content": {map_id: RegionContent.get_map_content(map_id)},
		"masks": {}, "gothic_collision_entries": [],
		"background": {"zone_name": "比奇省", "zone_data": {"mapId": map_id, "legacyRuntimeMapId": 4},
			"bich_collision_shapes": bich_shapes, "tomb_collision_shapes": tomb_shapes, "source_collision_shape_count": 0,
			"collision_revision": 0, "source_mask_path": "", "source_mask_present": false,
			"source_clear_segments": [], "source_clear_cell_cache": {}, "gothic_camp_layout": {},
			"editor_runtime_size": Vector2i.ZERO, "editor_runtime_collision_invalid": false, "staged_generation": -1}}
	var theme := str(publication.profiles[4].get("theme", ""))
	publication.themes[theme] = OriginalCatalog.get_theme(theme)
	var mask_path := str(publication.profiles[4].get("collision_mask_path", ""))
	if not mask_path.is_empty():
		publication.resource_exists[mask_path] = ResourceLoader.exists(mask_path)
	var maps: RefCounted = Maps.new()
	_check("map_values_configure", maps.configure_owner(publication, host))
	var mapper: RefCounted = Mapper.new()
	_check("mapper_owner_configure", mapper.configure_owner(maps, maps))
	var polygon: RefCounted = Polygon.new()
	var actor_access: RefCounted = HelperActorAccess.new()
	_check("shared_polygon_configure", polygon.configure_owner({}, actor_access))
	var collision: RefCounted = Collision.new()
	_check("collision_owner_configure", collision.configure_owner(polygon, spatial))
	var catalog: RefCounted = Catalog.new()
	_check("catalog_owner_configure", catalog.configure_owner(publication, host))
	var footprint: RefCounted = Footprint.new()
	_check("footprint_owner_configure", footprint.configure_owner(spatial))
	var background: RefCounted = Background.new()
	_check("background_owner_configure", background.configure_owner({"world": host, "catalog": catalog, "region_content": catalog,
		"mapper": mapper, "spatial": spatial, "collision": collision, "runtime_maps": maps, "diagnostics": host, "footprint": footprint}, publication))
	var original: Node = OriginalBackground.new()
	original.zone_name = "比奇省"
	original.zone_data = publication.background.zone_data
	var sizes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(13, 9), Vector2i(700, 700)]
	var points: Array[Vector2] = [Vector2.ZERO, Vector2(0.5, 0.5), Vector2(-0.125, 16.5), Vector2(8.375, -0.5), Vector2(699, 699)]
	for size: Vector2i in sizes:
		for point: Vector2 in points:
			_check("projection_source_%d" % _checks.size(), mapper.source_to_world(point, size) == OriginalMapper.source_to_world(point, size))
			_check("projection_world_%d" % _checks.size(), mapper.world_to_source(point, size) == OriginalMapper.world_to_source(point, size))
			_check("projection_bounds_%d" % _checks.size(), mapper.contains_source(point, size) == OriginalMapper.contains_source(point, size))
	for radius: float in [0.0, 0.01, 3.75, 18.0, 31.125]:
		_check("footprint_ellipse_%d" % _checks.size(), spatial.actor_footprint_polygon_px(radius) == OriginalSpatial.actor_footprint_polygon_px(radius))
		_check("footprint_ground_%d" % _checks.size(), spatial.actor_footprint_ground_polygon_gu(radius, 16) == OriginalSpatial.actor_footprint_ground_polygon_gu(radius, 16))
		for index: int in range(-2, 19):
			_check("footprint_offset_%d" % _checks.size(), spatial.actor_footprint_offset_px(index, radius) == OriginalSpatial.actor_footprint_offset_px(index, radius))
	var runtime := {"build_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "runtime_map_id": map_id,
		"source": {"runtime_map_id": map_id}, "design": {"design_size": [13, 9]},
		"collision": {"coordinate_contract_id": OriginalCollision.CONTRACT_ID, "physics_source_id": OriginalCollision.PHYSICS_SOURCE_ID,
			"blocked_tiles": ["1,2", "2,2", "12,8"], "blocked_count": 3}}
	var old_compiled: Dictionary = OriginalCollision.compile_runtime_collision(runtime, map_id)
	var new_compiled: Dictionary = collision.compile_runtime_collision(runtime, map_id)
	_check("compiled_grid_exact", old_compiled == new_compiled)
	if old_compiled.get("ok", false) and new_compiled.get("ok", false):
		_check("blocked_cell_runs_exact", OriginalCollision.compiled_collision_blocked_cell_runs(old_compiled.snapshot) == collision.compiled_collision_blocked_cell_runs(new_compiled.snapshot))
		original._editor_runtime_collision_snapshot = old_compiled.snapshot
		original._editor_runtime_size = Vector2i(13, 9)
		background._editor_runtime_collision_snapshot = new_compiled.snapshot
		background._editor_runtime_size = Vector2i(13, 9)
		for x: int in range(-1, 15):
			for y: int in range(-1, 11):
				var point := Vector2(float(x) + 0.5, float(y) + 0.5)
				var world: Vector2 = mapper.source_to_world(point, Vector2i(13, 9))
				_check("environment_point_%d" % _checks.size(), background.is_environment_point_blocked(world) == original.is_environment_point_blocked(world))
				_check("environment_actor_%d" % _checks.size(), background.is_environment_actor_blocked(world, 18.0) == original.is_environment_actor_blocked(world, 18.0))
		for a: Vector2 in points:
			for b: Vector2 in points:
				_check("environment_segment_%d" % _checks.size(), background.is_environment_segment_blocked_ground(a, b, 0.25) == original.is_environment_segment_blocked_ground(a, b, 0.25))
		var old_descriptors: Array = []
		var new_descriptors: Array = []
		original._append_editor_runtime_collision_descriptors(old_descriptors, runtime, 51, map_id)
		background._append_editor_runtime_collision_descriptors(new_descriptors, runtime, 51, map_id)
		_check("formal_descriptor_original_order", old_descriptors == new_descriptors)
		for descriptor: Dictionary in old_descriptors:
			var body: CollisionObject2D = original.build_one_collision(descriptor)
			var translated: Dictionary = background.build_one_collision(descriptor)
			_check("native_shape_descriptor_created_%d" % _checks.size(), translated.get("ok", false) and translated.get("created", false) and body != null)
			if body != null and translated.get("created", false):
				var child: CollisionShape2D = body.get_child(0) as CollisionShape2D
				var old_shape: ConvexPolygonShape2D = child.shape as ConvexPolygonShape2D
				var captured: Dictionary = host.bodies[translated.id - 1]
				_check("native_shape_points_%d" % _checks.size(), captured.shapes[0].data == old_shape.points)
				_check("native_shape_transform_filters_%d" % _checks.size(), captured.transform == body.transform and captured.layer == body.collision_layer and captured.mask == body.collision_mask)
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	var components := PackedFloat32Array([0.0, 0.49999997, 0.5, 1.0])
	for y: int in range(2):
		for x: int in range(2):
			image.set_pixel(x, y, Color(components[y * 2 + x], 0.0, 0.0, 1.0))
	var mask: RefCounted = Mask.new()
	_check("mask_numeric_values_configure", mask.configure_owner({"size": Vector2i(2, 2), "red": components}))
	original._source_mask_image = image
	background._source_mask_image = mask
	original._source_clear_cell_cache = {Vector2i(1, 0): true}
	background._source_clear_cell_cache = {Vector2i(1, 0): true}
	for x: int in range(-1, 3):
		for y: int in range(-1, 3):
			for clearance: bool in [false, true]:
				_check("mask_red_threshold_and_clearance_%d" % _checks.size(), background.source_mask_cell_blocked(Vector2i(x, y), clearance) == original.source_mask_cell_blocked(Vector2i(x, y), clearance))
	var live_node := Node.new()
	_check("publication_rejects_live_node", not Graph.copy_and_seal({"node": live_node}).ok)
	live_node.free()
	_check("publication_rejects_callable", not Graph.copy_and_seal({"call": func(): return 1}).ok)
	var graph := Graph.copy_and_seal({Vector2i(1, 2): PackedFloat64Array([0.125, 0.5]), "point": Vector2(1.25, -0.5)})
	_check("local_math_dictionary_keys_and_precision", graph.ok and graph.value.is_read_only() and graph.value[Vector2i(1, 2)][0] == 0.125)
	var weak_host: WeakRef = weakref(host)
	original.free()
	# Keep providers alive while dropping their host: backlinks must not own it.
	host = null
	_check("host_backlinks_release", weak_host.get_ref() == null)
	var failures := 0
	for check: Dictionary in _checks:
		if check.status == "FAIL": failures += 1
	if not proof.write_receipt("multicore_world_environment_owner_20261014", _checks.size(), failures): failures += 1
	var result := {"status": "PASS" if failures == 0 else "FAIL", "failed": failures, "checks": _checks,
		"scope": "original geometry/projection/background queries and weak-backlink helpers only", "native": "NOT_RUN", "S_integration": "NOT_RUN"}
	var file := FileAccess.open("user://multicore_world_environment_owner_20261014.result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("WORLD_ENVIRONMENT_OWNER_RESULT ", JSON.stringify(result))
	if failures == 0: print("WORLD_ENVIRONMENT_OWNER_PASS")
	else: print("WORLD_ENVIRONMENT_OWNER_FAIL")
	get_tree().quit(0 if failures == 0 else 1)
