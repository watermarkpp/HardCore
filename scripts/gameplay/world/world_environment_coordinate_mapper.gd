extends RefCounted

var _owner_thread := OS.get_thread_caller_id()
var _configured := false

func owner_thread_id() -> int:
	return _owner_thread

func _valid_owner_port(port: Variant, methods: Array[String]) -> bool:
	if not port is Object or port is Node or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner_thread:
		return false
	for method: String in methods:
		if not port.has_method(method):
			return false
	return true

var _world_content: Object
func configure_owner(runtime_maps: Object, world_content: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or not _valid_owner_port(runtime_maps, ["require_map", "is_formal_playable", "has_runtime_map", "load_map", "screen_position_px_to_ground_position_gu", "ground_position_gu_to_screen_position_px"]) or not _valid_owner_port(world_content, ["has_map", "map_content"]):
		push_error("Coordinate mapper requires exact published runtime/world content")
		return false
	_runtime_maps = runtime_maps
	_world_content = world_content
	_configured = true
	return true


const GroundUnitSpaceScript = preload("res://scripts/ground_unit_space.gd")
var _runtime_maps: Object

## FREEZE-P0.2: formal map projection profile policies.
const PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE = (
	&"map_editor_runtime_absolute"
)
const PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE = (
	&"authored_source_absolute"
)
const PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE = (
	&"authored_centered_absolute"
)
const PROJECTION_POLICY_MAP_NOT_IMPLEMENTED = &"map_not_implemented"
const PROJECTION_POLICY_UNSUPPORTED = &"unsupported_map_projection"

# 经典客户端地砖采用64×32菱形；每个MAP逻辑格对应一个固定等距步长。
const CELL_HALF_WIDTH = 32.0
const CELL_HALF_HEIGHT = 16.0


## FREEZE-P0.2: single formal projection-profile resolver. Every playable map
## id resolves to one explicit map-global Ground GU projection:
##   A. MAP_EDITOR_RUNTIME_ABSOLUTE  (MapEditorRuntimeBridge runtime)
##   B. AUTHORED_SOURCE_ABSOLUTE     (WorldContent source_size)
##   C. AUTHORED_CENTERED_ABSOLUTE   (WorldContent centered authored map)
##   D. UNMAPPED_TEST_IDENTITY       (runtime_map_id < 0, explicit)
##   E. UNSUPPORTED                  (explicit failure; never guessed)
## FREEZE-P0.2R: formal production projection resolver. Only runtime-built maps
## (MapEditor runtime + ready marker) are formally playable; world/reference
## data never grants a formal profile.
func resolve_formal_runtime_projection_profile(
	map_id: int
) -> Dictionary:
	if map_id >= 0 and not _runtime_maps.require_map(map_id):
		return {"success": false, "reason": &"environment_map_not_published", "runtime_map_id": map_id,
			"policy": PROJECTION_POLICY_UNSUPPORTED, "source": "", "source_size": Vector2i.ZERO,
			"screen_to_ground": Callable(), "ground_to_screen": Callable()}
	if map_id < 0:
		return {
			"success": true,
			"reason": &"",
			"runtime_map_id": map_id,
			"policy": (
				GroundUnitSpaceScript.PROJECTION_POLICY_UNMAPPED_TEST_IDENTITY
			),
			"source": "unmapped_test_identity",
			"source_size": Vector2i.ZERO,
			"screen_to_ground": (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu
			),
			"ground_to_screen": (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px
			),
		}
	if _runtime_maps.is_formal_playable(map_id):
		var runtime = _runtime_maps.load_map(map_id)
		if not runtime.is_empty():
			var raw_size: Array = runtime.get(
				"design", {}
			).get("design_size", [256, 256])
			var design_size = Vector2i(
				int(raw_size[0]),
				int(raw_size[1])
			)
			return {
				"success": true,
				"reason": &"",
				"runtime_map_id": map_id,
				"policy": PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE,
				"source": "MapEditorRuntimeBridge",
				"source_size": design_size,
				"screen_to_ground": func(screen_position_px: Vector2) -> Vector2:
					return _runtime_maps.screen_position_px_to_ground_position_gu(
						runtime,
						screen_position_px
					),
				"ground_to_screen": func(ground_position_gu: Vector2) -> Vector2:
					return _runtime_maps.ground_position_gu_to_screen_position_px(
						runtime,
						ground_position_gu
					),
			}
	if _world_content != null and _world_content.has_map(map_id):
		return {
			"success": false,
			"reason": GroundUnitSpaceScript.REASON_MAP_NOT_IMPLEMENTED,
			"runtime_map_id": map_id,
			"policy": PROJECTION_POLICY_MAP_NOT_IMPLEMENTED,
			"source": "reference_only_not_runtime_built",
			"source_size": Vector2i.ZERO,
			"screen_to_ground": Callable(),
			"ground_to_screen": Callable(),
		}
	return {
		"success": false,
		"reason": GroundUnitSpaceScript.REASON_UNSUPPORTED_MAP_PROJECTION,
		"runtime_map_id": map_id,
		"policy": PROJECTION_POLICY_UNSUPPORTED,
		"source": "",
		"source_size": Vector2i.ZERO,
		"screen_to_ground": Callable(),
		"ground_to_screen": Callable(),
	}


## FREEZE-P0.2R: formal-only alias kept for existing callers. Never resolves a
## reference-only / planned-unbuilt map.
func resolve_map_projection_profile(map_id: int) -> Dictionary:
	return resolve_formal_runtime_projection_profile(map_id)


## FREEZE-P0.2R: reference/migration resolver. Keeps the legacy authored
## source-size / centered math for import audits, migration tools and
## test/dev preview. NEVER used by formal GameRoot/combat paths.
func resolve_reference_projection_profile(map_id: int) -> Dictionary:
	if map_id >= 0 and not _runtime_maps.require_map(map_id):
		return {"success": false, "reason": &"environment_map_not_published", "runtime_map_id": map_id,
			"policy": PROJECTION_POLICY_UNSUPPORTED, "source": "", "source_size": Vector2i.ZERO,
			"screen_to_ground": Callable(), "ground_to_screen": Callable()}
	if map_id < 0:
		return {
			"success": true,
			"reason": &"",
			"runtime_map_id": map_id,
			"policy": (
				GroundUnitSpaceScript.PROJECTION_POLICY_UNMAPPED_TEST_IDENTITY
			),
			"source": "unmapped_test_identity",
			"source_size": Vector2i.ZERO,
			"screen_to_ground": (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu
			),
			"ground_to_screen": (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px
			),
		}
	if _runtime_maps.has_runtime_map(map_id):
		var runtime = _runtime_maps.load_map(map_id)
		if not runtime.is_empty():
			var raw_size: Array = runtime.get(
				"design", {}
			).get("design_size", [256, 256])
			var design_size = Vector2i(
				int(raw_size[0]),
				int(raw_size[1])
			)
			return {
				"success": true,
				"reason": &"",
				"runtime_map_id": map_id,
				"policy": PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE,
				"source": "MapEditorRuntimeBridge",
				"source_size": design_size,
				"screen_to_ground": func(screen_position_px: Vector2) -> Vector2:
					return _runtime_maps.screen_position_px_to_ground_position_gu(
						runtime,
						screen_position_px
					),
				"ground_to_screen": func(ground_position_gu: Vector2) -> Vector2:
					return _runtime_maps.ground_position_gu_to_screen_position_px(
						runtime,
						ground_position_gu
					),
			}
	if _world_content != null and _world_content.has_map(map_id):
		var content = _world_content.map_content(map_id)
		var source_size: Variant = content.get(
			"source_size",
			Vector2i.ZERO
		)
		var source_size_vi = Vector2i.ZERO
		if source_size is Vector2:
			source_size_vi = Vector2i(source_size)
		elif source_size is Vector2i:
			source_size_vi = source_size
		if source_size_vi != Vector2i.ZERO:
			return {
				"success": true,
				"reason": &"",
				"runtime_map_id": map_id,
				"policy": PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE,
				"source": "WorldContent.source_size",
				"source_size": source_size_vi,
				"screen_to_ground": func(screen_position_px: Vector2) -> Vector2:
					return screen_position_px_to_ground_position_gu(
						screen_position_px,
						source_size_vi
					),
				"ground_to_screen": func(ground_position_gu: Vector2) -> Vector2:
					return ground_position_gu_to_screen_position_px(
						ground_position_gu,
						source_size_vi
					),
			}
		return {
			"success": true,
			"reason": &"",
			"runtime_map_id": map_id,
			"policy": PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE,
			"source": "WorldContent.centered",
			"source_size": Vector2i.ZERO,
			"screen_to_ground": (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu
			),
			"ground_to_screen": (
				GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px
			),
		}
	return {
		"success": false,
		"reason": GroundUnitSpaceScript.REASON_UNSUPPORTED_MAP_PROJECTION,
		"runtime_map_id": map_id,
		"policy": PROJECTION_POLICY_UNSUPPORTED,
		"source": "",
		"source_size": Vector2i.ZERO,
		"screen_to_ground": Callable(),
		"ground_to_screen": Callable(),
	}


func source_to_world(source_coordinate: Vector2, source_size: Vector2i) -> Vector2:
	return ground_position_gu_to_screen_position_px(
		source_coordinate, source_size
	)


func ground_position_gu_to_screen_position_px(
	ground_position_gu: Vector2,
	source_size: Vector2i
) -> Vector2:
	var center = (Vector2(source_size) - Vector2.ONE) * 0.5
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_position_gu - center
	)


