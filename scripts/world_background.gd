class_name WorldBackground
extends Node2D

const EnvironmentCatalogScript := preload("res://scripts/environment_catalog.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const EditorCoordinateScript := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const RuntimeCollisionGeometryScript := preload("res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd")
const RuntimeVisualGeometryScript := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
# P1-004: texture atlases are now lazy-loaded.  Only the target map's
# atlases are loaded when a map is built.  Old const names remain as
# compat aliases that delegate to _region_atlas().
const _REGION_ATLAS_PATHS := {
	"bich_ground": "res://assets/art/maps/bich/bich_ground_tiles.png",
	"gothic_bich_ground": "res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png",
	"bich_prop": "res://assets/art/maps/bich/bich_props.png",
	"orc_tomb_ground": "res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png",
	"orc_tomb_prop": "res://assets/art/maps/orc_tomb/orc_tomb_props.png",
	"orc_tomb_fire_glow": "res://assets/art/maps/orc_tomb/orc_tomb_fire_glow.png",
	"mine_ground": "res://assets/art/maps/mine/mine_ground_tiles.png",
	"mine_prop": "res://assets/art/maps/mine/mine_props.png",
	"mine_lamp_glow": "res://assets/art/maps/mine/mine_lamp_glow.png",
	"wooma_temple_ground": "res://assets/art/maps/wooma_temple/wooma_temple_ground_tiles.png",
	"wooma_temple_prop": "res://assets/art/maps/wooma_temple/wooma_temple_props.png",
	"wooma_temple_fire_glow": "res://assets/art/maps/wooma_temple/wooma_temple_fire_glow.png",
	"wooma_forest_ground": "res://assets/art/maps/wooma_region/wooma_forest_ground_tiles.png",
	"wooma_forest_prop": "res://assets/art/maps/wooma_region/wooma_forest_props.png",
	"wooma_cave_ground": "res://assets/art/maps/wooma_region/wooma_cave_ground_tiles.png",
	"wooma_cave_prop": "res://assets/art/maps/wooma_region/wooma_cave_props.png",
	"wooma_cave_glow": "res://assets/art/maps/wooma_region/wooma_cave_glow.png",
	"snake_valley_ground": "res://assets/art/maps/snake_valley/snake_valley_ground_tiles.png",
	"snake_valley_prop": "res://assets/art/maps/snake_valley/snake_valley_props.png",
	"snake_mine_glow": "res://assets/art/maps/snake_valley/snake_mine_glow.png",
}

var _atlas_cache: Dictionary = {}

func _region_atlas(key: String) -> Resource:
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var path: String = _REGION_ATLAS_PATHS.get(key, "")
	if path.is_empty():
		push_error("unknown region atlas key: %s" % key)
		return null
	var res: Resource = _prefetched_texture(path, _current_build_stage())
	if res == null:
		return null
	_atlas_cache[key] = res
	return res


func _current_build_stage() -> String:
	return _active_stage_label


func _res_path(raw: String) -> String:
	if raw.is_empty():
		return ""
	return raw if raw.begins_with("res://") else "res://" + raw


# Unified formal resource acquisition for bootstrap build stages. When a
# coordinator is attached the resource MUST already be in its prefetch cache;
# a miss is recorded by the coordinator as an unexpected synchronous load and
# returns null so the build fails instead of falling back to a sync load.
func _prefetched_texture(path: String, stage_name: String) -> Texture2D:
	if path.is_empty():
		return null
	if bootstrap_coordinator != null:
		var res: Resource = bootstrap_coordinator.get_build_resource(path, stage_name)
		return res as Texture2D
	return load(path) as Texture2D

# Compat aliases
func _bich_ground_atlas() -> Resource: return _region_atlas("bich_ground")
func _bich_prop_atlas() -> Resource: return _region_atlas("bich_prop")
func _orc_tomb_ground_atlas() -> Resource: return _region_atlas("orc_tomb_ground")
func _mine_ground_atlas() -> Resource: return _region_atlas("mine_ground")
# snake_mine kept as preload (single-use)
# snake_mine_prop kept as preload (single-use)
# _region_atlas("snake_mine_glow"): see _REGION_ATLAS_PATHS["snake_mine_glow"]
const BICH_TILE_SIZE := Vector2(64.0, 32.0)
const BICH_PROP_SIZE := Vector2(96.0, 128.0)
const ORC_TOMB_TILE_SIZE := Vector2(64.0, 32.0)
const ORC_TOMB_PROP_SIZE := Vector2(96.0, 128.0)
const SOURCE_COLLISION_RADIUS := 28
const EDITOR_RUNTIME_EDGE_SKIRT_CONTRACT_ID := "map_runtime_nonwalkable_edge_skirt_v1"
const EDITOR_RUNTIME_EDGE_SKIRT_FADE_TILES := 10.0
const DEFAULT_EDITOR_RUNTIME_GUARD_BAND_WORLD := 1536.0

@export var grid_radius := 28
@export var tile_width := 64.0
@export var tile_height := 32.0
var zone_name := "比奇郊外"
var zone_data: Dictionary = {}
var _environment_nodes: Array[Node] = []
var _bich_collision_shapes: Array[Dictionary] = []
var _tomb_collision_shapes: Array[Dictionary] = []
var _focus_position := Vector2.ZERO
var _draw_focus_source := Vector2i(-99999, -99999)
var _collision_focus_source := Vector2i(-99999, -99999)
var _source_collision_nodes: Array[Node] = []
var _source_collision_shape_count := 0
var _collision_rebuild_pending := false
var _pending_collision_focus := Vector2i.ZERO
var _source_mask_image: Image
var _source_mask_path := ""
var _source_clear_segments: Array = []
var _source_clear_cell_cache: Dictionary = {}
var _ground_tile_cache: Dictionary = {}
var _full_ground_ready := false
var _gothic_camp_layout: Dictionary = {}
var _editor_runtime_visual: Dictionary = {}
var _editor_runtime_size := Vector2i.ZERO
var _editor_runtime_blocked_tiles: Dictionary = {}
var _editor_runtime_chunk_draws: Array[Dictionary] = []
var _editor_runtime_fallback_ground := false

# ── HC-P1-004 staged build contract ──
# When attached, every formal resource in the build stages is obtained through
# the coordinator prefetch cache; a missing cache entry is recorded as an
# unexpected synchronous load and fails the bootstrap.
var bootstrap_coordinator: WorldBootstrapCoordinator = null
var _staged_build_complete := false
var _staged_build_map_id := -1
var _staged_generation := -1
var _active_stage_label := "BUILD_MAP"
var _pending_map_descriptors: Array[Dictionary] = []
var _pending_collision_descriptors: Array[Dictionary] = []
var _pending_arrival_position := Vector2.ZERO
var _source_mask_markers: Array[Node] = []
var _gothic_camp_built: Dictionary = {}

# Explicit whitelist of global resources that may be shared across regions.
# Each entry documents ownership; these are the only resources allowed with
# "shared" scope during a target-map resource collection.
const SHARED_GLOBAL_RESOURCE_WHITELIST := {
	"res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png": {
		"owner": "codex/ui-art",
		"note": "Gothic Bich full-ground shader atlas used by the service-home profile fallback.",
	},
	"res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png": {
		"owner": "codex/maps",
		"note": "Legacy tomb-family ground tile base shared by orc-tomb/mine/wooma/snake/natural-cave profile draw fallbacks.",
	},
}


func _ready() -> void:
	z_index = -20
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rebuild_environment()
	queue_redraw()


func set_zone(value: String) -> void:
	zone_name = value
	zone_data = {}
	_rebuild_environment()
	queue_redraw()


func set_focus_position(world_position: Vector2) -> void:
	_focus_position = world_position
	var profile := environment_profile()
	if _source_mask_image == null or str(profile.get("coordinate_projection", "")) != "isometric_64x32_full_size":
		return
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var focus_source := Vector2i(MapCoordinateMapperScript.world_to_source(world_position, source_size).round())
	# Keep a local collision window around the actor. Rebuild only after a
	# meaningful cell change so normal movement does not churn physics bodies.
	if _collision_focus_source.x > -90000 and maxi(abs(focus_source.x - _collision_focus_source.x), abs(focus_source.y - _collision_focus_source.y)) < 8:
		return
	_pending_collision_focus = focus_source
	if not _collision_rebuild_pending:
		_collision_rebuild_pending = true
		_apply_pending_collision_rebuild.call_deferred()


func _apply_pending_collision_rebuild() -> void:
	_collision_rebuild_pending = false
	_collision_focus_source = _pending_collision_focus
	var profile := environment_profile()
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		_rebuild_source_collision_chunk(profile, _collision_focus_source)


func uses_bich_art() -> bool:
	return (
		str(_active_theme().get("asset_set", "")) == "bich"
		and _presentation_map_id(_active_map_id()) == 4
	)


func uses_orc_tomb_art() -> bool:
	return _orc_tomb_map_id() in [217, 218, 221]


func uses_mine_art() -> bool:
	return _active_asset_set() == "mine"


func uses_wooma_temple_art() -> bool:
	return _active_asset_set() == "wooma_temple"


func uses_wooma_forest_art() -> bool:
	return _active_asset_set() == "wooma_forest"


func uses_wooma_cave_art() -> bool:
	return _active_asset_set() == "wooma_cave"


func uses_snake_valley_art() -> bool:
	return _active_asset_set() == "snake_valley"


func uses_snake_mine_art() -> bool:
	return _active_asset_set() == "snake_mine"


func uses_natural_cave_art() -> bool:
	return _active_asset_set() == "natural_cave"


func mine_source_map_code() -> String:
	return str(environment_profile().get("source_map_code", ""))


func environment_source_map_code() -> String:
	return str(environment_profile().get("source_map_code", ""))


func uses_environment_template() -> bool:
	return not environment_profile().is_empty()


func environment_profile() -> Dictionary:
	return EnvironmentCatalogScript.get_map_profile(
		_presentation_map_id(_active_map_id())
	)


func environment_theme_id() -> String:
	return str(environment_profile().get("theme", ""))


func environment_collision_count() -> int:
	return _bich_collision_shapes.size() + _tomb_collision_shapes.size()


func source_collision_shape_count() -> int:
	return _source_collision_shape_count


func source_collision_mask_size() -> Vector2i:
	return _source_mask_image.get_size() if _source_mask_image != null else Vector2i.ZERO


func source_mask_cell_blocked(source_coordinate: Vector2i, apply_clearance := true) -> bool:
	if _source_mask_image == null or source_coordinate.x < 0 or source_coordinate.y < 0 or source_coordinate.x >= _source_mask_image.get_width() or source_coordinate.y >= _source_mask_image.get_height():
		return false
	if apply_clearance and (_source_clear_cell_cache.has(source_coordinate) or (_source_clear_cell_cache.is_empty() and _source_cell_is_cleared(source_coordinate, environment_profile()))):
		return false
	return _source_mask_image.get_pixel(source_coordinate.x, source_coordinate.y).r < 0.5


func environment_node_count() -> int:
	var count := 0
	for node: Node in _environment_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func environment_light_count() -> int:
	return orc_tomb_light_count()


func is_environment_point_blocked(world_position: Vector2) -> bool:
	# Editor-authored maps already contain the complete boundary, blocked-tile and
	# manual-shape contract.  Falling through to every legacy map profile here
	# repeats expensive geometry work for each pursuing monster and can also mix
	# obsolete collision data into the current map.
	if _editor_runtime_size != Vector2i.ZERO:
		return _editor_runtime_blocks_world(world_position)
	return is_bich_point_blocked(world_position) or is_orc_tomb_point_blocked(world_position) or _source_mask_blocks_world(world_position)


func bich_collision_count() -> int:
	return _bich_collision_shapes.size()


func orc_tomb_collision_count() -> int:
	return _tomb_collision_shapes.size()


func orc_tomb_light_count() -> int:
	var count := 0
	for node: Node in _environment_nodes:
		if is_instance_valid(node) and node is PointLight2D:
			count += 1
	return count


func bich_ground_atlas_size() -> Vector2i:
	return _bich_ground_atlas().get_size()


func bich_prop_atlas_size() -> Vector2i:
	return _bich_prop_atlas().get_size()


func orc_tomb_ground_atlas_size() -> Vector2i:
	return _region_atlas("orc_tomb_ground").get_size()


func orc_tomb_prop_atlas_size() -> Vector2i:
	return _region_atlas("orc_tomb_prop").get_size()


func mine_ground_atlas_size() -> Vector2i:
	return _mine_ground_atlas().get_size()


func mine_prop_atlas_size() -> Vector2i:
	return _region_atlas("mine_prop").get_size()


func wooma_temple_ground_atlas_size() -> Vector2i:
	return _region_atlas("wooma_temple_ground").get_size()


func wooma_temple_prop_atlas_size() -> Vector2i:
	return _region_atlas("wooma_temple_prop").get_size()


func wooma_region_atlas_sizes() -> Dictionary:
	return {
		"forest_ground": _region_atlas("wooma_forest_ground").get_size(), "forest_props": _region_atlas("wooma_forest_prop").get_size(),
		"cave_ground": _region_atlas("wooma_cave_ground").get_size(), "cave_props": _region_atlas("wooma_cave_prop").get_size(),
	}


func snake_valley_atlas_sizes() -> Dictionary:
	return {
		"valley_ground": _region_atlas("snake_valley_ground").get_size(), "valley_props": _region_atlas("snake_valley_prop").get_size(),
		"mine_ground": _region_atlas("snake_valley_ground").get_size(), "mine_props": _region_atlas("snake_valley_prop").get_size(),
	}


func natural_cave_atlas_sizes() -> Dictionary:
	var profile := environment_profile()
	var ground := _prefetched_texture(
		str(profile.get("ground_atlas_override", "")), _current_build_stage()
	)
	var props := _prefetched_texture(
		str(profile.get("prop_atlas_override", "")), _current_build_stage()
	)
	return {"ground": ground.get_size() if ground != null else Vector2i.ZERO, "props": props.get_size() if props != null else Vector2i.ZERO}


func bich_tile_index_for_world(world_position: Vector2) -> int:
	var profile := environment_profile()
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var source := MapCoordinateMapperScript.world_to_source(world_position, source_size)
	if not MapCoordinateMapperScript.contains_source(source, source_size):
		return 4
	var edge_cells := minf(minf(source.x, source.y), minf(source_size.x - 1.0 - source.x, source_size.y - 1.0 - source.y))
	if edge_cells < 2.0:
		return 4
	if edge_cells < 5.0:
		return 5
	var route_origin: Vector2 = profile.get("route_origin", Vector2.ZERO)
	for route_position: Vector2 in profile.get("routes", []):
		if _distance_to_segment(world_position, route_origin, route_position) < 52.0:
			return 6 if route_position == profile.get("routes", [])[2] else 2
	for prop_data: Dictionary in profile.get("props", []):
		if int(prop_data.get("kind", -1)) in [0, 1] and world_position.distance_to(prop_data.position) < 145.0:
			return 7
	var noise_key := absi(roundi(source.x) * 13 + roundi(source.y) * 7)
	return 1 if posmod(noise_key, 6) == 0 else 0


func is_bich_point_blocked(world_position: Vector2) -> bool:
	if uses_bich_art():
		var source_size: Vector2i = environment_profile().get("source_size", Vector2i.ZERO)
		if not MapCoordinateMapperScript.contains_source(MapCoordinateMapperScript.world_to_source(world_position, source_size), source_size):
			return true
	for entry: Dictionary in _bich_collision_shapes:
		if entry.kind == "circle" and world_position.distance_to(entry.position) <= float(entry.radius):
			return true
		if entry.kind == "rect":
			var half_size: Vector2 = entry.size * 0.5
			if Rect2(entry.position - half_size, entry.size).has_point(world_position):
				return true
	return false


func orc_tomb_tile_index_for_world(world_position: Vector2) -> int:
	return environment_tile_index_for_world(world_position)


func environment_tile_index_for_world(world_position: Vector2) -> int:
	var profile := environment_profile()
	if str(profile.get("ground_style", "")) == "bich":
		return bich_tile_index_for_world(world_position)
	var map_id := int(profile.get("map_id", -1))
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var full_size := str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size"
	var source := MapCoordinateMapperScript.world_to_source(world_position, source_size) if full_size else Vector2.ZERO
	if full_size:
		if not MapCoordinateMapperScript.contains_source(source, source_size):
			return 6
		var edge_cells := minf(minf(source.x, source.y), minf(source_size.x - 1.0 - source.x, source_size.y - 1.0 - source.y))
		if edge_cells < 3.0:
			return 6
	elif maxf(absf(world_position.x), absf(world_position.y * 1.6)) > 950.0:
		return 6
	var arena: Dictionary = profile.get("arena", {})
	if not arena.is_empty():
		var arena_distance := world_position.distance_to(arena.get("center", Vector2.ZERO))
		if arena_distance < float(arena.get("outer", 250.0)):
			return 7 if arena_distance < float(arena.get("inner", 205.0)) else 3
	for route: Variant in profile.get("routes", []):
		if route is Array and route.size() >= 3 and _distance_to_segment(world_position, route[0], route[1]) < float(route[2]):
			return 5
	var noise_key := absi((roundi(source.x) * 11 + roundi(source.y) * 17 + map_id) if full_size else (int(world_position.x / tile_width) * 11 + int(world_position.y / tile_height) * 17 + map_id))
	if posmod(noise_key, 19) == 0:
		return 2
	if posmod(noise_key, 11) == 0:
		return 4
	return 1 if posmod(noise_key, 5) == 0 else 0


func is_orc_tomb_point_blocked(world_position: Vector2) -> bool:
	var profile := environment_profile()
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
		if not MapCoordinateMapperScript.contains_source(MapCoordinateMapperScript.world_to_source(world_position, source_size), source_size):
			return true
	for entry: Dictionary in _tomb_collision_shapes:
		if entry.kind == "circle" and world_position.distance_to(entry.position) <= float(entry.radius):
			return true
		if entry.kind == "rect":
			var half_size: Vector2 = entry.size * 0.5
			if Rect2(entry.position - half_size, entry.size).has_point(world_position):
				return true
	return false


func _draw() -> void:
	if not _editor_runtime_visual.is_empty():
		var raw_size:Array=_editor_runtime_visual.get("design_size",[64,64]);var size:=Vector2i(int(raw_size[0]),int(raw_size[1]))
		var corners := editor_runtime_ground_boundary_world(size)
		draw_colored_polygon(corners, Color(str(_editor_runtime_visual.get("base_color", "#465827"))))
		# Keep all authored chunk textures on one CanvasItem. Godot otherwise
		# culls distant Sprite2D chunks and can defer their GPU upload until the
		# player approaches an edge, producing a visible hitch on mobile.
		for chunk_draw: Dictionary in _editor_runtime_chunk_draws:
			var texture: Texture2D = chunk_draw.get("texture")
			var rect: Rect2 = chunk_draw.get("rect", Rect2())
			if texture != null and rect.size.x > 0.0 and rect.size.y > 0.0:
				draw_texture_rect(texture, rect, false)
		return
	if _full_ground_ready:
		return
	if uses_bich_art():
		_draw_bich_ground()
		return
	if _uses_tomb_atlas():
		_draw_orc_tomb_ground()
		return

	var base_color := _base_tile_color()
	for x in range(-grid_radius, grid_radius + 1):
		for y in range(-grid_radius, grid_radius + 1):
			var center := Vector2((x - y) * tile_width * 0.5, (x + y) * tile_height * 0.5)
			var shade := 0.028 if posmod(x * 3 + y * 5, 7) == 0 else 0.0
			var color := Color(base_color.r + shade, base_color.g + shade, base_color.b + shade, 1.0)
			var diamond := _diamond_at(center)
			draw_colored_polygon(diamond, color)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0.20, 0.17, 0.12, 0.35), 1.0)
	if environment_theme_id() == "desert":
		for route: Variant in environment_profile().get("routes", []):
			if route is Array and route.size() >= 2:
				draw_line(route[0], route[1], Color(0.36, 0.24, 0.11, 0.66), float(route[2]) * 1.25, true)
				draw_line(route[0], route[1], Color(0.56, 0.39, 0.18, 0.52), float(route[2]) * 0.75, true)

	if zone_name == "比奇城":
		_draw_city()
	elif zone_data.is_empty() or str(zone_data.get("mapGroup", "地表/入口")) == "地表/入口":
		for position in [Vector2(-420, -220), Vector2(460, 160), Vector2(60, 380), Vector2(720, -280)]:
			draw_circle(position, 54.0, Color(0.08, 0.19, 0.11, 0.85))
			draw_circle(position, 38.0, Color(0.10, 0.26, 0.14, 0.85))
	else:
		for position in [Vector2(-430, -210), Vector2(420, 190), Vector2(-50, 410), Vector2(680, -260), Vector2(-720, 280)]:
			draw_colored_polygon(PackedVector2Array([position + Vector2(-45, 25), position + Vector2(-20, -35), position + Vector2(30, -48), position + Vector2(55, 22)]), Color(0.20, 0.19, 0.18, 0.82))
			draw_line(position + Vector2(-25, 4), position + Vector2(28, -18), Color(0.34, 0.31, 0.27), 4.0)


