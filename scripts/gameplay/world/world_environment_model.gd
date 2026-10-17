extends RefCounted

const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Mask := preload("res://scripts/gameplay/world/world_environment_mask_values.gd")
const SOURCE_COLLISION_RADIUS := 28
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _world_ref: WeakRef
var _world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null
var _catalog: Object
var _region_content: Object
var _mapper: Object
var _spatial: Object
var _collision: Object
var _runtime_maps: Object
var _diagnostics_ref: WeakRef
var _diagnostics: Object:
	get:
		return _diagnostics_ref.get_ref() if _diagnostics_ref != null else null
	set(value):
		_diagnostics_ref = weakref(value) if value != null else null
var _actor_footprint_query: Object
var zone_name := "比奇郊外"
var zone_data: Dictionary = {}
var _bich_collision_shapes: Array[Dictionary] = []
var _tomb_collision_shapes: Array[Dictionary] = []
var _source_collision_shape_count := 0
var _environment_collision_revision := 0
var _source_mask_image: RefCounted
var _source_mask_path := ""
var _source_clear_segments: Array = []
var _source_clear_cell_cache: Dictionary = {}
var _gothic_camp_layout: Dictionary = {}
var _editor_runtime_size := Vector2i.ZERO
var _editor_runtime_collision_snapshot: Dictionary = {}
var _editor_runtime_collision_invalid := false
var _pending_collision_descriptors: Array[Dictionary] = []
var _staged_generation := -1
var _gothic_collision_entries: Array = []
var _mask_publications: Dictionary = {}
var _source_body_ids: Array[int] = []
var _environment_body_ids: Array[int] = []
var _pending_arrival_position := Vector2.ZERO
var _focus_position := Vector2.ZERO
var _collision_focus_source := Vector2i(-99999,-99999)
var _pending_collision_focus := Vector2i.ZERO
var _collision_rebuild_pending := false
var _staged_build_complete := false

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(bindings: Dictionary, publication: Dictionary) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		return false
	var requirements := {
		"world": ["owner_thread_id", "fault", "environment_generation_token", "environment_generation_is_current", "set_environment_stage", "create_environment_static_body", "retire_environment_static_body", "ensure_gothic_environment_bodies"],
		"catalog": ["owner_thread_id", "get_map_profile", "get_theme", "resource_exists", "require_background_values"],
		"region_content": ["owner_thread_id", "get_map_content"],
		"mapper": ["owner_thread_id", "source_to_world", "world_to_source", "contains_source", "ground_position_gu_to_screen_position_px"],
		"spatial": ["owner_thread_id", "actor_footprint_offset_px"],
		"collision": ["owner_thread_id", "compile_runtime_collision", "compiled_collision_contains_world", "compiled_collision_contains_ground", "compiled_collision_blocked_cell_runs", "tile_polygon_world", "rect_polygon_world"],
		"runtime_maps": ["owner_thread_id", "has_runtime_map", "load_map", "runtime_path", "require_map"],
		"diagnostics": ["owner_thread_id", "increment_performance_counter", "timing_start", "timing_elapsed_usec", "record_performance_max"],
		"footprint": ["owner_thread_id", "blocked"],
	}
	for key: String in requirements:
		var port: Variant = bindings.get(key)
		if not port is Object or port is Node or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner_thread:
			push_error("Environment missing owner port: " + key)
			return false
		for method: String in requirements[key]:
			if not port.has_method(method):
				push_error("Environment missing required method: " + key + "." + method)
				return false
	_world = bindings.world
	_catalog = bindings.catalog
	_region_content = bindings.region_content
	_mapper = bindings.mapper
	_spatial = bindings.spatial
	_collision = bindings.collision
	_runtime_maps = bindings.runtime_maps
	_diagnostics = bindings.diagnostics
	_actor_footprint_query = bindings.footprint
	if not publication.get("background") is Dictionary or not publication.get("masks") is Dictionary or not publication.get("gothic_collision_entries") is Array:
		_world.fault("environment_background_publication_missing", {})
		return false
	var result := Graph.copy_and_seal(publication)
	if not result.ok:
		_world.fault("environment_publication_live_value", {"errors": result.errors})
		return false
	var p: Dictionary = result.value
	var state: Dictionary = p.background
	var required := {
		"zone_name": TYPE_STRING, "zone_data": TYPE_DICTIONARY,
		"bich_collision_shapes": TYPE_ARRAY, "tomb_collision_shapes": TYPE_ARRAY,
		"source_collision_shape_count": TYPE_INT, "collision_revision": TYPE_INT,
		"source_mask_path": TYPE_STRING, "source_mask_present": TYPE_BOOL,
		"source_clear_segments": TYPE_ARRAY, "source_clear_cell_cache": TYPE_DICTIONARY,
		"gothic_camp_layout": TYPE_DICTIONARY, "editor_runtime_size": TYPE_VECTOR2I,
		"editor_runtime_collision_invalid": TYPE_BOOL, "staged_generation": TYPE_INT,
	}
	for key: String in required:
		if not state.has(key) or typeof(state[key]) != required[key]:
			_world.fault("environment_background_field_invalid", {"field": key})
			return false
	zone_name = state.zone_name
	zone_data = state.zone_data
	# These are local mutable rebuild caches, never shared with the publication.
	var working := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd").restore_runtime_roots({"bich_collision_shapes": state.bich_collision_shapes, "tomb_collision_shapes": state.tomb_collision_shapes, "source_clear_segments": state.source_clear_segments, "source_clear_cell_cache": state.source_clear_cell_cache})
	if not working.ok:
		_world.fault("environment_working_container_restore_failed", working)
		return false
	_bich_collision_shapes = working.value.bich_collision_shapes
	_tomb_collision_shapes = working.value.tomb_collision_shapes
	_source_collision_shape_count = state.source_collision_shape_count
	_environment_collision_revision = state.collision_revision
	_source_mask_path = state.source_mask_path
	_source_clear_segments = working.value.source_clear_segments
	_source_clear_cell_cache = working.value.source_clear_cell_cache
	_gothic_camp_layout = state.gothic_camp_layout
	_editor_runtime_collision_invalid = state.editor_runtime_collision_invalid
	_staged_generation = state.staged_generation
	_gothic_collision_entries = p.gothic_collision_entries
	_mask_publications = p.masks
	if not _runtime_maps.require_map(_active_map_id()) or not _catalog.require_background_values(_active_map_id(), _presentation_map_id(_active_map_id())):
		return false
	if state.source_mask_present:
		if not _mask_publications.has(_source_mask_path):
			_world.fault("environment_mask_not_published", {"path": _source_mask_path})
			return false
		var mask := Mask.new()
		if not mask.configure_owner(_mask_publications[_source_mask_path]):
			_world.fault("environment_mask_publication_invalid", {"path": _source_mask_path})
			return false
		_source_mask_image = mask
	if state.editor_runtime_size != Vector2i.ZERO:
		var compiled: Dictionary = _collision.compile_runtime_collision(_runtime_maps.load_map(_active_map_id()), _active_map_id())
		if not compiled.get("ok", false) or compiled.snapshot.get("design_size") != state.editor_runtime_size:
			_world.fault("environment_published_collision_recompile_failed", {"errors": compiled.get("errors", [])})
			return false
		_editor_runtime_collision_snapshot = compiled.snapshot
		_editor_runtime_size = state.editor_runtime_size
	_configured = true
	return true

