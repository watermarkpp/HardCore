extends RefCounted

const Maps := preload("res://scripts/gameplay/world/world_environment_runtime_maps.gd")
const Catalog := preload("res://scripts/gameplay/world/world_environment_catalog.gd")
const Mapper := preload("res://scripts/gameplay/world/world_environment_coordinate_mapper.gd")
const Spatial := preload("res://scripts/gameplay/world/world_environment_spatial_rules.gd")
const Collision := preload("res://scripts/gameplay/world/world_environment_collision_geometry.gd")
const Footprint := preload("res://scripts/gameplay/world/world_environment_footprint_query.gd")
const EnvironmentModel := preload("res://scripts/gameplay/world/world_environment_model.gd")
const GeometryPort := preload("res://scripts/gameplay/world/world_environment_geometry_port.gd")
const PolyGeo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")

var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var runtime_maps: RefCounted
var catalog: RefCounted
var coordinate_mapper: RefCounted
var spatial_rules: RefCounted
var collision_geometry: RefCounted
var footprint_query: RefCounted
var environment: RefCounted
var geometry_port: RefCounted
var polygon: Object
var terrain_navigation: Object
var _world_ref: WeakRef

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(bindings: Dictionary, publication: Dictionary) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		return false
	var requirements := {
		"world": ["fault"],
		"diagnostics": ["timing_start", "timing_elapsed_usec", "record_timing_usec", "increment_performance_counter", "record_performance_max"],
		"polygon": ["compile", "remember_validation", "seal_loaded"],
		"terrain_navigation": ["build_context", "context_valid", "point_walkable", "static_line_of_sight_clear", "find_bounded_path"],
	}
	for key: String in requirements:
		var port: Variant = bindings.get(key)
		if not port is Object or port is Node or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner_thread:
			push_error("Environment factory requires owner service: " + key)
			return false
		for method: String in requirements[key]:
			if not port.has_method(method):
				push_error("Environment factory requires service method: " + key + "." + method)
				return false
	var world: Object = bindings.world
	_world_ref = weakref(world)
	polygon = bindings.polygon
	terrain_navigation = bindings.terrain_navigation
	if polygon.get("_configured") != true or terrain_navigation.get("_configured") != true or not is_same(terrain_navigation.get("deps").get("HCPPolyRuntime"), polygon):
		world.fault("environment_polygon_terrain_instance_mismatch", {})
		return false
	runtime_maps = Maps.new()
	if not runtime_maps.configure_owner(publication, world):
		return false
	if not publication.get("map_load_order") is Array:
		world.fault("environment_map_load_order_missing", {})
		return false
	# Original MapService.validate(include_navigation=true) and successful
	# Bridge.load_map seal boundary. Do not seal a false/empty-graphs snapshot.
	for id: int in publication.map_load_order:
		if not runtime_maps.has_runtime_map(id):
			continue
		var runtime: Dictionary = runtime_maps.load_map(id)
		if runtime.is_empty() or not PolyGeo.runtime_enabled(runtime):
			continue
		var compiled: Dictionary = polygon.compile(runtime, -1, true)
		if not bool(compiled.get("ok", false)):
			world.fault("environment_polygon_recompile_rejected", {"map_id": id, "errors": compiled.get("errors", [])})
			return false
		polygon.remember_validation(runtime, compiled)
		polygon.seal_loaded(runtime)
	catalog = Catalog.new()
	if not catalog.configure_owner(publication, world):
		return false
	coordinate_mapper = Mapper.new()
	if not coordinate_mapper.configure_owner(runtime_maps, runtime_maps):
		return false
	spatial_rules = Spatial.new()
	if not spatial_rules.configure_owner(bindings.diagnostics):
		return false
	collision_geometry = Collision.new()
	if not collision_geometry.configure_owner(polygon, spatial_rules):
		return false
	footprint_query = Footprint.new()
	if not footprint_query.configure_owner(spatial_rules):
		return false
	environment = EnvironmentModel.new()
	if not environment.configure_owner({"world": world, "catalog": catalog, "region_content": catalog,
		"mapper": coordinate_mapper, "spatial": spatial_rules, "collision": collision_geometry,
		"runtime_maps": runtime_maps, "diagnostics": bindings.diagnostics, "footprint": footprint_query}, publication):
		return false
	geometry_port = GeometryPort.new()
	if not geometry_port.configure_owner(world, environment, spatial_rules, coordinate_mapper, runtime_maps):
		return false
	_configured = true
	return true

func adopt_original_loading_publication(publication: Dictionary, receipt: Dictionary, transport: RefCounted) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or _world_ref == null or _world_ref.get_ref() == null: return false
	var world: RefCounted = _world_ref.get_ref()
	if transport == null or transport.get_script() != preload("res://scripts/gameplay/world/world_map_loading_transport.gd") or transport.get("_world") != world or not transport.verify_actual_map_publication(publication,receipt): return false
	var scope: Dictionary = transport.get("_scope")
	if publication.get("contract_id") != "world.environment.publication.v1" or not publication.get("background") is Dictionary or publication.background.get("zone_data",{}).get("mapId") != scope.get("map_id") or publication.background.get("staged_generation") != scope.get("coordinator_generation"): return false
	if not publication.get("masks") is Dictionary or not publication.get("gothic_collision_entries") is Array or not publication.gothic_collision_entries.is_empty(): return false
	# Validate new immutable tables without replacing any service referenced by
	# active geometry/path/skill owners. These candidates own no bodies or logic.
	var incoming_maps := Maps.new()
	var incoming_catalog := Catalog.new()
	if not incoming_maps.configure_owner(publication,world) or not incoming_catalog.configure_owner(publication,world): return false
	if not incoming_maps.require_map(int(scope.map_id)): return false
	var entries: Dictionary = runtime_maps.get("_entries").duplicate(false)
	entries.merge(incoming_maps.get("_entries"),true)
	var values: Dictionary = {}
	for table: String in ["profiles","themes","region_content","resource_exists"]:
		values[table] = catalog.get("_values")[table].duplicate(false)
		values[table].merge(incoming_catalog.get("_values")[table],true)
	var masks: Dictionary = environment.get("_mask_publications").duplicate(false)
	masks.merge(publication.masks,true)
	var captured: Dictionary = preload("res://scripts/gameplay/world/world_environment_value_graph.gd").copy_and_seal({"entries":entries,"values":values,"masks":masks})
	if not captured.get("ok",false): return false
	# Same original navigation compilation/seal, on the real S polygon owner.
	for id: int in publication.get("map_load_order",[]):
		if not incoming_maps.has_runtime_map(id): continue
		var runtime: Dictionary = incoming_maps.load_map(id)
		if runtime.is_empty() or not PolyGeo.runtime_enabled(runtime): continue
		var compiled: Dictionary = polygon.compile(runtime,-1,true)
		if compiled.get("ok") != true: world.fault("map_loading_polygon_recompile_rejected",{"map_id":id}); return false
		polygon.remember_validation(runtime,compiled)
		polygon.seal_loaded(runtime)
	runtime_maps.set("_entries",captured.value.entries)
	catalog.set("_values",captured.value.values)
	environment.set("_mask_publications",captured.value.masks)
	# Numerical collision state/revision remain S-owned after the original
	# clear. Main's pre-build cache is input evidence, never a second authority.
	return catalog.require_background_values(int(scope.map_id),environment._presentation_map_id(int(scope.map_id)))