func editor_runtime_ground_boundary_world(size: Vector2i) -> PackedVector2Array:
	# Ground chunks are rasterized around cell centres, so their visible diamond
	# spans [-0.5, size - 0.5]. Keep base fill, guard calculations and hard
	# collision on that one boundary. [0, size] is the same diamond shifted 16
	# world pixels downward and creates the double edge visible on mobile.
	return RuntimeCollisionGeometryScript.map_inner_boundary_world(size)


func _draw_bich_ground() -> void:
	var source_size: Vector2i = environment_profile().get("source_size", Vector2i.ZERO)
	var focus_source := Vector2i(MapCoordinateMapperScript.world_to_source(_focus_position, source_size).round())
	for x in range(focus_source.x - grid_radius, focus_source.x + grid_radius + 1):
		for y in range(focus_source.y - grid_radius, focus_source.y + grid_radius + 1):
			if x < 0 or y < 0 or x >= source_size.x or y >= source_size.y:
				continue
			var center := MapCoordinateMapperScript.source_to_world(Vector2(x, y), source_size)
			var cache_key := y * source_size.x + x
			var tile_index := int(_ground_tile_cache.get(cache_key, -1))
			if tile_index < 0:
				tile_index = bich_tile_index_for_world(center)
				_ground_tile_cache[cache_key] = tile_index
			var source := Rect2(Vector2(tile_index * 64, 0), BICH_TILE_SIZE)
			draw_texture_rect_region(_bich_ground_atlas(), Rect2(center - BICH_TILE_SIZE * 0.5, BICH_TILE_SIZE), source)