func _generation_token() -> int:
	return _world.environment_generation_token(_staged_generation)

func _generation_is_current() -> bool:
	return _world.environment_generation_is_current(_staged_generation)

func clear_original_map_environment(generation: int, map_id: int, data: Dictionary) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or generation < 0 or data.get("mapId") != map_id or not _world.environment_generation_is_current(generation): return false
	if not _world.native_bodies.retire_original_map_environment(): return false
	# Original WorldBackground.clear_environment numeric fields. Main owns the
	# corresponding canvases/textures; only S owns these collision/query caches.
	_environment_collision_revision += 1
	_source_body_ids.clear(); _environment_body_ids.clear()
	_bich_collision_shapes.clear(); _tomb_collision_shapes.clear()
	_source_collision_shape_count = 0
	_source_mask_image = null; _source_mask_path = ""
	_source_clear_segments.clear(); _source_clear_cell_cache.clear()
	_gothic_camp_layout = {}; _gothic_collision_entries = []
	_editor_runtime_size = Vector2i.ZERO; _editor_runtime_collision_snapshot = {}
	_editor_runtime_collision_invalid = false; _pending_collision_descriptors.clear()
	_collision_focus_source = Vector2i(-99999,-99999)
	_staged_generation = generation; _staged_build_complete = false
	zone_data = data.duplicate(true)
	zone_name = str(data.get("name",zone_name))
	return true

func set_original_pending_arrival_position(position_px: Vector2) -> void:
	if OS.get_thread_caller_id() != _owner_thread or not position_px.is_finite():
		_world.fault("invalid_original_pending_arrival_position",{}); return
	_pending_arrival_position = position_px

