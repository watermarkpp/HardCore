extends RefCounted

const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const MapEditorCoordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _entries: Dictionary
var _world_ref: WeakRef
var _world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(publication: Dictionary, world: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or world == null or world is Node or world is Resource or not world.has_method("owner_thread_id") or world.owner_thread_id() != _owner_thread or not world.has_method("fault"):
		push_error("Runtime map table requires S owner world")
		return false
	_world = world
	if str(publication.get("contract_id", "")) != "world.environment.publication.v1" or not publication.get("runtime_maps") is Dictionary:
		_world.fault("environment_publication_invalid", {"component": "runtime_maps"})
		return false
	var copied := Graph.copy_and_seal(publication.runtime_maps)
	if not copied.ok:
		_world.fault("environment_publication_live_value", {"errors": copied.errors})
		return false
	_entries = copied.value
	for map_id: Variant in _entries:
		var entry: Variant = _entries[map_id]
		if not map_id is int or not entry is Dictionary or not entry.get("formal_playable") is bool or not entry.get("has_runtime_map") is bool or not entry.get("runtime_path") is String or not entry.get("runtime") is Dictionary or not entry.get("world_has_map") is bool or not entry.get("world_content") is Dictionary:
			_world.fault("environment_runtime_entry_invalid", {"map_id": map_id})
			return false
	_configured = true
	return true

func _entry(map_id: int) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _entries.has(map_id):
		_world.fault("environment_map_not_published", {"map_id": map_id})
		return {}
	return _entries[map_id]

func require_map(map_id: int) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _entries.has(map_id):
		_world.fault("environment_map_not_published", {"map_id": map_id})
		return false
	return true

func is_formal_playable(map_id: int) -> bool:
	if _actual_original_pre_map_query(map_id): return false
	return bool(_entry(map_id).get("formal_playable", false))

func has_runtime_map(map_id: int) -> bool:
	if _actual_original_pre_map_query(map_id): return false
	return bool(_entry(map_id).get("has_runtime_map", false))

func runtime_path(map_id: int) -> String:
	return str(_entry(map_id).get("runtime_path", ""))

func load_map(map_id: int) -> Dictionary:
	if _actual_original_pre_map_query(map_id): return {}
	return _entry(map_id).get("runtime", {})

func _actual_original_pre_map_query(map_id: int) -> bool:
	# Original Bridge lookup returns no runtime before the first map exists.
	# This grants no geometry, table entry or permission to an unknown map.
	if not _configured or OS.get_thread_caller_id() != _owner_thread or map_id != -1 or not _world.has_method("current_world_identity"): return false
	var current: Dictionary = _world.current_world_identity()
	return current.get("contract_id") == "hardcore.execution.world_context.v1" and current.get("runtime_map_id") == -1 and current.get("world_epoch") == 0

func has_map(map_id: int) -> bool:
	return bool(_entry(map_id).get("world_has_map", false))

func map_content(map_id: int) -> Dictionary:
	return _entry(map_id).get("world_content", {}).duplicate(true)

func game_content_for_map(map_id: int) -> Dictionary:
	var entry: Dictionary = _entry(map_id)
	if not entry.get("runtime_game_content") is Dictionary:
		_world.fault("original_runtime_game_content_not_published", {"map_id":map_id})
		return {}
	# Original Bridge assembles a fresh mutable result for each caller.
	return entry.runtime_game_content.duplicate(true)

func portal_screen_position_px(map_id: int, portal_id: String, source_map_id := -1) -> Vector2:
	var runtime: Dictionary = load_map(map_id)
	if runtime.is_empty(): return Vector2.ZERO
	# This original helper consumes only the supplied immutable semantic map;
	# the Source side never invokes Bridge's Main-owned loader or registry.
	var found: Dictionary = Bridge._portal_ground_position_result(runtime,portal_id,source_map_id)
	if not bool(found.get("ok",false)): return Vector2.ZERO
	return ground_position_gu_to_screen_position_px(runtime,found.position_ground_gu)


func ground_position_gu_to_screen_position_px(
	runtime: Dictionary,
	ground_position_gu: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.ground_position_gu_to_screen_position_px(
		ground_position_gu,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


func grid_cell_to_screen_position_px(
	runtime: Dictionary,
	raw_cell: Array
) -> Vector2:
	return ground_position_gu_to_screen_position_px(
		runtime, cell_to_ground_position_gu(raw_cell)
	)


func screen_position_px_to_ground_position_gu(
	runtime: Dictionary,
	screen_position_px: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.screen_position_px_to_ground_position_gu(
		screen_position_px,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


func cell_to_ground_position_gu(raw_cell: Array) -> Vector2:
	return _array_to_vector2(raw_cell) + Vector2(0.5, 0.5)


func ground_polygon_gu_to_screen_polygon_px(
	runtime: Dictionary,
	raw_polygon_ground_gu: Array
) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for raw_point: Variant in raw_polygon_ground_gu:
		if raw_point is Array and raw_point.size() == 2:
			projected.append(ground_position_gu_to_screen_position_px(
				runtime, _array_to_vector2(raw_point)
			))
	return projected


func _array_to_vector2(raw: Array) -> Vector2:
	if raw.size() != 2:
		return Vector2.ZERO
	return Vector2(float(raw[0]), float(raw[1]))