func _draw_orc_tomb_ground() -> void:
	var theme_tint: Color = _active_theme().get("tint", Color.WHITE)
	var ground_texture: Texture2D = _region_atlas("orc_tomb_ground")
	var override_path := str(environment_profile().get("ground_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		ground_texture = _prefetched_texture(override_path, _current_build_stage())
	elif uses_mine_art():
		ground_texture = _mine_ground_atlas()
	elif uses_wooma_temple_art():
		ground_texture = _region_atlas("wooma_temple_ground")
	elif uses_wooma_forest_art():
		ground_texture = _region_atlas("wooma_forest_ground")
	elif uses_wooma_cave_art():
		ground_texture = _region_atlas("wooma_cave_ground")
	elif uses_snake_valley_art():
		ground_texture = _region_atlas("snake_valley_ground")
	elif uses_snake_mine_art():
		ground_texture = _region_atlas("snake_valley_ground")
	var profile := environment_profile()
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var full_size := str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size"
	var focus_source := Vector2i(MapCoordinateMapperScript.world_to_source(_focus_position, source_size).round()) if full_size else Vector2i.ZERO
	for x in range(focus_source.x - grid_radius, focus_source.x + grid_radius + 1):
		for y in range(focus_source.y - grid_radius, focus_source.y + grid_radius + 1):
			if full_size and (x < 0 or y < 0 or x >= source_size.x or y >= source_size.y):
				continue
			var center := MapCoordinateMapperScript.source_to_world(Vector2(x, y), source_size) if full_size else Vector2((x - y) * tile_width * 0.5, (x + y) * tile_height * 0.5)
			var cache_key: Variant = y * maxi(1, source_size.x) + x if full_size else Vector2i(x, y)
			var tile_index := int(_ground_tile_cache.get(cache_key, -1))
			if tile_index < 0:
				tile_index = environment_tile_index_for_world(center)
				_ground_tile_cache[cache_key] = tile_index
			var source := Rect2(Vector2(tile_index * 64, 0), ORC_TOMB_TILE_SIZE)
			var edge_factor := clampf(maxf(absf(center.x) / 1150.0, absf(center.y) / 720.0), 0.0, 1.0)
			var lightness := lerpf(0.92, 0.50, edge_factor)
			var tint := Color(lightness * theme_tint.r, lightness * 0.94 * theme_tint.g, lightness * 0.88 * theme_tint.b, 1.0)
			draw_texture_rect_region(ground_texture, Rect2(center - ORC_TOMB_TILE_SIZE * 0.5, ORC_TOMB_TILE_SIZE), source, tint)


func _rebuild_environment() -> void:
	# Legacy synchronous path (no coordinator attached): drain the same
	# descriptor pipeline in one pass. Production entry always uses
	# prepare_map_build() through the coordinator instead.
	bootstrap_coordinator = null
	clear_environment()
	if not is_inside_tree():
		return
	var map_id := _active_map_id()
	var descriptors := build_map_item_descriptors({})
	for descriptor: Dictionary in descriptors:
		build_one_map_item(descriptor)
	var collision_descriptors := build_collision_descriptors({})
	for descriptor: Dictionary in collision_descriptors:
		build_one_collision(descriptor)
	_finish_map_build()


func clear_environment() -> void:
	_ground_tile_cache.clear()
	_full_ground_ready = false
	_gothic_camp_layout.clear()
	_editor_runtime_visual.clear()
	_editor_runtime_size = Vector2i.ZERO
	_editor_runtime_blocked_tiles.clear()
	_editor_runtime_chunk_draws.clear()
	_editor_runtime_fallback_ground = false
	for node: Node in _environment_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_environment_nodes.clear()
	_clear_source_collision_nodes()
	_bich_collision_shapes.clear()
	_tomb_collision_shapes.clear()
	_source_mask_image = null
	_source_mask_path = ""
	_source_clear_segments.clear()
	_source_clear_cell_cache.clear()
	_collision_focus_source = Vector2i(-99999, -99999)
	for node: Node in _source_mask_markers:
		if is_instance_valid(node):
			node.queue_free()
	_source_mask_markers.clear()
	_gothic_camp_built.clear()
	_staged_build_complete = false


func set_zone_data(value: String, data: Dictionary) -> void:
	zone_name = value
	zone_data = data.duplicate(true)
	if _staged_build_complete and _staged_build_map_id == int(data.get("mapId", -1)):
		# Environment was already staged-built by the coordinator for this map;
		# only refresh zone state so the arrival operation can spawn content.
		return
	_rebuild_environment()
	queue_redraw()


# ── HC-P1-004 staged production API ──

func prepare_map_build(
	map_id: int,
	coordinator: WorldBootstrapCoordinator,
	map_data := {}
) -> Dictionary:
	bootstrap_coordinator = coordinator
	_staged_build_complete = false
	_staged_build_map_id = map_id
	_staged_generation = coordinator.generation
	_active_stage_label = "BUILD_MAP"
	var resolved := map_data
	if resolved.is_empty():
		resolved = zone_data.duplicate(true)
		if resolved.is_empty():
			resolved = {"mapId": map_id, "name": _default_zone_name(map_id)}
	var zone_name_value := str(resolved.get("name", ""))
	zone_name = zone_name_value if not zone_name_value.is_empty() else _default_zone_name(map_id)
	zone_data = resolved.duplicate(true)
	clear_environment()
	if coordinator != null:
		coordinator.collect_map_resources(resolved)
		_collect_target_map_resources(map_id)
	_pending_map_descriptors = build_map_item_descriptors(resolved)
	_pending_collision_descriptors = build_collision_descriptors(resolved)
	return {
		"ok": true,
		"map_id": map_id,
		"planned_map_item_count": _pending_map_descriptors.size(),
		"planned_collision_count": _pending_collision_descriptors.size(),
	}


func set_pending_arrival_position(position_px: Vector2) -> void:
	_pending_arrival_position = position_px


func submit_staged_build() -> void:
	if bootstrap_coordinator == null:
		return
	bootstrap_coordinator.submit_map_descriptors(_pending_map_descriptors)
	bootstrap_coordinator.submit_collision_descriptors(_pending_collision_descriptors)


func finish_map_build() -> void:
	_finish_map_build()


func _finish_map_build() -> void:
	_staged_build_complete = true
	_staged_build_map_id = _active_map_id()
	queue_redraw()


func _default_zone_name(map_id: int) -> String:
	if _presentation_map_id(map_id) == 4:
		return "比奇省"
	if _orc_tomb_map_id() in [217, 218, 221]:
		return "兽人古墓"
	return "未命名地图"


func _map_id_from_data(map_data: Dictionary) -> int:
	var map_id := int(map_data.get("mapId", -1))
	if map_id > 0:
		return map_id
	return _active_map_id()


func _generation_token() -> int:
	if bootstrap_coordinator != null:
		return bootstrap_coordinator.generation
	return _staged_generation


func _generation_is_current() -> bool:
	if bootstrap_coordinator != null:
		return bootstrap_coordinator.is_generation_current(_staged_generation)
	return true


func _append_environment_node(node: Node) -> Node:
	if not _generation_is_current():
		node.free()
		return null
	add_child(node)
	_environment_nodes.append(node)
	return node


func _append_actor_sort_node(root: Node2D, sprite: Sprite2D) -> Node2D:
	if not _generation_is_current():
		root.free()
		return null
	get_parent().add_child(root)
	root.add_child(sprite)
	_environment_nodes.append(root)
	return root


# ── HC-P1-004 map descriptors ──

func _descriptor(
	kind: String,
	source_index: int,
	layer: String,
	resource_path: String,
	position_px: Vector2,
	z_index: int,
	payload: Dictionary,
	generation: int
) -> Dictionary:
	return {
		"kind": kind,
		"source_index": source_index,
		"layer": layer,
		"resource_path": resource_path,
		"position_px": position_px,
		"z_index": z_index,
		"payload": payload,
		"generation": generation,
	}


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
	if not MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		return {}
	return MapEditorRuntimeBridgeScript.load_map(map_id)


func _visual_data_for(map_id: int, runtime: Dictionary) -> Dictionary:
	if runtime.is_empty():
		return {}
	return _load_editor_runtime_visual(map_id, runtime)


func _ground_atlas_path_for(profile: Dictionary) -> String:
	var override_path := str(profile.get("ground_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		return override_path
	if (
		_presentation_map_id(_active_map_id()) == 4
		or str(profile.get("asset_set", "")) == "bich"
	):
		return _REGION_ATLAS_PATHS.get("gothic_bich_ground", "")
	return _REGION_ATLAS_PATHS.get("orc_tomb_ground", "")


func _prop_atlas_path_for(profile: Dictionary) -> String:
	var override_path := str(profile.get("prop_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		return override_path
	var asset_set := str(profile.get("asset_set", ""))
	if asset_set == "":
		asset_set = str(EnvironmentCatalogScript.get_theme(
			str(profile.get("theme", ""))
		).get("asset_set", ""))
	match asset_set:
		"mine":
			return _REGION_ATLAS_PATHS.get("mine_prop", "")
		"wooma_temple":
			return _REGION_ATLAS_PATHS.get("wooma_temple_prop", "")
		"wooma_forest":
			return _REGION_ATLAS_PATHS.get("wooma_forest_prop", "")
		"wooma_cave":
			return _REGION_ATLAS_PATHS.get("wooma_cave_prop", "")
		"snake_valley", "snake_mine":
			return _REGION_ATLAS_PATHS.get("snake_valley_prop", "")
		"bich":
			return _REGION_ATLAS_PATHS.get("bich_prop", "")
	return _REGION_ATLAS_PATHS.get("orc_tomb_prop", "")


func _light_atlas_path_for(profile: Dictionary) -> String:
	var override_path := str(profile.get("light_texture_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		return override_path
	var asset_set := str(profile.get("asset_set", ""))
	if asset_set == "":
		asset_set = str(EnvironmentCatalogScript.get_theme(
			str(profile.get("theme", ""))
		).get("asset_set", ""))
	match asset_set:
		"mine":
			return _REGION_ATLAS_PATHS.get("mine_lamp_glow", "")
		"wooma_temple":
			return _REGION_ATLAS_PATHS.get("wooma_temple_fire_glow", "")
		"wooma_cave":
			return _REGION_ATLAS_PATHS.get("wooma_cave_glow", "")
		"snake_mine":
			return _REGION_ATLAS_PATHS.get("snake_mine_glow", "")
	return _REGION_ATLAS_PATHS.get("orc_tomb_fire_glow", "")


func build_map_item_descriptors(map_data: Dictionary) -> Array:
	var map_id := _map_id_from_data(map_data)
	var runtime := _runtime_data_for(map_id)
	var visual := _visual_data_for(map_id, runtime)
	var generation := _generation_token()
	var descriptors: Array[Dictionary] = []
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id) and not runtime.is_empty():
		if not visual.is_empty():
			_editor_runtime_visual = visual
			_append_chunk_descriptors(descriptors, visual, generation)
			descriptors.append(_descriptor(
				"guard_band", 1, "ground", "", Vector2.ZERO, -30,
				{"visual": visual}, generation
			))
			_append_instance_descriptors(descriptors, runtime, generation)
		else:
			var profile := environment_profile()
			if not profile.is_empty():
				var raw_size: Array = runtime.get("design", {}).get("design_size", [])
				if raw_size.size() == 2:
					var runtime_profile := profile.duplicate(true)
					runtime_profile["source_size"] = Vector2i(
						int(raw_size[0]), int(raw_size[1])
					)
					descriptors.append(_descriptor(
						"full_ground", 0, "ground",
						_ground_atlas_path_for(runtime_profile), Vector2.ZERO, -20,
						{"profile": runtime_profile}, generation
					))
					_append_instance_descriptors(descriptors, runtime, generation)
	elif not environment_profile().is_empty():
		_append_profile_map_descriptors(descriptors, map_id, generation)
	_pending_map_descriptors = descriptors
	return descriptors


func _append_chunk_descriptors(
	descriptors: Array,
	visual: Dictionary,
	generation: int
) -> void:
	var center: Array = visual.get("ground_pixel_center", [8192, 4096])
	var center_px := Vector2(float(center[0]), float(center[1]))
	for index in visual.get("chunks", []).size():
		var chunk: Dictionary = visual.get("chunks", [])[index]
		var image_path := _res_path(str(chunk.get("image", "")))
		if not ResourceLoader.exists(image_path):
			continue
		var rect: Array = chunk.get("rect_px", [])
		if rect.size() != 4:
			continue
		descriptors.append(_descriptor(
			"chunk_draw", index, "ground", image_path,
			Vector2(float(rect[0]) - center_px.x, float(rect[1]) - center_px.y),
			-20,
			{
				"chunk_id": str(chunk.get("chunk_id", "")),
				"rect": Rect2(
					float(rect[0]) - center_px.x,
					float(rect[1]) - center_px.y,
					float(rect[2]),
					float(rect[3])
				),
			},
			generation
		))


func _append_instance_descriptors(
	descriptors: Array,
	runtime: Dictionary,
	generation: int
) -> void:
	var raw_size: Array = runtime.get("design", {}).get("design_size", [64, 64])
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var commands := RuntimeVisualGeometryScript.sorted_draw_commands(
		runtime.get("instances", [])
	)
	for command_index in commands.size():
		var command: Dictionary = commands[command_index]
		var image_path := str(command.get("image_path", ""))
		if image_path.is_empty():
			continue
		var resource_path := _res_path(image_path)
		if not ResourceLoader.exists(resource_path):
			continue
		var render_domain := str(command.get(
			"render_domain",
			RuntimeVisualGeometryScript.RENDER_DOMAIN_STATIC_BACKGROUND
		))
		descriptors.append(_descriptor(
			"instance_sprite", command_index, "object",
			resource_path, Vector2.ZERO, -5,
			{
				"command": command,
				"design_size": size,
				"render_domain": render_domain,
			},
			generation
		))


func _append_profile_map_descriptors(
	descriptors: Array,
	map_id: int,
	generation: int
) -> void:
	var profile := environment_profile()
	if profile.is_empty():
		return
	if (
		_presentation_map_id(map_id) == 4
		and bool(profile.get("gothic_camp_enabled", true))
	):
		descriptors.append(_descriptor(
			"gothic_camp", 0, "ground", "", Vector2.ZERO, -20,
			{
				"profile": profile,
				"home": profile.get("runtime_home_position", Vector2.ZERO),
			},
			generation
		))
		if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
			descriptors.append(_descriptor(
				"full_ground", 1, "ground",
				_ground_atlas_path_for(profile), Vector2.ZERO, -20,
				{"profile": profile},
				generation
			))
		return
	if _active_asset_set() == "bich":
		for index in profile.get("props", []).size():
			var prop_data: Dictionary = profile.get("props", [])[index]
			var position: Vector2 = prop_data.get("position", Vector2.ZERO)
			descriptors.append(_descriptor(
				"prop_sprite", index, "prop",
				_prop_atlas_path_for(profile), position, -5,
				{
					"kind": int(prop_data.get("kind", 0)),
					"canopy": bool(prop_data.get("canopy", false)),
					"prop": prop_data,
					"tomb": false,
				},
				generation
			))
		if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
			descriptors.append(_descriptor(
				"full_ground", 2000, "ground",
				_ground_atlas_path_for(profile), Vector2.ZERO, -20,
				{"profile": profile},
				generation
			))
		return
	for index in profile.get("props", []).size():
		var prop_data: Dictionary = profile.get("props", [])[index]
		var kind := int(prop_data.get("kind", 0))
		var position: Vector2 = prop_data.get("position", Vector2.ZERO)
		var canopy := bool(prop_data.get("canopy", kind in [0, 1, 5]))
		descriptors.append(_descriptor(
			"prop_sprite", index, "prop",
			_prop_atlas_path_for(profile), position, -5,
			{
				"kind": kind,
				"canopy": canopy,
				"prop": prop_data,
				"tomb": true,
			},
			generation
		))
	for index in profile.get("braziers", []).size():
		var brazier_position: Vector2 = profile.get("braziers", [])[index]
		descriptors.append(_descriptor(
			"prop_sprite", 1000 + index, "prop",
			_prop_atlas_path_for(profile), brazier_position, -5,
			{
				"kind": 2,
				"canopy": true,
				"prop": {"position": brazier_position, "occlusion": true},
				"tomb": true,
			},
			generation
		))
		descriptors.append(_descriptor(
			"light_glow", 2000 + index, "light",
			_light_atlas_path_for(profile), brazier_position + Vector2(0, -54), -4,
			{"position": brazier_position + Vector2(0, -54)},
			generation
		))
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		descriptors.append(_descriptor(
			"full_ground", 3000, "ground",
			_ground_atlas_path_for(profile), Vector2.ZERO, -20,
			{"profile": profile},
			generation
		))


# ── HC-P1-004 target-map resource collection ──

func _region_id_for_map(map_id: int, profile: Dictionary) -> String:
	if _presentation_map_id(map_id) == 4:
		return "bich"
	var asset_set := str(profile.get("asset_set", ""))
	if asset_set == "":
		asset_set = str(EnvironmentCatalogScript.get_theme(
			str(profile.get("theme", ""))
		).get("asset_set", ""))
	if asset_set != "":
		return asset_set
	if _orc_tomb_map_id() in [217, 218, 221]:
		return "orc_tomb"
	return "unknown"


func _collect_target_map_resources(map_id: int) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var profile := environment_profile()
	var region := _region_id_for_map(map_id, profile)
	coord.set_target_region(region)
	var runtime := _runtime_data_for(map_id)
	var visual := _visual_data_for(map_id, runtime)
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id) and not runtime.is_empty():
		if not visual.is_empty():
			for chunk: Dictionary in visual.get("chunks", []):
				var image_path := _res_path(str(chunk.get("image", "")))
				if not image_path.is_empty() and ResourceLoader.exists(image_path):
					coord.register_resource(
						image_path, "texture", true, "editor_chunk", "target", region
					)
		_register_command_resources(runtime, region)
		_register_profile_ground_resources(map_id, profile, region)
		# Editor runtime maps still resolve prop/light atlases through the
		# profile (legacy draw fallbacks and diagnostics), so they must be
		# prefetched as target-map resources.
		_register_profile_prop_resources(profile, region)
		_register_profile_light_resources(profile, region)
		return
	_register_profile_ground_resources(map_id, profile, region)
	_register_profile_prop_resources(profile, region)
	_register_profile_light_resources(profile, region)
	var mask_path := str(profile.get("collision_mask_path", ""))
	if map_id != 4 and not mask_path.is_empty() and ResourceLoader.exists(mask_path):
		coord.register_resource(
			mask_path, "collision_mask", true, "collision_mask", "target", region
		)
	if (
		_presentation_map_id(map_id) == 4
		and bool(profile.get("gothic_camp_enabled", true))
	):
		_register_gothic_camp_resources(region)


func _register_command_resources(runtime: Dictionary, region: String) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var commands := RuntimeVisualGeometryScript.sorted_draw_commands(
		runtime.get("instances", [])
	)
	for command: Dictionary in commands:
		var image_path := _res_path(str(command.get("image_path", "")))
		if not image_path.is_empty() and ResourceLoader.exists(image_path):
			coord.register_resource(
				image_path, "texture", true, "editor_instance", "target", region
			)


func _register_profile_ground_resources(
	map_id: int,
	profile: Dictionary,
	region: String
) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var ground_path := _ground_atlas_path_for(profile)
	if not ground_path.is_empty() and ResourceLoader.exists(ground_path):
		var is_shared := SHARED_GLOBAL_RESOURCE_WHITELIST.has(ground_path)
		coord.register_resource(
			ground_path, "texture", true, "ground_atlas",
			"shared" if is_shared else "target",
			"global" if is_shared else region
		)
	if _uses_tomb_atlas() and not MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		# The legacy tomb-family draw fallback only runs for non-editor
		# profiles; editor runtime maps render authored chunks instead.
		var base_path: String = str(
			_REGION_ATLAS_PATHS.get("orc_tomb_ground", "")
		)
		if (
			not base_path.is_empty()
			and ResourceLoader.exists(base_path)
			and base_path != ground_path
		):
			coord.register_resource(
				base_path, "texture", true, "tomb_ground_draw",
				"shared", "global"
			)
	if _presentation_map_id(map_id) == 4:
		var bich_ground: String = str(_REGION_ATLAS_PATHS.get("bich_ground", ""))
		if not bich_ground.is_empty() and ResourceLoader.exists(bich_ground):
			coord.register_resource(
				bich_ground, "texture", true, "bich_ground_draw", "target", region
			)


func _register_profile_prop_resources(profile: Dictionary, region: String) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var prop_path := _prop_atlas_path_for(profile)
	if not prop_path.is_empty() and ResourceLoader.exists(prop_path):
		coord.register_resource(
			prop_path, "texture", true, "prop_atlas", "target", region
		)


func _register_profile_light_resources(profile: Dictionary, region: String) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var has_lights: bool = profile.get("braziers", []).size() > 0
	var has_override: bool = not str(
		profile.get("light_texture_override", "")
	).is_empty()
	if not has_lights and not has_override:
		return
	var light_path := _light_atlas_path_for(profile)
	if not light_path.is_empty() and ResourceLoader.exists(light_path):
		coord.register_resource(
			light_path, "texture", true, "light_atlas", "target", region
		)


func _register_gothic_camp_resources(region: String) -> void:
	var coord := bootstrap_coordinator
	if coord == null:
		return
	var ground_path := "res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png"
	coord.register_resource(
		ground_path, "texture", true, "gothic_camp_ground", "shared", "global"
	)
	var layout := GothicBichCampBuilderScript.load_layout()
	for record: Variant in layout.get("props", []):
		if not record is Dictionary:
			continue
		var asset_id := str(record.get("asset", ""))
		if asset_id.is_empty():
			continue
		var path := "res://assets/presentation/skins/gothic_bich_camp/sprites/%s.png" % asset_id
		if ResourceLoader.exists(path):
			coord.register_resource(
				path, "texture", true, "gothic_camp_prop", "target", region
			)
	for record: Variant in layout.get("lights", []):
		if not record is Dictionary:
			continue
		var texture_id := str(record.get("texture", ""))
		if texture_id.is_empty():
			continue
		var path := "res://assets/presentation/skins/gothic_bich_camp/sprites/%s.png" % texture_id
		if ResourceLoader.exists(path):
			coord.register_resource(
				path, "texture", true, "gothic_camp_light", "target", region
			)


func _build_gothic_camp_node(payload: Dictionary) -> Node:
	if not _generation_is_current():
		return null
	var home: Vector2 = payload.get("home", Vector2.ZERO)
	var built := GothicBichCampBuilderScript.build(self, home)
	_gothic_camp_built = built
	_gothic_camp_layout = built.get("layout", {})
	_environment_nodes.append_array(built.get("nodes", []))
	var nodes: Array = built.get("nodes", [])
	return nodes.front() as Node if not nodes.is_empty() else null


func build_one_map_item(descriptor: Dictionary) -> Node:
	if not _generation_is_current():
		return null
	_active_stage_label = "BUILD_MAP"
	var kind := str(descriptor.get("kind", ""))
	var resource_path := str(descriptor.get("resource_path", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	match kind:
		"chunk_draw":
			var texture := _prefetched_texture(resource_path, "BUILD_MAP")
			if texture == null:
				return null
			_editor_runtime_chunk_draws.append({
				"chunk_id": str(payload.get("chunk_id", "")),
				"texture": texture,
				"rect": payload.get("rect", Rect2()),
			})
			var marker := Node2D.new()
			marker.name = "WorldChunk_%s" % str(payload.get("chunk_id", "x"))
			marker.set_meta("editor_runtime_chunk_marker", true)
			marker.set_meta(
				"editor_runtime_chunk_id", str(payload.get("chunk_id", ""))
			)
			marker.z_index = int(descriptor.get("z_index", -20))
			return _append_environment_node(marker)
		"guard_band":
			return _build_guard_band_node(payload)
		"full_ground":
			var ground_texture := _prefetched_texture(resource_path, "BUILD_MAP")
			if ground_texture == null:
				return null
			return _build_full_ground_node(payload, ground_texture)
		"instance_sprite":
			var instance_texture := _prefetched_texture(resource_path, "BUILD_MAP")
			if instance_texture == null:
				return null
			return _build_one_editor_runtime_instance(
				payload.get("command", {}),
				int(descriptor.get("source_index", 0)),
				payload.get("design_size", Vector2i.ZERO),
				instance_texture
			)
		"prop_sprite":
			var prop_texture := _prefetched_texture(resource_path, "BUILD_MAP")
			if prop_texture == null:
				return null
			return _build_prop_sprite_node(payload, prop_texture)
		"light_glow":
			var light_texture := _prefetched_texture(resource_path, "BUILD_MAP")
			if light_texture == null:
				return null
			return _build_light_glow_node(payload, light_texture)
		"gothic_camp":
			return _build_gothic_camp_node(payload)
	return null


# ── HC-P1-004 collision descriptors ──

func build_collision_descriptors(map_data: Dictionary) -> Array:
	var map_id := _map_id_from_data(map_data)
	var runtime := _runtime_data_for(map_id)
	var generation := _generation_token()
	var descriptors: Array[Dictionary] = []
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id) and not runtime.is_empty():
		_append_editor_runtime_collision_descriptors(descriptors, runtime, generation)
	elif not environment_profile().is_empty():
		_append_profile_collision_descriptors(descriptors, map_id, generation)
	_pending_collision_descriptors = descriptors
	return descriptors


func _append_editor_runtime_collision_descriptors(
	descriptors: Array,
	runtime: Dictionary,
	generation: int
) -> void:
	var raw_size: Array = runtime.design.get("design_size", [256, 256])
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	_editor_runtime_size = size
	_editor_runtime_blocked_tiles = RuntimeCollisionGeometryScript.blocked_cell_set(
		runtime.collision
	)
	var inner := RuntimeCollisionGeometryScript.map_actor_boundary_world(size)
	var outer := RuntimeCollisionGeometryScript.map_outer_boundary_world(size)
	for side in range(inner.size()):
		var next := (side + 1) % 4
		descriptors.append(_collision_descriptor(
			"boundary_side", side,
			{
				"outer": outer[side],
				"outer_next": outer[next],
				"inner": inner[side],
				"inner_next": inner[next],
				"side": side,
				"size": size,
			},
			generation
		))
	for rect: Rect2i in RuntimeCollisionGeometryScript.blocked_cell_runs(
		runtime.collision
	):
		descriptors.append(_collision_descriptor(
			"blocked_rect_run", descriptors.size(),
			{"rect": rect, "size": size},
			generation
		))


func _append_profile_collision_descriptors(
	descriptors: Array,
	map_id: int,
	generation: int
) -> void:
	var profile := environment_profile()
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
	var mask_path := str(profile.get("collision_mask_path", ""))
	if map_id != 4 and not mask_path.is_empty() and ResourceLoader.exists(mask_path):
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
	var shape := str(prop_data.get("shape", ""))
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


func build_one_collision(descriptor: Dictionary) -> CollisionObject2D:
	if not _generation_is_current():
		return null
	_active_stage_label = "BUILD_COLLISION"
	var kind := str(descriptor.get("kind", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	match kind:
		"boundary_side":
			return _build_editor_boundary_side(payload)
		"blocked_rect_run":
			return _build_blocked_rect_run(payload)
		"obstacle_circle":
			return _build_obstacle_body(payload, "circle")
		"obstacle_rect":
			return _build_obstacle_body(payload, "rect")
		"boundary_segment":
			return _build_boundary_segment(payload)
		"source_mask_load":
			return _build_source_mask_load(payload)
		"gothic_camp_collisions":
			return _build_gothic_camp_collisions(payload)
	return null


func _build_editor_boundary_side(payload: Dictionary) -> CollisionObject2D:
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([
		payload.get("outer", Vector2.ZERO),
		payload.get("outer_next", Vector2.ZERO),
		payload.get("inner_next", Vector2.ZERO),
		payload.get("inner", Vector2.ZERO),
	])
	var collision := CollisionShape2D.new()
	collision.name = "MapBoundary%d" % int(payload.get("side", 0))
	collision.shape = shape
	body.add_child(collision)
	body.set_meta("editor_runtime_boundary", true)
	_source_collision_shape_count += 1
	return _append_environment_node(body) as CollisionObject2D


func _build_blocked_rect_run(payload: Dictionary) -> CollisionObject2D:
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("editor_runtime_blocked_run", true)
	var rect: Rect2i = payload.get("rect", Rect2i())
	var size: Vector2i = payload.get("size", Vector2i.ZERO)
	var shape := ConvexPolygonShape2D.new()
	shape.points = RuntimeCollisionGeometryScript.rect_polygon_world(
		[float(rect.position.x), float(rect.position.y), float(rect.size.x), float(rect.size.y)],
		size
	)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	_source_collision_shape_count += 1
	return _append_environment_node(body) as CollisionObject2D


func _build_obstacle_body(payload: Dictionary, shape_kind: String) -> CollisionObject2D:
	var owner := str(payload.get("owner", "tomb"))
	var position: Vector2 = payload.get("position", Vector2.ZERO)
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	if shape_kind == "circle":
		var shape := CircleShape2D.new()
		shape.radius = float(payload.get("radius", 22.0))
		collision.shape = shape
		if owner == "bich":
			_bich_collision_shapes.append({
				"kind": "circle",
				"position": position,
				"radius": float(payload.get("radius", 22.0)),
			})
		else:
			_tomb_collision_shapes.append({
				"kind": "circle",
				"position": position,
				"radius": float(payload.get("radius", 22.0)),
			})
	else:
		var shape := RectangleShape2D.new()
		shape.size = payload.get("size", Vector2(88, 34))
		collision.shape = shape
		if owner == "bich":
			_bich_collision_shapes.append({
				"kind": "rect",
				"position": position,
				"size": shape.size,
			})
		else:
			_tomb_collision_shapes.append({
				"kind": "rect",
				"position": position,
				"size": shape.size,
			})
	body.add_child(collision)
	return _append_environment_node(body) as CollisionObject2D


func _build_boundary_segment(payload: Dictionary) -> CollisionObject2D:
	var owner := str(payload.get("owner", "tomb"))
	var start: Vector2 = payload.get("start", Vector2.ZERO)
	var finish: Vector2 = payload.get("finish", Vector2.ZERO)
	var shape := SegmentShape2D.new()
	shape.a = start
	shape.b = finish
	var body := _add_static_body_node(Vector2.ZERO, shape)
	if owner == "bich":
		_bich_collision_shapes.append({
			"kind": "segment", "start": start, "finish": finish,
		})
	else:
		_tomb_collision_shapes.append({
			"kind": "segment", "start": start, "finish": finish,
		})
	return body


func _build_source_mask_load(payload: Dictionary) -> CollisionObject2D:
	var profile: Dictionary = payload.get("profile", {})
	_load_source_collision_mask(profile)
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("source_mask_loaded", true)
	if not _generation_is_current():
		body.free()
		return null
	add_child(body)
	_source_mask_markers.append(body)
	return body


func _build_gothic_camp_collisions(payload: Dictionary) -> CollisionObject2D:
	for node: Node in _gothic_camp_built.get("nodes", []):
		if node is StaticBody2D and bool(node.get_meta("gothic_bich_camp", false)):
			return node as CollisionObject2D
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	return _append_environment_node(body) as CollisionObject2D


func _load_editor_runtime_visual(
	runtime_map_id: int,
	runtime: Dictionary
) -> Dictionary:
	var visual_path := MapEditorRuntimeBridgeScript.visual_path(
		runtime_map_id
	)
	var visual := _read_editor_json(visual_path)
	if visual.is_empty():
		return {}
	var runtime_map_key := str(runtime.get("source", {}).get("map_id", ""))
	if str(visual.get("map_id", "")) != runtime_map_key:
		return {}
	if int(visual.get("runtime_map_id", -1)) != runtime_map_id:
		return {}
	if not bool(visual.get("coverage", {}).get(
		"complete", _presentation_map_id(runtime_map_id) == 4
	)):
		return {}
	return visual


func _read_editor_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _build_guard_band_node(payload: Dictionary) -> Node:
	var visual: Dictionary = payload.get("visual", {})
	var raw_size: Array = visual.get("design_size", [64, 64])
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var corners := editor_runtime_ground_boundary_world(size)
	var authored_bounds := Rect2(corners[0], Vector2.ZERO)
	for point: Vector2 in corners:
		authored_bounds = authored_bounds.expand(point)
	var guard_band_world := float(visual.get(
		"guard_band_px", DEFAULT_EDITOR_RUNTIME_GUARD_BAND_WORLD
	))
	var guard_bounds := authored_bounds.grow(guard_band_world)
	var guard := Polygon2D.new()
	guard.name = "EditorRuntimeGuardBand"
	guard.set_meta("editor_runtime_guard_band", true)
	guard.set_meta(
		"editor_runtime_edge_skirt_contract_id",
		EDITOR_RUNTIME_EDGE_SKIRT_CONTRACT_ID
	)
	guard.set_meta("editor_runtime_guard_non_walkable", true)
	guard.set_meta("editor_runtime_guard_band_world", guard_band_world)
	guard.set_meta(
		"editor_runtime_guard_fade_tiles",
		EDITOR_RUNTIME_EDGE_SKIRT_FADE_TILES
	)
	guard.z_as_relative = false
	guard.z_index = -30
	guard.polygon = PackedVector2Array([
		guard_bounds.position,
		Vector2(guard_bounds.end.x, guard_bounds.position.y),
		guard_bounds.end,
		Vector2(guard_bounds.position.x, guard_bounds.end.y),
	])
	var is_bich_runtime := (
		int(visual.get("runtime_map_id", -1))
		== MapEditorRuntimeBridgeScript.BICH_MAP_ID
	)
	var shader := Shader.new()
	shader.code = ("""
shader_type canvas_item;
render_mode unshaded;
uniform vec2 design_size = vec2(80.0, 80.0);
uniform float fade_tiles = 10.0;
varying vec2 map_position;
void vertex() {
	map_position = VERTEX;
}
void fragment() {
	vec2 iso = vec2(
		(map_position.x / 32.0 + map_position.y / 16.0) * 0.5,
		(map_position.y / 16.0 - map_position.x / 32.0) * 0.5
	) + (design_size - vec2(1.0)) * 0.5;
	vec2 outside_low = max(vec2(-0.5) - iso, vec2(0.0));
	vec2 outside_high = max(
		iso - (design_size - vec2(0.5)), vec2(0.0)
	);
	float outside_tiles = max(
		max(outside_low.x, outside_low.y),
		max(outside_high.x, outside_high.y)
	);
	if (outside_tiles <= 0.0001) {
		discard;
	}
	float fade = smoothstep(0.0, max(fade_tiles, 0.001), outside_tiles);
	vec3 near_skirt = vec3(0.050, 0.066, 0.033);
	vec3 far_skirt = vec3(0.030, 0.046, 0.022);
	vec3 color = mix(near_skirt, far_skirt, fade);
	COLOR = vec4(color, mix(0.98, 0.94, fade));
}
""" if is_bich_runtime else """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 design_size = vec2(80.0, 80.0);
uniform float fade_tiles = 10.0;
varying vec2 map_position;
void vertex() {
	map_position = VERTEX;
}
float terrain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float coarse = terrain_hash(floor(map_position / 64.0));
	float fine = terrain_hash(floor(map_position / 12.0));
	vec2 iso = vec2(
		(map_position.x / 32.0 + map_position.y / 16.0) * 0.5,
		(map_position.y / 16.0 - map_position.x / 32.0) * 0.5
	) + (design_size - vec2(1.0)) * 0.5;
	vec2 outside_low = max(vec2(-0.5) - iso, vec2(0.0));
	vec2 outside_high = max(
		iso - (design_size - vec2(0.5)), vec2(0.0)
	);
	float outside_tiles = max(
		max(outside_low.x, outside_low.y),
		max(outside_high.x, outside_high.y)
	);
	float fade = smoothstep(0.0, max(fade_tiles, 0.001), outside_tiles);
	float edge_mark = 1.0 - smoothstep(0.0, 0.55, outside_tiles);
	vec3 near_skirt = vec3(0.050, 0.066, 0.033);
	vec3 far_skirt = vec3(0.006, 0.010, 0.006);
	vec3 variation = vec3((coarse - 0.5) * 0.014 + (fine - 0.5) * 0.005);
	vec3 color = mix(near_skirt + variation, far_skirt, fade);
	color += vec3(0.030, 0.025, 0.012) * edge_mark;
	COLOR = vec4(color, mix(1.0, 0.92, fade));
}
"""
)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("design_size", Vector2(size))
	material.set_shader_parameter(
		"fade_tiles", EDITOR_RUNTIME_EDGE_SKIRT_FADE_TILES
	)
	guard.material = material
	return _append_environment_node(guard)


func editor_runtime_chunk_texture_count() -> int:
	return _editor_runtime_chunk_draws.size()


func editor_runtime_ground_ready() -> bool:
	return not _editor_runtime_visual.is_empty() or _editor_runtime_fallback_ground


func uses_editor_runtime_fallback_ground() -> bool:
	return _editor_runtime_fallback_ground


func _build_editor_runtime_instances(runtime:Dictionary)->void:
	var raw_size: Array = runtime.design.get("design_size", [64, 64])
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var commands := RuntimeVisualGeometryScript.sorted_draw_commands(
		runtime.get("instances", [])
	)
	for command_index in commands.size():
		var command: Dictionary = commands[command_index]
		_build_one_editor_runtime_instance(command, command_index, size)


func _build_one_editor_runtime_instance(
	command: Dictionary,
	command_index: int,
	size: Vector2i,
	texture: Texture2D = null
) -> Node:
	var image_path := str(command.get("image_path", ""))
	if image_path.is_empty():
		return null
	var resource_path := _res_path(image_path)
	if texture == null:
		if not ResourceLoader.exists(resource_path):
			return null
		texture = _prefetched_texture(resource_path, "BUILD_MAP")
	if texture == null:
		return null
	var geometry := RuntimeVisualGeometryScript.runtime_command_geometry(
		command, size, texture.get_size()
	)
	var sprite := Sprite2D.new()
	sprite.name = "EditorRuntimeInstance_%d" % command_index
	sprite.set_meta("editor_runtime_instance", true)
	sprite.set_meta(
		"editor_runtime_instance_id",
		str(command.get("instance", {}).get("instance_id", ""))
	)
	sprite.set_meta("editor_runtime_image_path", image_path)
	sprite.set_meta("editor_runtime_command_index", command_index)
	sprite.texture = texture
	sprite.centered = false
	# Keep the node at the authored foot/part center and move only the drawn
	# pixels.  Using top_left as position would rotate wall parts around the
	# wrong pivot and recreate the editor/runtime offset.
	var render_domain := str(command.get(
		"render_domain",
		RuntimeVisualGeometryScript.RENDER_DOMAIN_STATIC_BACKGROUND
	))
	var actor_sort_root: Node2D = null
	var parent_world_origin := Vector2.ZERO
	if render_domain == RuntimeVisualGeometryScript.RENDER_DOMAIN_ACTOR_Y_SORT:
		actor_sort_root = Node2D.new()
		actor_sort_root.name = "EditorRuntimeOccluder_%d" % command_index
		actor_sort_root.position = RuntimeVisualGeometryScript.command_actor_sort_world(
			command, size
		)
		parent_world_origin = actor_sort_root.position
		actor_sort_root.set_meta("editor_runtime_actor_occluder", true)
		actor_sort_root.set_meta("editor_runtime_sort_tile", command.sort_tile)
		actor_sort_root.set_meta("editor_runtime_instance_id", str(
			command.get("instance", {}).get("instance_id", "")
		))
	RuntimeVisualGeometryScript.apply_runtime_sprite_geometry(
		sprite, command, geometry, parent_world_origin
	)
	sprite.set_meta("editor_runtime_render_domain", render_domain)
	if actor_sort_root != null:
		# The wrapper is a direct sibling of actors under GameRoot's Y-sort.
		# Keep the sprite in that same z domain so Y order, not a fixed z,
		# determines whether the wall front is before or behind an actor.
		sprite.z_index = 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if actor_sort_root != null and get_parent() != null:
		return _append_actor_sort_node(actor_sort_root, sprite)
	return _append_environment_node(sprite)


func _editor_runtime_blocks_world(world_position: Vector2) -> bool:
	if _editor_runtime_size == Vector2i.ZERO:
		return false
	return RuntimeCollisionGeometryScript.blocked_cells_contain_world(
		_editor_runtime_blocked_tiles,
		world_position,
		_editor_runtime_size
	)


func _add_prop(
	kind: int,
	foot_position: Vector2,
	_canopy: bool,
	prop: Dictionary = {}
) -> void:
	_build_prop_sprite_node({
		"kind": kind,
		"canopy": _canopy,
		"prop": prop,
		"tomb": false,
		"position": foot_position,
	}, _bich_prop_atlas() as Texture2D)


func _add_tomb_prop(
	kind: int,
	foot_position: Vector2,
	_canopy: bool,
	prop: Dictionary = {}
) -> void:
	var prop_texture: Texture2D = _region_atlas("orc_tomb_prop")
	var override_path := str(environment_profile().get("prop_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		prop_texture = _prefetched_texture(override_path, _current_build_stage())
	elif uses_mine_art():
		prop_texture = _region_atlas("mine_prop")
	elif uses_wooma_temple_art():
		prop_texture = _region_atlas("wooma_temple_prop")
	elif uses_wooma_forest_art():
		prop_texture = _region_atlas("wooma_forest_prop")
	elif uses_wooma_cave_art():
		prop_texture = _region_atlas("wooma_cave_prop")
	elif uses_snake_valley_art():
		prop_texture = _region_atlas("snake_valley_prop")
	elif uses_snake_mine_art():
		prop_texture = _region_atlas("snake_valley_prop")
	_build_prop_sprite_node({
		"kind": kind,
		"canopy": _canopy,
		"prop": prop,
		"tomb": true,
		"position": foot_position,
	}, prop_texture)


func _build_prop_sprite_node(payload: Dictionary, texture: Texture2D) -> Node:
	if texture == null:
		return null
	var kind := int(payload.get("kind", 0))
	var foot_position: Vector2 = payload.get("position", Vector2.ZERO)
	var prop: Dictionary = payload.get("prop", {})
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		Vector2(kind * 96, 0),
		BICH_PROP_SIZE if not bool(payload.get("tomb", false)) else ORC_TOMB_PROP_SIZE
	)
	sprite.centered = false
	return _add_legacy_profile_prop_sprite(sprite, foot_position, prop)


func _add_legacy_profile_prop_sprite(
	sprite: Sprite2D,
	foot_position: Vector2,
	prop: Dictionary
) -> Node:
	var effective_prop := prop.duplicate(true)
	effective_prop["position"] = foot_position
	var render_domain := RuntimeVisualGeometryScript.legacy_profile_prop_render_domain(
		effective_prop
	)
	if (
		render_domain == RuntimeVisualGeometryScript.RENDER_DOMAIN_ACTOR_Y_SORT
		and get_parent() != null
	):
		var actor_sort_root := Node2D.new()
		actor_sort_root.name = "LegacyProfileOccluder"
		actor_sort_root.position = RuntimeVisualGeometryScript.legacy_profile_prop_actor_sort_world(
			effective_prop
		)
		actor_sort_root.z_as_relative = false
		actor_sort_root.z_index = 0
		actor_sort_root.set_meta("legacy_profile_actor_occluder", true)
		actor_sort_root.set_meta(
			"map_occlusion_sort_contract_id",
			RuntimeVisualGeometryScript.OCCLUSION_SORT_CONTRACT_ID
		)
		actor_sort_root.set_meta("legacy_profile_render_domain", render_domain)
		sprite.position = foot_position - Vector2(48, 118) - actor_sort_root.position
		sprite.z_as_relative = true
		sprite.z_index = 0
		return _append_actor_sort_node(actor_sort_root, sprite)
	sprite.position = foot_position - Vector2(48, 118)
	sprite.z_as_relative = false
	sprite.z_index = -5
	sprite.set_meta("legacy_profile_render_domain", render_domain)
	return _append_environment_node(sprite)


func _add_tomb_light(position: Vector2) -> void:
	var light_texture: Texture2D = _region_atlas("orc_tomb_fire_glow")
	var override_path := str(environment_profile().get("light_texture_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		light_texture = _prefetched_texture(override_path, _current_build_stage())
	elif uses_mine_art():
		light_texture = _region_atlas("mine_lamp_glow")
	elif uses_wooma_temple_art():
		light_texture = _region_atlas("wooma_temple_fire_glow")
	elif uses_wooma_cave_art():
		light_texture = _region_atlas("wooma_cave_glow")
	elif uses_snake_mine_art():
		light_texture = _region_atlas("snake_mine_glow")
	_build_light_glow_node({"position": position}, light_texture)


func _build_light_glow_node(payload: Dictionary, light_texture: Texture2D) -> Node:
	if light_texture == null:
		return null
	var position: Vector2 = payload.get("position", Vector2.ZERO)
	var glow := Sprite2D.new()
	glow.texture = light_texture
	glow.position = position
	glow.scale = Vector2(2.2, 1.5)
	glow.modulate = Color(1.0, 0.72, 0.42, 0.52)
	glow.z_as_relative = false
	glow.z_index = -4
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = material
	_append_environment_node(glow)
	var light := PointLight2D.new()
	light.texture = light_texture
	light.position = position
	light.texture_scale = 2.0
	light.energy = 0.75
	light.color = Color(1.0, 0.52, 0.22)
	light.z_as_relative = false
	light.z_index = -3
	_append_environment_node(light)
	return glow


func _load_source_collision_mask(profile: Dictionary) -> void:
	_source_mask_path = str(profile.get("collision_mask_path", ""))
	if _source_mask_path.is_empty() or not ResourceLoader.exists(_source_mask_path):
		return
	var texture := _prefetched_texture(_source_mask_path, "BUILD_COLLISION")
	if texture == null:
		return
	var image := texture.get_image()
	var expected_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	if image == null or image.get_size() != expected_size:
		return
	_source_mask_image = image
	_build_source_clear_segments(profile)


func _clear_source_collision_nodes() -> void:
	for node: Node in _source_collision_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_source_collision_nodes.clear()
	_source_collision_shape_count = 0


func _rebuild_source_collision_chunk(profile: Dictionary, focus_source: Vector2i) -> void:
	_clear_source_collision_nodes()
	if _source_mask_image == null:
		return
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var minimum := Vector2i(maxi(0, focus_source.x - SOURCE_COLLISION_RADIUS), maxi(0, focus_source.y - SOURCE_COLLISION_RADIUS))
	var maximum := Vector2i(mini(source_size.x - 1, focus_source.x + SOURCE_COLLISION_RADIUS), mini(source_size.y - 1, focus_source.y + SOURCE_COLLISION_RADIUS))
	if minimum.x > maximum.x or minimum.y > maximum.y:
		return
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("source_collision_chunk", true)
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
			_add_source_collision_run(body, run_start, x, y, source_size)
			x += 1
	if body.get_child_count() > 0:
		add_child(body)
		_source_collision_nodes.append(body)
	else:
		body.free()


func _build_full_ground(profile: Dictionary) -> void:
	var atlas: Texture2D = _region_atlas("gothic_bich_ground") if uses_bich_art() else _region_atlas("orc_tomb_ground")
	var override_path := str(profile.get("ground_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		atlas = _prefetched_texture(override_path, _current_build_stage())
	_build_full_ground_node({"profile": profile}, atlas)


func _build_full_ground_node(payload: Dictionary, atlas: Texture2D) -> Node:
	var profile: Dictionary = payload.get("profile", {})
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	if source_size == Vector2i.ZERO:
		return null
	if atlas == null:
		return null
	var bounds := MapCoordinateMapperScript.world_bounds(source_size).grow(32.0)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	ground.z_index = -20
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D atlas_tex : source_color, filter_nearest;
uniform vec2 source_size;
varying vec2 map_position;
void vertex() {
	map_position = VERTEX;
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.001), 0.0, 1.0);
	return distance(p, a + ab * t);
}
void fragment() {
	vec2 world = map_position;
	vec2 center = (source_size - vec2(1.0)) * 0.5;
	float h = world.x / 32.0;
	float v = world.y / 16.0;
	vec2 source = center + vec2((h + v) * 0.5, (v - h) * 0.5);
	vec2 cell = floor(source + vec2(0.5));
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= source_size.x || cell.y >= source_size.y) discard;
	vec2 d = source - cell;
	vec2 local_uv = vec2((d.x - d.y) * 0.5 + 0.5, (d.x + d.y) * 0.5 + 0.5);
	float hashv = mod(abs(cell.x * 11.0 + cell.y * 17.0), 23.0);
	float tile = hashv < 3.0 ? 1.0 : (hashv < 5.0 ? 2.0 : 0.0);
	vec2 home = vec2(0.0, 0.0);
	float city_distance = distance(world, home);
	if (city_distance < 700.0) tile = hashv < 8.0 ? 4.0 : 3.0;
	vec2 exits[5] = {vec2(608.0,-336.0), vec2(-608.0,-336.0), vec2(0.0,288.0), vec2(608.0,176.0), vec2(-608.0,176.0)};
	for (int i = 0; i < 5; i++) {
		if (segment_distance(world, home, exits[i]) < 66.0) tile = hashv < 5.0 ? 6.0 : 5.0;
	}
	vec2 atlas_uv = vec2((tile + local_uv.x) / 8.0, local_uv.y);
	vec4 sampled = texture(atlas_tex, atlas_uv);
	vec3 base = city_distance < 700.0 ? vec3(0.19, 0.14, 0.09) : vec3(0.12, 0.18, 0.095);
	COLOR = vec4(mix(base, sampled.rgb, sampled.a), 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas_tex", atlas)
	material.set_shader_parameter("source_size", Vector2(source_size))
	ground.material = material
	_append_environment_node(ground)
	_full_ground_ready = true
	return ground


func _rebuild_full_source_collision(profile: Dictionary) -> void:
	_clear_source_collision_nodes()
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("source_collision_full_map", true)
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
			_add_source_collision_run(body, run_start, x, y, source_size)
			x += 1
	if body.get_child_count() > 0:
		add_child(body)
		_source_collision_nodes.append(body)
	else:
		body.free()


func _add_source_collision_run(body: StaticBody2D, start_x: int, end_x: int, y: int, source_size: Vector2i) -> void:
	var start := MapCoordinateMapperScript.source_to_world(Vector2(start_x, y), source_size)
	var finish := MapCoordinateMapperScript.source_to_world(Vector2(end_x, y), source_size)
	var shape := ConvexPolygonShape2D.new()
	if start_x == end_x:
		shape.points = PackedVector2Array([start + Vector2(-32, 0), start + Vector2(0, -16), start + Vector2(32, 0), start + Vector2(0, 16)])
	else:
		shape.points = PackedVector2Array([
			start + Vector2(-32, 0), start + Vector2(0, -16),
			finish + Vector2(0, -16), finish + Vector2(32, 0),
			finish + Vector2(0, 16), start + Vector2(0, 16),
		])
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	_source_collision_shape_count += 1


func _source_mask_blocks_world(world_position: Vector2) -> bool:
	if _source_mask_image == null:
		return false
	var source_size: Vector2i = environment_profile().get("source_size", Vector2i.ZERO)
	var source := Vector2i(MapCoordinateMapperScript.world_to_source(world_position, source_size).round())
	return source_mask_cell_blocked(source, true)


func _source_cell_is_cleared(source_coordinate: Vector2i, profile: Dictionary) -> bool:
	if (
		_presentation_map_id(_active_map_id()) == 4
		and not _gothic_camp_layout.is_empty()
	):
		var camp_world := MapCoordinateMapperScript.source_to_world(Vector2(source_coordinate), profile.get("source_size", Vector2i.ZERO))
		if camp_world.distance_to(profile.get("runtime_home_position", Vector2.ZERO)) <= float(_gothic_camp_layout.get("safeRadius", 690.0)):
			return true
	var content := RegionContent.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		var radius := 7.0 if group_name == "bosses" else (4.0 if group_name == "portals" else 2.5)
		for entry: Dictionary in content.get(group_name, []):
			if entry.has("source_coordinate") and Vector2(source_coordinate).distance_to(Vector2(entry.source_coordinate)) <= radius:
				return true
	var world_position := MapCoordinateMapperScript.source_to_world(Vector2(source_coordinate), profile.get("source_size", Vector2i.ZERO))
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
	var content := RegionContent.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs"]:
		for entry: Dictionary in content.get(group_name, []):
			var actor_position: Vector2 = entry.get("position", Vector2.ZERO)
			var nearest_point := Vector2.ZERO
			var nearest_distance := INF
			for route: Array in route_segments:
				var point := _closest_point_on_segment(actor_position, route[0], route[1])
				var distance := actor_position.distance_to(point)
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
	var content := RegionContent.get_map_content(_active_map_id())
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			var radius := 112.0 if group_name == "bosses" else (64.0 if group_name == "portals" else 48.0)
			_mark_clear_world_circle(entry.get("position", Vector2.ZERO), radius, profile)
	var arena: Dictionary = profile.get("arena", {})
	if not arena.is_empty():
		_mark_clear_world_circle(arena.get("center", Vector2.ZERO), float(arena.get("outer", 0.0)), profile)


func _mark_clear_world_segment(start: Vector2, finish: Vector2, width: float, profile: Dictionary) -> void:
	var steps := maxi(1, ceili(start.distance_to(finish) / 16.0))
	for index in range(steps + 1):
		_mark_clear_world_circle(start.lerp(finish, float(index) / steps), width, profile)


func _mark_clear_world_circle(world_position: Vector2, radius: float, profile: Dictionary) -> void:
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	var center := Vector2i(MapCoordinateMapperScript.world_to_source(world_position, source_size).round())
	var cell_radius := maxi(1, ceili(radius / 16.0))
	for y in range(center.y - cell_radius, center.y + cell_radius + 1):
		for x in range(center.x - cell_radius, center.x + cell_radius + 1):
			var cell := Vector2i(x, y)
			if MapCoordinateMapperScript.contains_source(Vector2(cell), source_size):
				_source_clear_cell_cache[cell] = true


func _closest_point_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> Vector2:
	var segment := finish - start
	if segment.length_squared() <= 0.001:
		return start
	var ratio := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return start + segment * ratio


func _add_static_body(position: Vector2, shape: Shape2D) -> CollisionObject2D:
	return _add_static_body_node(position, shape)


func _add_static_body_node(position: Vector2, shape: Shape2D) -> CollisionObject2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	return _append_environment_node(body) as CollisionObject2D


func _orc_tomb_map_id() -> int:
	var map_id := _presentation_map_id(int(zone_data.get("mapId", -1)))
	if map_id in [217, 218, 221]:
		return map_id
	match zone_name:
		"兽人古墓一层": return 217
		"兽人古墓二层": return 218
		"兽人古墓三层": return 221
	return -1


func _active_map_id() -> int:
	var map_id := int(zone_data.get("mapId", -1))
	if map_id > 0:
		return map_id
	if zone_name in ["比奇郊外", "比奇省"]:
		return 910001
	return _orc_tomb_map_id()


func _presentation_map_id(runtime_map_id: int) -> int:
	if runtime_map_id == int(zone_data.get("mapId", -1)):
		var legacy_id := int(zone_data.get("legacyRuntimeMapId", -1))
		if legacy_id > 0:
			return legacy_id
	return runtime_map_id


func _active_theme() -> Dictionary:
	return EnvironmentCatalogScript.get_theme(environment_theme_id())


func _active_asset_set() -> String:
	return str(environment_profile().get("asset_set", _active_theme().get("asset_set", "")))


func _uses_tomb_atlas() -> bool:
	return _active_asset_set() in ["orc_tomb", "mine", "wooma_temple", "wooma_forest", "wooma_cave", "snake_valley", "snake_mine", "natural_cave"]


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() == 0.0:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _diamond_at(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -tile_height * 0.5),
		center + Vector2(tile_width * 0.5, 0),
		center + Vector2(0, tile_height * 0.5),
		center + Vector2(-tile_width * 0.5, 0),
	])


func _base_tile_color() -> Color:
	if zone_name == "比奇城":
		return Color(0.17, 0.15, 0.12)
	if environment_theme_id() == "desert":
		return Color(0.24, 0.17, 0.085)
	if zone_data.is_empty():
		return Color(0.12, 0.105, 0.075)
	var group := str(zone_data.get("mapGroup", ""))
	var region := str(zone_data.get("region", ""))
	if group == "地表/入口":
		if "沙" in region or "盟重" in region:
			return Color(0.18, 0.135, 0.075)
		if "苍月" in region:
			return Color(0.08, 0.13, 0.15)
		return Color(0.10, 0.14, 0.075)
	var variants := [Color(0.085, 0.075, 0.068), Color(0.075, 0.07, 0.085), Color(0.10, 0.072, 0.055), Color(0.06, 0.085, 0.078)]
	return variants[absi(zone_name.hash()) % variants.size()]


func _draw_city() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-700, -120), Vector2(0, -470), Vector2(700, -120), Vector2(0, 230)]), Color(0.31, 0.27, 0.21, 0.74))
	for rect in [Rect2(-610, -380, 280, 170), Rect2(330, -380, 280, 170), Rect2(-610, 160, 280, 170), Rect2(330, 160, 280, 170)]:
		draw_rect(rect, Color(0.27, 0.13, 0.08))
		draw_rect(Rect2(rect.position + Vector2(16, 18), rect.size - Vector2(32, 36)), Color(0.48, 0.30, 0.16))
		draw_line(rect.position, rect.position + Vector2(rect.size.x * 0.5, -80), Color(0.56, 0.20, 0.10), 18.0)
		draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(rect.size.x * 0.5, -80), Color(0.56, 0.20, 0.10), 18.0)
	for x in range(-800, 801, 80):
		draw_rect(Rect2(x, -560, 72, 45), Color(0.32, 0.29, 0.25))