func _trace_original_gothic_rejection(reason: String, details: Dictionary) -> void:
	if bool(_world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace",false)):
		print("HC_SOURCE_GOTHIC_BUILD_REJECT ",JSON.stringify({"reason":reason,"details":details,"generation":_staged_generation,"usec":Time.get_ticks_usec()}))
func install_original_gothic_build_entries(entries: Array) -> bool:
	if OS.get_thread_caller_id() != _owner_thread:
		_trace_original_gothic_rejection("owner",{"owner":_owner_thread,"actual":OS.get_thread_caller_id()});return false
	if not _generation_is_current():
		_trace_original_gothic_rejection("environment_generation",{});return false
	if entries == _gothic_collision_entries: return true
	if not _gothic_collision_entries.is_empty():
		_trace_original_gothic_rejection("different_existing_entries",{"existing":_gothic_collision_entries.size(),"received":entries.size()});return false
	var copied: Dictionary = Graph.copy_and_seal(entries)
	if not copied.get("ok",false):
		_trace_original_gothic_rejection("graph_copy",{});return false
	if not _world.native_bodies.register_gothic_environment_bodies(copied.value,_staged_generation):
		_trace_original_gothic_rejection("native_registration",{"existing_ids":_world.native_bodies.get("_gothic_ids").size(),"received":entries.size()});return false
	_gothic_collision_entries = copied.value
	for id: int in _world.native_bodies.get("_gothic_ids"):
		_environment_body_ids.append(id)
	return true

func finish_original_map_build(generation: int, map_id: int) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or generation != _staged_generation or map_id != _active_map_id() or not _generation_is_current() or _editor_runtime_collision_invalid or _staged_build_complete: return false
	# Visual authored-wall completion is acknowledged separately by Main. This
	# is the original numeric revision/completion statement after collision work.
	_environment_collision_revision += 1
	_staged_build_complete = true
	return true

func set_original_focus_position(position_px: Vector2) -> void:
	if OS.get_thread_caller_id() != _owner_thread or not position_px.is_finite():
		_world.fault("invalid_original_focus_position",{}); return
	_focus_position = position_px
	if _source_mask_image == null: return
	var profile: Dictionary = environment_profile()
	if str(profile.get("coordinate_projection","")) != "isometric_64x32_full_size": return
	var source_size: Vector2i = profile.get("source_size",Vector2i.ZERO)
	var focus := Vector2i(_mapper.world_to_source(position_px,source_size).round())
	if _collision_focus_source.x > -90000 and maxi(abs(focus.x-_collision_focus_source.x),abs(focus.y-_collision_focus_source.y)) < 8: return
	_pending_collision_focus = focus
	if not _collision_rebuild_pending:
		_collision_rebuild_pending = true
		# Same original deferred coalescing. Native's installed S-local call queue
		# executes this on Source at the existing message-queue flush checkpoint.
		Callable(self,"_apply_original_pending_collision_rebuild").call_deferred()

func _apply_original_pending_collision_rebuild() -> void:
	_collision_rebuild_pending = false
	_collision_focus_source = _pending_collision_focus
	var profile: Dictionary = environment_profile()
	if str(profile.get("coordinate_projection","")) == "isometric_64x32_full_size":
		rebuild_source_collision_chunk(profile,_collision_focus_source)

## Owner-side replacement for Node/Shape construction; source kind selection,
## points, transforms, filter bits, registration order and query-cache writes match
## the original builders. canonical identity comes from the one WorldCore registry.
func build_one_collision(descriptor: Dictionary) -> Dictionary:
	if not _generation_is_current():
		return {"ok": true, "created": false, "cancelled": true}
	_world.set_environment_stage("BUILD_COLLISION")
	var kind := str(descriptor.get("kind", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	var shapes: Array[Dictionary] = []
	var transform := Transform2D.IDENTITY
	var metadata := {"source_kind": kind, "source_index": descriptor.get("source_index", -1), "generation": descriptor.get("generation", _staged_generation)}
	match kind:
		"polygon_convex":
			var polygon: Variant = payload.get("polygon", null)
			var size: Variant = payload.get("size", null)
			if not polygon is PackedVector2Array or polygon.size() < 3 or not size is Vector2i:
				return {"ok": true, "created": false}
			shapes.append(_shape(PhysicsServer2D.SHAPE_CONVEX_POLYGON, _collision.tile_polygon_world(polygon, size)))
			metadata["editor_runtime_collision_kind"] = "polygon_convex"
			_source_collision_shape_count += 1
		"boundary_side":
			shapes.append(_shape(PhysicsServer2D.SHAPE_CONVEX_POLYGON, PackedVector2Array([
				payload.get("outer", Vector2.ZERO), payload.get("outer_next", Vector2.ZERO),
				payload.get("inner_next", Vector2.ZERO), payload.get("inner", Vector2.ZERO)])))
			metadata["editor_runtime_boundary"] = true
			_source_collision_shape_count += 1
		"blocked_rect_run":
			var rect: Rect2i = payload.get("rect", Rect2i())
			var size: Vector2i = payload.get("size", Vector2i.ZERO)
			shapes.append(_shape(PhysicsServer2D.SHAPE_CONVEX_POLYGON, _collision.rect_polygon_world(
				[float(rect.position.x), float(rect.position.y), float(rect.size.x), float(rect.size.y)], size)))
			metadata["editor_runtime_blocked_run"] = true
			_source_collision_shape_count += 1
		"obstacle_circle", "obstacle_rect":
			var position: Vector2 = payload.get("position", Vector2.ZERO)
			var owner := str(payload.get("owner", "tomb"))
			transform.origin = position
			var query: Dictionary
			if kind == "obstacle_circle":
				var radius := float(payload.get("radius", 22.0))
				shapes.append(_shape(PhysicsServer2D.SHAPE_CIRCLE, radius))
				query = {"kind": "circle", "position": position, "radius": radius}
			else:
				var size: Vector2 = payload.get("size", Vector2(88, 34))
				shapes.append(_shape(PhysicsServer2D.SHAPE_RECTANGLE, size * 0.5))
				query = {"kind": "rect", "position": position, "size": size}
			if owner == "bich":
				_bich_collision_shapes.append(query)
			else:
				_tomb_collision_shapes.append(query)
		"boundary_segment":
			var start: Vector2 = payload.get("start", Vector2.ZERO)
			var finish: Vector2 = payload.get("finish", Vector2.ZERO)
			# PhysicsServer segment data is Rect2(a,b), NOT Rect2(a,b-a).
			shapes.append(_shape(PhysicsServer2D.SHAPE_SEGMENT, Rect2(start, finish)))
			var query := {"kind": "segment", "start": start, "finish": finish}
			if str(payload.get("owner", "tomb")) == "bich":
				_bich_collision_shapes.append(query)
			else:
				_tomb_collision_shapes.append(query)
		"source_mask_load":
			if not _load_source_collision_mask(payload.get("profile", {})):
				return {"ok": false, "created": false}
			metadata["source_mask_loaded"] = true
			if not _generation_is_current():
				return {"ok": true, "created": false, "cancelled": true}
		"gothic_camp_collisions":
			# Already-built camp geometry is published in original prop/sprite order.
			# The original entry returns the first existing body, or an empty marker.
			if not _gothic_collision_entries.is_empty():
				return _world.ensure_gothic_environment_bodies(_gothic_collision_entries, _staged_generation)
		_:
			_world.fault("environment_collision_kind_unsupported", {"kind": kind})
			return {"ok": false, "created": false}
	var result: Dictionary = _world.create_environment_static_body(transform, shapes, _spatial.WORLD_LAYER, 0, metadata)
	if not result.get("ok", false) or int(result.get("id", 0)) <= 0:
		_world.fault("environment_static_body_rejected", {"kind": kind})
		return {"ok": false, "created": false}
	_environment_body_ids.append(result.id)
	return result

func _shape(type: int, data: Variant) -> Dictionary:
	return {"type": type, "data": data, "transform": Transform2D.IDENTITY, "disabled": false,
		"one_way": false, "one_way_margin": 1.0, "one_way_direction": Vector2(0, 1)}

func _load_source_collision_mask(profile: Dictionary) -> bool:
	_source_mask_path = str(profile.get("collision_mask_path", ""))
	if _source_mask_path.is_empty() or not _catalog.resource_exists(_source_mask_path):
		return true
	# Main has already resolved ResourceLoader/texture/Image qualification.
	if not _mask_publications.has(_source_mask_path):
		_world.fault("environment_mask_not_published", {"path": _source_mask_path})
		return false
	var values: Dictionary = _mask_publications[_source_mask_path]
	if not bool(values.get("qualified", false)):
		return true
	var expected_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	if values.get("size") != expected_size:
		return true
	var mask := Mask.new()
	if not mask.configure_owner(values):
		_world.fault("environment_mask_publication_invalid", {"path": _source_mask_path})
		return false
	_source_mask_image = mask
	_build_source_clear_segments(profile)
	return true

func _clear_source_collision_nodes() -> bool:
	# Root retirement port enqueues the original queue_free-equivalent owner
	# lifecycle; it must NOT flush physics transforms or retire bodies early.
	for id: int in _source_body_ids:
		if not _world.retire_environment_static_body(id):
			_world.fault("environment_body_retirement_rejected", {"id": id})
			return false
	_source_body_ids.clear()
	_source_collision_shape_count = 0
	return true

func rebuild_full_source_collision(profile: Dictionary) -> bool:
	_environment_collision_revision += 1
	if not _clear_source_collision_nodes():
		return false
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var shapes: Array[Dictionary] = []
	for y in range(source_size.y):
		var x := 0
		while x < source_size.x:
			while x < source_size.x and not source_mask_cell_blocked(Vector2i(x, y), true):
				x += 1
			if x >= source_size.x:
				break
			var run_start := x
			while x + 1 < source_size.x and source_mask_cell_blocked(Vector2i(x + 1, y), true):
				x += 1
			_add_source_collision_run(shapes, run_start, x, y, source_size)
			x += 1
	return _publish_source_body(shapes, "source_collision_full_map")

func rebuild_source_collision_chunk(profile: Dictionary, focus_source: Vector2i) -> bool:
	var profile_started_usec: int = _diagnostics.timing_start()
	_environment_collision_revision += 1
	if not _clear_source_collision_nodes():
		return false
	if _source_mask_image == null:
		return true
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var minimum := Vector2i(maxi(0, focus_source.x - SOURCE_COLLISION_RADIUS), maxi(0, focus_source.y - SOURCE_COLLISION_RADIUS))
	var maximum := Vector2i(mini(source_size.x - 1, focus_source.x + SOURCE_COLLISION_RADIUS), mini(source_size.y - 1, focus_source.y + SOURCE_COLLISION_RADIUS))
	if minimum.x > maximum.x or minimum.y > maximum.y:
		return true
	var shapes: Array[Dictionary] = []
	for y in range(minimum.y, maximum.y + 1):
		var x := minimum.x
		while x <= maximum.x:
			while x <= maximum.x and not source_mask_cell_blocked(Vector2i(x, y), true):
				x += 1
			if x > maximum.x:
				break
			var run_start := x
			while x + 1 <= maximum.x and source_mask_cell_blocked(Vector2i(x + 1, y), true):
				x += 1
			_add_source_collision_run(shapes, run_start, x, y, source_size)
			x += 1
	if not _publish_source_body(shapes, "source_collision_chunk"):
		return false
	var elapsed_usec: int = _diagnostics.timing_elapsed_usec(profile_started_usec)
	if elapsed_usec > 0:
		_diagnostics.increment_performance_counter(&"source_collision_rebuild_runs")
		_diagnostics.record_performance_max(&"source_collision_rebuild_max_ms", float(elapsed_usec) / 1000.0)
	return true

func _add_source_collision_run(shapes: Array[Dictionary], start_x: int, end_x: int, y: int, source_size: Vector2i) -> void:
	var start: Vector2 = _mapper.source_to_world(Vector2(start_x, y), source_size)
	var finish: Vector2 = _mapper.source_to_world(Vector2(end_x, y), source_size)
	var points: PackedVector2Array
	if start_x == end_x:
		points = PackedVector2Array([start + Vector2(-32, 0), start + Vector2(0, -16), start + Vector2(32, 0), start + Vector2(0, 16)])
	else:
		points = PackedVector2Array([
			start + Vector2(-32, 0), start + Vector2(0, -16),
			finish + Vector2(0, -16), finish + Vector2(32, 0),
			finish + Vector2(0, 16), start + Vector2(0, 16),
		])
	shapes.append(_shape(PhysicsServer2D.SHAPE_CONVEX_POLYGON, points))
	_source_collision_shape_count += 1

func _publish_source_body(shapes: Array[Dictionary], tag: String) -> bool:
	if shapes.is_empty():
		return true
	var result: Dictionary = _world.create_environment_static_body(Transform2D.IDENTITY, shapes, _spatial.WORLD_LAYER, 0, {tag: true, "generation": _staged_generation})
	if not result.get("ok", false) or int(result.get("id", 0)) <= 0:
		_world.fault("environment_source_body_rejected", {"tag": tag})
		return false
	_source_body_ids.append(result.id)
	return true


func environment_profile() -> Dictionary:
	return _catalog.get_map_profile(
		_presentation_map_id(_active_map_id())
	)


func environment_theme_id() -> String:
	return str(environment_profile().get("theme", ""))


func environment_collision_count() -> int:
	return _bich_collision_shapes.size() + _tomb_collision_shapes.size()


## Monotonic revision for the formal environment collision authority. This is
## deliberately independent from bootstrap/generation tokens: a focus-window
## rebuild, map clear, or completed staged build must invalidate attack LOS
## results even when the surrounding bootstrap generation is unchanged.


func environment_collision_revision() -> int:
	return _environment_collision_revision


func source_collision_shape_count() -> int:
	return _source_collision_shape_count


func source_collision_mask_size() -> Vector2i:
	return _source_mask_image.get_size() if _source_mask_image != null else Vector2i.ZERO


func source_mask_cell_blocked(source_coordinate: Vector2i, apply_clearance = true) -> bool:
	if _source_mask_image == null or source_coordinate.x < 0 or source_coordinate.y < 0 or source_coordinate.x >= _source_mask_image.get_width() or source_coordinate.y >= _source_mask_image.get_height():
		return false
	if apply_clearance and (_source_clear_cell_cache.has(source_coordinate) or (_source_clear_cell_cache.is_empty() and _source_cell_is_cleared(source_coordinate, environment_profile()))):
		return false
	return _source_mask_image.get_pixel(source_coordinate.x, source_coordinate.y).r < 0.5


func is_environment_point_blocked(world_position: Vector2) -> bool:
	# Editor-authored maps already contain the complete boundary, blocked-tile and
	# manual-shape contract.  Falling through to every legacy map profile here
	# repeats expensive geometry work for each pursuing monster and can also mix
	# obsolete collision data into the current map.
	if _editor_runtime_size != Vector2i.ZERO:
		return _editor_runtime_blocks_world(world_position)
	if _editor_runtime_collision_invalid:
		return true
	return is_bich_point_blocked(world_position) or is_orc_tomb_point_blocked(world_position) or _source_mask_blocks_world(world_position)


## One deterministic environment query for an actor footprint.  Formal runtime
## collision uses the compiled integer-cell snapshot directly; legacy profiles
## retain the existing point provider semantics and sample order.


func is_environment_actor_blocked(
	center_world_px: Vector2,
	collision_radius_px: float
) -> bool:
	# HC-POLY-R2
	if _editor_runtime_collision_snapshot.has("poly_index"):
		if not is_finite(collision_radius_px) or collision_radius_px < 0.0:
			return true
		return _actor_footprint_query.blocked(
			_editor_runtime_collision_snapshot, center_world_px, collision_radius_px)
	if not center_world_px.is_finite():
		return true
	var sample_radius_px = maxf(0.0, collision_radius_px - 1.0)
	if _editor_runtime_size != Vector2i.ZERO:
		_diagnostics.increment_performance_counter(&"environment_point_samples")
		if _editor_runtime_blocks_world(center_world_px):
			return true
		if sample_radius_px <= 0.0:
			return false
		for index: int in range(_spatial.ACTOR_FOOTPRINT_SEGMENTS):
			var offset_px = _spatial.actor_footprint_offset_px(
				index,
				sample_radius_px,
			)
			_diagnostics.increment_performance_counter(&"environment_point_samples")
			if _editor_runtime_blocks_world(center_world_px + offset_px):
				return true
		return false
	if _editor_runtime_collision_invalid:
		return true
	_diagnostics.increment_performance_counter(&"environment_point_samples")
	if is_environment_point_blocked(center_world_px):
		return true
	if sample_radius_px <= 0.0:
		return false
	for index: int in range(_spatial.ACTOR_FOOTPRINT_SEGMENTS):
		var offset_px = _spatial.actor_footprint_offset_px(
			index,
			sample_radius_px,
		)
		_diagnostics.increment_performance_counter(&"environment_point_samples")
		if is_environment_point_blocked(center_world_px + offset_px):
			return true
	return false


## Ground-GU segment query with the legacy inclusive ceil sample contract.
## Formal maps use the precompiled snapshot and therefore perform no dynamic
## provider call per sample; profile maps retain the old point conversion.


func is_environment_segment_blocked_ground(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	step_gu = 0.25
) -> bool:
	# HC-POLY-R2
	if _editor_runtime_collision_snapshot.has("poly_index"):
		if not is_finite(step_gu) or step_gu <= 0.0:
			return true
		return _editor_runtime_collision_snapshot.poly_index.capsule_blocked(source_ground_gu, target_ground_gu, 0.0)
	if (
		not source_ground_gu.is_finite()
		or not target_ground_gu.is_finite()
		or not is_finite(float(step_gu))
		or float(step_gu) <= 0.0
	):
		return true
	var distance_gu = source_ground_gu.distance_to(target_ground_gu)
	if not is_finite(distance_gu):
		return true
	var sample_count = maxi(1, int(ceil(distance_gu / float(step_gu))))
	if _editor_runtime_collision_invalid:
		return true
	var legacy_source_size = Vector2i.ZERO
	if _editor_runtime_size == Vector2i.ZERO:
		var legacy_profile = environment_profile()
		var raw_source_size: Variant = legacy_profile.get("source_size", null)
		if not raw_source_size is Vector2i:
			return true
		legacy_source_size = raw_source_size
		if legacy_source_size.x <= 0 or legacy_source_size.y <= 0:
			return true
	for sample_index: int in range(sample_count + 1):
		var progress = float(sample_index) / float(sample_count)
		var sample_ground_gu = source_ground_gu.lerp(target_ground_gu, progress)
		var blocked = false
		if _editor_runtime_size != Vector2i.ZERO:
			_diagnostics.increment_performance_counter(&"environment_point_samples")
			blocked = _collision.compiled_collision_contains_ground(
				_editor_runtime_collision_snapshot,
				sample_ground_gu,
			)
		else:
			var sample_world_px = _mapper.ground_position_gu_to_screen_position_px(
				sample_ground_gu,
				legacy_source_size,
			)
			if not sample_world_px.is_finite():
				return true
			_diagnostics.increment_performance_counter(&"environment_point_samples")
			blocked = is_environment_point_blocked(sample_world_px)
		if blocked:
			return true
	return false


func is_bich_point_blocked(world_position: Vector2) -> bool:
	if uses_bich_art():
		var source_size: Vector2i = environment_profile().get("source_size", Vector2i.ZERO)
		if not _mapper.contains_source(_mapper.world_to_source(world_position, source_size), source_size):
			return true
	for entry: Dictionary in _bich_collision_shapes:
		if entry.kind == "circle" and world_position.distance_to(entry.position) <= float(entry.radius):
			return true
		if entry.kind == "rect":
			var half_size: Vector2 = entry.size * 0.5
			if Rect2(entry.position - half_size, entry.size).has_point(world_position):
				return true
	return false


func is_orc_tomb_point_blocked(world_position: Vector2) -> bool:
	var profile = environment_profile()
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
		if not _mapper.contains_source(_mapper.world_to_source(world_position, source_size), source_size):
			return true
	for entry: Dictionary in _tomb_collision_shapes:
		if entry.kind == "circle" and world_position.distance_to(entry.position) <= float(entry.radius):
			return true
		if entry.kind == "rect":
			var half_size: Vector2 = entry.size * 0.5
			if Rect2(entry.position - half_size, entry.size).has_point(world_position):
				return true
	return false


func uses_bich_art() -> bool:
	return (
		str(_active_theme().get("asset_set", "")) == "bich"
		and _presentation_map_id(_active_map_id()) == 4
	)


func uses_orc_tomb_art() -> bool:
	return _orc_tomb_map_id() in [217, 218, 221]


func bich_collision_count() -> int:
	return _bich_collision_shapes.size()


func orc_tomb_collision_count() -> int:
	return _tomb_collision_shapes.size()


func _editor_runtime_blocks_world(world_position: Vector2) -> bool:
	if _editor_runtime_collision_invalid:
		return true
	if _editor_runtime_collision_snapshot.is_empty():
		return true
	return _collision.compiled_collision_contains_world(
		_editor_runtime_collision_snapshot,
		world_position,
	)


func _source_mask_blocks_world(world_position: Vector2) -> bool:
	if _source_mask_image == null:
		return false
	var source_size: Vector2i = environment_profile().get("source_size", Vector2i.ZERO)
	var source = Vector2i(_mapper.world_to_source(world_position, source_size).round())
	return source_mask_cell_blocked(source, true)


func _source_cell_is_cleared(source_coordinate: Vector2i, profile: Dictionary) -> bool:
	if (
		_presentation_map_id(_active_map_id()) == 4
		and not _gothic_camp_layout.is_empty()
	):
		var camp_world = _mapper.source_to_world(Vector2(source_coordinate), profile.get("source_size", Vector2i.ZERO))
		if camp_world.distance_to(profile.get("runtime_home_position", Vector2.ZERO)) <= float(_gothic_camp_layout.get("safeRadius", 690.0)):
			return true
	var content = _region_content.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		var radius = 7.0 if group_name == "bosses" else (4.0 if group_name == "portals" else 2.5)
		for entry: Dictionary in content.get(group_name, []):
			if entry.has("source_coordinate") and Vector2(source_coordinate).distance_to(Vector2(entry.source_coordinate)) <= radius:
				return true
	var world_position = _mapper.source_to_world(Vector2(source_coordinate), profile.get("source_size", Vector2i.ZERO))
	var arena: Dictionary = profile.get("arena", {})
	if not arena.is_empty() and world_position.distance_to(arena.get("center", Vector2.ZERO)) <= float(arena.get("outer", 0.0)):
		return true
	var routes: Array = profile.get("routes", [])
	if str(profile.get("ground_style", "")) == "bich":
		var origin: Vector2 = profile.get("route_origin", Vector2.ZERO)
		for destination: Vector2 in routes:
			if _distance_to_segment(world_position, origin, destination) <= 58.0:
				return true
	else:
		for route: Variant in routes:
			if route is Array and route.size() >= 3 and _distance_to_segment(world_position, route[0], route[1]) <= float(route[2]):
				return true
	for segment: Array in _source_clear_segments:
		if _distance_to_segment(world_position, segment[0], segment[1]) <= float(segment[2]):
			return true
	return false


func _build_source_clear_segments(profile: Dictionary) -> void:
	_source_clear_segments.clear()
	var route_segments: Array = []
	var routes: Array = profile.get("routes", [])
	if str(profile.get("ground_style", "")) == "bich":
		var origin: Vector2 = profile.get("route_origin", Vector2.ZERO)
		for destination: Vector2 in routes:
			route_segments.append([origin, destination])
	else:
		for route: Variant in routes:
			if route is Array and route.size() >= 2:
				route_segments.append([route[0], route[1]])
	if route_segments.is_empty():
		route_segments.append([Vector2.ZERO, Vector2.ZERO])
	var content = _region_content.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs"]:
		for entry: Dictionary in content.get(group_name, []):
			var actor_position: Vector2 = entry.get("position", Vector2.ZERO)
			var nearest_point = Vector2.ZERO
			var nearest_distance = INF
			for route: Array in route_segments:
				var point = _closest_point_on_segment(actor_position, route[0], route[1])
				var distance = actor_position.distance_to(point)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_point = point
			if nearest_distance > 52.0:
				_source_clear_segments.append([actor_position, nearest_point, 96.0 if group_name == "bosses" else 44.0])


func _build_source_clear_cell_cache(profile: Dictionary) -> void:
	_source_clear_cell_cache.clear()
	var segments: Array = []
	var routes: Array = profile.get("routes", [])
	if str(profile.get("ground_style", "")) == "bich":
		var origin: Vector2 = profile.get("route_origin", Vector2.ZERO)
		for destination: Vector2 in routes:
			segments.append([origin, destination, 58.0])
	else:
		for route: Variant in routes:
			if route is Array and route.size() >= 3:
				segments.append([route[0], route[1], float(route[2])])
	segments.append_array(_source_clear_segments)
	for segment: Array in segments:
		_mark_clear_world_segment(segment[0], segment[1], float(segment[2]), profile)
	var content = _region_content.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			var radius = 112.0 if group_name == "bosses" else (64.0 if group_name == "portals" else 48.0)
			_mark_clear_world_circle(entry.get("position", Vector2.ZERO), radius, profile)
	var arena: Dictionary = profile.get("arena", {})
	if not arena.is_empty():
		_mark_clear_world_circle(arena.get("center", Vector2.ZERO), float(arena.get("outer", 0.0)), profile)


func _mark_clear_world_segment(start: Vector2, finish: Vector2, width: float, profile: Dictionary) -> void:
	var steps = maxi(1, ceili(start.distance_to(finish) / 16.0))
	for index in range(steps + 1):
		_mark_clear_world_circle(start.lerp(finish, float(index) / steps), width, profile)


func _mark_clear_world_circle(world_position: Vector2, radius: float, profile: Dictionary) -> void:
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var center = Vector2i(_mapper.world_to_source(world_position, source_size).round())
	var cell_radius = maxi(1, ceili(radius / 16.0))
	for y in range(center.y - cell_radius, center.y + cell_radius + 1):
		for x in range(center.x - cell_radius, center.x + cell_radius + 1):
			var cell = Vector2i(x, y)
			if _mapper.contains_source(Vector2(cell), source_size):
				_source_clear_cell_cache[cell] = true


func _closest_point_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> Vector2:
	var segment = finish - start
	if segment.length_squared() <= 0.001:
		return start
	var ratio = clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return start + segment * ratio


func _orc_tomb_map_id() -> int:
	var map_id = _presentation_map_id(int(zone_data.get("mapId", -1)))
	if map_id in [217, 218, 221]:
		return map_id
	match zone_name:
		"兽人古墓一层": return 217
		"兽人古墓二层": return 218
		"兽人古墓三层": return 221
	return -1


func _active_map_id() -> int:
	var map_id = int(zone_data.get("mapId", -1))
	if map_id > 0:
		return map_id
	if zone_name in ["比奇郊外", "比奇省"]:
		return 910001
	return _orc_tomb_map_id()


func _presentation_map_id(runtime_map_id: int) -> int:
	if runtime_map_id == int(zone_data.get("mapId", -1)):
		var legacy_id = int(zone_data.get("legacyRuntimeMapId", -1))
		if legacy_id > 0:
			return legacy_id
	return runtime_map_id


func _active_theme() -> Dictionary:
	return _catalog.get_theme(environment_theme_id())


func _active_asset_set() -> String:
	return str(environment_profile().get("asset_set", _active_theme().get("asset_set", "")))


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment = finish - start
	if segment.length_squared() == 0.0:
		return point.distance_to(start)
	var t = clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _map_id_from_data(map_data: Dictionary) -> int:
	var map_id = int(map_data.get("mapId", -1))
	if map_id > 0:
		return map_id
	return _active_map_id()


func _collision_descriptor(
	kind: String,
	source_index: int,
	payload: Dictionary,
	generation: int
) -> Dictionary:
	return {
		"kind": kind,
		"source_index": source_index,
		"collision_kind": kind,
		"payload": payload,
		"generation": generation,
	}


func _runtime_data_for(map_id: int) -> Dictionary:
	if not _runtime_maps.has_runtime_map(map_id):
		return {}
	return _runtime_maps.load_map(map_id)


func build_collision_descriptors(map_data: Dictionary) -> Array:
	# This public rebuild entry can be called independently of clear_environment()
	# by tests/tools. Invalidate the old authority before resolving the new map so
	# a missing or invalid replacement can never keep serving stale occupancy.
	_environment_collision_revision += 1
	_editor_runtime_collision_snapshot.clear()
	_editor_runtime_size = Vector2i.ZERO
	_editor_runtime_collision_invalid = false
	var map_id = _map_id_from_data(map_data)
	if not _runtime_maps.require_map(map_id):
		_editor_runtime_collision_invalid = true
		_pending_collision_descriptors.clear()
		return []
	var runtime = _runtime_data_for(map_id)
	var generation = _generation_token()
	var descriptors: Array[Dictionary] = []
	var formal_runtime_registered = not _runtime_maps.runtime_path(
		map_id
	).is_empty()
	if formal_runtime_registered:
		if runtime.is_empty():
			_editor_runtime_collision_invalid = true
		else:
			_append_editor_runtime_collision_descriptors(
				descriptors,
				runtime,
				generation,
				map_id,
			)
	elif not environment_profile().is_empty():
		_append_profile_collision_descriptors(descriptors, map_id, generation)
	_pending_collision_descriptors = descriptors
	return descriptors


func _append_editor_runtime_collision_descriptors(
	descriptors: Array,
	runtime: Dictionary,
	generation: int,
	expected_runtime_map_id: int,
) -> void:
	var compiled_result = _collision.compile_runtime_collision(
		runtime,
		expected_runtime_map_id,
	)
	if not bool(compiled_result.get("ok", false)):
		_editor_runtime_collision_invalid = true
		return
	var compiled_collision: Dictionary = compiled_result.get("snapshot", {})
	_editor_runtime_collision_snapshot = compiled_collision
	_editor_runtime_collision_invalid = false
	_editor_runtime_size = compiled_collision.get("design_size", Vector2i.ZERO)
	var inner: PackedVector2Array = compiled_collision.get(
		"boundary_world", PackedVector2Array()
	)
	var outer: PackedVector2Array = compiled_collision.get(
		"outer_boundary_world", PackedVector2Array()
	)
	for side in range(inner.size()):
		var next = (side + 1) % 4
		descriptors.append(_collision_descriptor(
			"boundary_side", side,
			{
				"outer": outer[side],
				"outer_next": outer[next],
				"inner": inner[side],
				"inner_next": inner[next],
				"side": side,
				"size": _editor_runtime_size,
			},
			generation
		))
	# HC-POLY-R2: boundary descriptors above remain unchanged.
	if compiled_collision.has("poly_index"):
		for polygon: PackedVector2Array in compiled_collision.poly_index.parts:
			descriptors.append(_collision_descriptor("polygon_convex", descriptors.size(),
				{"polygon": polygon, "size": _editor_runtime_size}, generation))
		return
	for rect: Rect2i in _collision.compiled_collision_blocked_cell_runs(
		compiled_collision
	):
		descriptors.append(_collision_descriptor(
			"blocked_rect_run", descriptors.size(),
			{"rect": rect, "size": _editor_runtime_size},
			generation
		))


func _append_profile_collision_descriptors(
	descriptors: Array,
	map_id: int,
	generation: int
) -> void:
	var profile = environment_profile()
	if profile.is_empty():
		return
	if (
		_presentation_map_id(map_id) == 4
		and bool(profile.get("gothic_camp_enabled", true))
	):
		descriptors.append(_collision_descriptor(
			"gothic_camp_collisions", 0, {}, generation
		))
		var corners: PackedVector2Array = profile.get(
			"world_corners", PackedVector2Array()
		)
		if corners.size() == 4:
			for side in range(4):
				descriptors.append(_collision_descriptor(
					"boundary_segment", 10 + side,
					{
						"start": corners[side],
						"finish": corners[(side + 1) % 4],
						"owner": "bich",
					},
					generation
				))
		return
	if _active_asset_set() == "bich":
		for index in profile.get("props", []).size():
			var prop_data: Dictionary = profile.get("props", [])[index]
			_append_obstacle_descriptor(
				descriptors, prop_data, index, "bich", generation
			)
		var corners: PackedVector2Array = profile.get(
			"world_corners", PackedVector2Array()
		)
		if corners.size() == 4:
			for side in range(4):
				descriptors.append(_collision_descriptor(
					"boundary_segment", 100 + side,
					{
						"start": corners[side],
						"finish": corners[(side + 1) % 4],
						"owner": "bich",
					},
					generation
				))
		return
	for index in profile.get("props", []).size():
		var prop_data: Dictionary = profile.get("props", [])[index]
		_append_obstacle_descriptor(
			descriptors, prop_data, index, "tomb", generation
		)
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		var corners: PackedVector2Array = profile.get(
			"world_corners", PackedVector2Array()
		)
		if corners.size() == 4:
			for side in range(4):
				descriptors.append(_collision_descriptor(
					"boundary_segment", 200 + side,
					{
						"start": corners[side],
						"finish": corners[(side + 1) % 4],
						"owner": "tomb",
					},
					generation
				))
	var mask_path = str(profile.get("collision_mask_path", ""))
	if map_id != 4 and not mask_path.is_empty() and _catalog.resource_exists(mask_path):
		descriptors.append(_collision_descriptor(
			"source_mask_load", 1000,
			{"profile": profile},
			generation
		))


func _append_obstacle_descriptor(
	descriptors: Array,
	prop_data: Dictionary,
	index: int,
	owner: String,
	generation: int
) -> void:
	var position: Vector2 = prop_data.get("position", Vector2.ZERO)
	var offset: Vector2 = prop_data.get("collision_offset", Vector2.ZERO)
	if owner == "tomb" and prop_data.get("collision_offset", null) == null:
		offset = Vector2(0, -8)
	var shape = str(prop_data.get("shape", ""))
	if shape == "circle":
		descriptors.append(_collision_descriptor(
			"obstacle_circle", index,
			{
				"position": position + offset,
				"radius": float(prop_data.get("radius", 22.0)),
				"owner": owner,
			},
			generation
		))
	elif shape == "rect":
		descriptors.append(_collision_descriptor(
			"obstacle_rect", index,
			{
				"position": position + offset,
				"size": prop_data.get("size", Vector2(88, 34)),
				"owner": owner,
			},
			generation
		))