func world_to_source(world_position: Vector2, source_size: Vector2i) -> Vector2:
	return screen_position_px_to_ground_position_gu(
		world_position, source_size
	)


func screen_position_px_to_ground_position_gu(
	screen_position_px: Vector2,
	source_size: Vector2i
) -> Vector2:
	var center = (Vector2(source_size) - Vector2.ONE) * 0.5
	return center + GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


func source_delta_to_world(source_delta: Vector2) -> Vector2:
	return ground_delta_gu_to_screen_delta_px(source_delta)


func ground_delta_gu_to_screen_delta_px(
	ground_delta_gu: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_delta_gu
	)


func world_delta_to_source(world_delta: Vector2) -> Vector2:
	return screen_delta_px_to_ground_delta_gu(world_delta)


func screen_delta_px_to_ground_delta_gu(
	screen_delta_px: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_delta_px
	)


func path_step_cost_gu(step: Vector2i) -> float:
	return GroundUnitSpaceScript.path_step_cost_gu(step)


func contains_source(source_coordinate: Vector2, source_size: Vector2i) -> bool:
	return source_coordinate.x >= 0.0 and source_coordinate.y >= 0.0 and source_coordinate.x < source_size.x and source_coordinate.y < source_size.y


func world_corners(source_size: Vector2i) -> PackedVector2Array:
	var maximum = Vector2(source_size - Vector2i.ONE)
	return PackedVector2Array([
		source_to_world(Vector2.ZERO, source_size),
		source_to_world(Vector2(maximum.x, 0), source_size),
		source_to_world(maximum, source_size),
		source_to_world(Vector2(0, maximum.y), source_size),
	])


func world_bounds(source_size: Vector2i) -> Rect2:
	var corners = world_corners(source_size)
	var minimum = corners[0]
	var maximum = corners[0]
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func compact_candidate_to_source(compact_position: Vector2, source_size: Vector2i, margin_ratio = 0.06) -> Vector2i:
	# 将旧样板[-650,650]×[-350,350]的位置展开到原MAP；仅用于缺MapInfo时的C级候选。
	var normalized = Vector2(
		clampf((compact_position.x + 650.0) / 1300.0, 0.0, 1.0),
		clampf((compact_position.y + 350.0) / 700.0, 0.0, 1.0),
	)
	var margin = Vector2(source_size) * margin_ratio
	var maximum = Vector2(source_size - Vector2i.ONE) - margin
	return Vector2i((margin + normalized * (maximum - margin)).round())
