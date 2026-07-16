class_name WorldBackground
extends Node2D

const EnvironmentCatalogScript := preload("res://scripts/environment_catalog.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const EditorCoordinateScript := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const BICH_GROUND_ATLAS := preload("res://assets/art/maps/bich/bich_ground_tiles.png")
const GOTHIC_BICH_GROUND_ATLAS := preload("res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png")
const BICH_PROP_ATLAS := preload("res://assets/art/maps/bich/bich_props.png")
const ORC_TOMB_GROUND_ATLAS := preload("res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png")
const ORC_TOMB_PROP_ATLAS := preload("res://assets/art/maps/orc_tomb/orc_tomb_props.png")
const ORC_TOMB_FIRE_GLOW := preload("res://assets/art/maps/orc_tomb/orc_tomb_fire_glow.png")
const MINE_GROUND_ATLAS := preload("res://assets/art/maps/mine/mine_ground_tiles.png")
const MINE_PROP_ATLAS := preload("res://assets/art/maps/mine/mine_props.png")
const MINE_LAMP_GLOW := preload("res://assets/art/maps/mine/mine_lamp_glow.png")
const WOOMA_TEMPLE_GROUND_ATLAS := preload("res://assets/art/maps/wooma_temple/wooma_temple_ground_tiles.png")
const WOOMA_TEMPLE_PROP_ATLAS := preload("res://assets/art/maps/wooma_temple/wooma_temple_props.png")
const WOOMA_TEMPLE_FIRE_GLOW := preload("res://assets/art/maps/wooma_temple/wooma_temple_fire_glow.png")
const WOOMA_FOREST_GROUND_ATLAS := preload("res://assets/art/maps/wooma_region/wooma_forest_ground_tiles.png")
const WOOMA_FOREST_PROP_ATLAS := preload("res://assets/art/maps/wooma_region/wooma_forest_props.png")
const WOOMA_CAVE_GROUND_ATLAS := preload("res://assets/art/maps/wooma_region/wooma_cave_ground_tiles.png")
const WOOMA_CAVE_PROP_ATLAS := preload("res://assets/art/maps/wooma_region/wooma_cave_props.png")
const WOOMA_CAVE_GLOW := preload("res://assets/art/maps/wooma_region/wooma_cave_glow.png")
const SNAKE_VALLEY_GROUND_ATLAS := preload("res://assets/art/maps/snake_valley/snake_valley_ground_tiles.png")
const SNAKE_VALLEY_PROP_ATLAS := preload("res://assets/art/maps/snake_valley/snake_valley_props.png")
const SNAKE_MINE_GROUND_ATLAS := preload("res://assets/art/maps/snake_valley/snake_mine_ground_tiles.png")
const SNAKE_MINE_PROP_ATLAS := preload("res://assets/art/maps/snake_valley/snake_mine_props.png")
const SNAKE_MINE_GLOW := preload("res://assets/art/maps/snake_valley/snake_mine_glow.png")
const BICH_TILE_SIZE := Vector2(64.0, 32.0)
const BICH_PROP_SIZE := Vector2(96.0, 128.0)
const ORC_TOMB_TILE_SIZE := Vector2(64.0, 32.0)
const ORC_TOMB_PROP_SIZE := Vector2(96.0, 128.0)
const SOURCE_COLLISION_RADIUS := 28

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
var _editor_runtime_manual_rects: Array[Rect2] = []


func _ready() -> void:
	z_index = -20
	_rebuild_environment()
	queue_redraw()


func set_zone(value: String) -> void:
	zone_name = value
	zone_data = {}
	_rebuild_environment()
	queue_redraw()


func set_zone_data(value: String, data: Dictionary) -> void:
	zone_name = value
	zone_data = data.duplicate(true)
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
	return str(_active_theme().get("asset_set", "")) == "bich" and _active_map_id() == 4


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
	return EnvironmentCatalogScript.get_map_profile(_active_map_id())


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
	return _editor_runtime_blocks_world(world_position) or is_bich_point_blocked(world_position) or is_orc_tomb_point_blocked(world_position) or _source_mask_blocks_world(world_position)


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
	return BICH_GROUND_ATLAS.get_size()


func bich_prop_atlas_size() -> Vector2i:
	return BICH_PROP_ATLAS.get_size()


func orc_tomb_ground_atlas_size() -> Vector2i:
	return ORC_TOMB_GROUND_ATLAS.get_size()


func orc_tomb_prop_atlas_size() -> Vector2i:
	return ORC_TOMB_PROP_ATLAS.get_size()


func mine_ground_atlas_size() -> Vector2i:
	return MINE_GROUND_ATLAS.get_size()


func mine_prop_atlas_size() -> Vector2i:
	return MINE_PROP_ATLAS.get_size()


func wooma_temple_ground_atlas_size() -> Vector2i:
	return WOOMA_TEMPLE_GROUND_ATLAS.get_size()


func wooma_temple_prop_atlas_size() -> Vector2i:
	return WOOMA_TEMPLE_PROP_ATLAS.get_size()


func wooma_region_atlas_sizes() -> Dictionary:
	return {
		"forest_ground": WOOMA_FOREST_GROUND_ATLAS.get_size(), "forest_props": WOOMA_FOREST_PROP_ATLAS.get_size(),
		"cave_ground": WOOMA_CAVE_GROUND_ATLAS.get_size(), "cave_props": WOOMA_CAVE_PROP_ATLAS.get_size(),
	}


func snake_valley_atlas_sizes() -> Dictionary:
	return {
		"valley_ground": SNAKE_VALLEY_GROUND_ATLAS.get_size(), "valley_props": SNAKE_VALLEY_PROP_ATLAS.get_size(),
		"mine_ground": SNAKE_MINE_GROUND_ATLAS.get_size(), "mine_props": SNAKE_MINE_PROP_ATLAS.get_size(),
	}


func natural_cave_atlas_sizes() -> Dictionary:
	var profile := environment_profile()
	var ground := load(str(profile.get("ground_atlas_override", ""))) as Texture2D
	var props := load(str(profile.get("prop_atlas_override", ""))) as Texture2D
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
		var corners := PackedVector2Array([
			EditorCoordinateScript.tile_to_world(Vector2(0,0),size), EditorCoordinateScript.tile_to_world(Vector2(size.x,0),size),
			EditorCoordinateScript.tile_to_world(Vector2(size.x,size.y),size), EditorCoordinateScript.tile_to_world(Vector2(0,size.y),size)])
		draw_colored_polygon(corners, Color(str(_editor_runtime_visual.get("base_color", "#465827"))))
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
			draw_texture_rect_region(BICH_GROUND_ATLAS, Rect2(center - BICH_TILE_SIZE * 0.5, BICH_TILE_SIZE), source)


func _draw_orc_tomb_ground() -> void:
	var theme_tint: Color = _active_theme().get("tint", Color.WHITE)
	var ground_texture: Texture2D = ORC_TOMB_GROUND_ATLAS
	var override_path := str(environment_profile().get("ground_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		ground_texture = load(override_path) as Texture2D
	elif uses_mine_art():
		ground_texture = MINE_GROUND_ATLAS
	elif uses_wooma_temple_art():
		ground_texture = WOOMA_TEMPLE_GROUND_ATLAS
	elif uses_wooma_forest_art():
		ground_texture = WOOMA_FOREST_GROUND_ATLAS
	elif uses_wooma_cave_art():
		ground_texture = WOOMA_CAVE_GROUND_ATLAS
	elif uses_snake_valley_art():
		ground_texture = SNAKE_VALLEY_GROUND_ATLAS
	elif uses_snake_mine_art():
		ground_texture = SNAKE_MINE_GROUND_ATLAS
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
	_ground_tile_cache.clear()
	_full_ground_ready = false
	_gothic_camp_layout.clear()
	_editor_runtime_visual.clear()
	_editor_runtime_size = Vector2i.ZERO
	_editor_runtime_blocked_tiles.clear()
	_editor_runtime_manual_rects.clear()
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
	if not is_inside_tree():
		return
	if _active_map_id() == 4 and _build_editor_runtime_environment():
		return
	var profile := environment_profile()
	if not profile.is_empty():
		_build_profile_environment(profile)
		# The redesigned Bich surface does not match the legacy collision bitmap.
		# Visible camp props and the outer boundary are its authoritative collisions.
		if _active_map_id() != 4:
			_load_source_collision_mask(profile)
		if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
			_build_full_ground(profile)


func _build_editor_runtime_environment() -> bool:
	var manifest_path := "res://assets/data/runtime/map_editor/bich_province.visual.json"
	var runtime_path := "res://assets/data/runtime/map_editor/bich_province.runtime.json"
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(runtime_path): return false
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text()) if manifest_file != null else null
	if not parsed is Dictionary: return false
	_editor_runtime_visual = parsed
	var center: Array = parsed.get("ground_pixel_center", [8192,4096])
	for chunk: Dictionary in parsed.get("chunks", []):
		var image_path := "res://" + str(chunk.get("image", ""))
		if not ResourceLoader.exists(image_path): continue
		var rect: Array = chunk.get("rect_px", [])
		if rect.size() != 4: continue
		var sprite := Sprite2D.new(); sprite.name = "EditorGroundChunk"; sprite.set_meta("editor_runtime_chunk", true); sprite.texture = load(image_path); sprite.z_as_relative=false; sprite.z_index=-20
		sprite.position = Vector2(float(rect[0])+float(rect[2])*.5-float(center[0]), float(rect[1])+float(rect[3])*.5-float(center[1]))
		add_child(sprite); _environment_nodes.append(sprite)
	var loaded := MapEditorRuntimeMapService.load_runtime(runtime_path)
	if loaded.ok:
		_build_editor_runtime_instances(loaded.runtime)
		_build_editor_runtime_collisions(loaded.runtime)
	_full_ground_ready = false
	return true


func _build_editor_runtime_instances(runtime:Dictionary)->void:
	var raw_size:Array=runtime.design.get("design_size",[64,64]);var size:=Vector2i(int(raw_size[0]),int(raw_size[1]))
	for instance:Dictionary in runtime.get("instances",[]):
		var asset:=MapAssetCatalogService.find_asset(str(instance.get("asset_id","")));var image_path:=str(asset.get("image",""))
		if image_path.is_empty() or not ResourceLoader.exists("res://"+image_path):continue
		var tile:Array=instance.get("tile",[0,0]);var footprint:Array=instance.get("footprint_tiles",[1,1]);var offset_px:Array=instance.get("offset_px",[0,0]);var anchor:Array=instance.get("anchor_px",asset.get("anchor_px",[0,0]));var scale_value:Array=instance.get("scale",[1,1])
		var foot_tile:=Vector2(float(tile[0])+float(footprint[0])*.5,float(tile[1])+float(footprint[1])*.5)
		var foot_world:=EditorCoordinateScript.tile_to_world(foot_tile,size)+Vector2(float(offset_px[0]),float(offset_px[1]))
		var sprite:=Sprite2D.new();sprite.name="EditorRuntimeInstance";sprite.set_meta("editor_runtime_instance",true);sprite.texture=load("res://"+image_path);sprite.centered=false;sprite.scale=Vector2(float(scale_value[0]),float(scale_value[1]));sprite.position=foot_world-Vector2(float(anchor[0]),float(anchor[1]))*sprite.scale
		sprite.z_as_relative=false;sprite.z_index=-10+clampi(roundi(foot_world.y/32.0),-8,8);sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite);_environment_nodes.append(sprite)


func _build_editor_runtime_collisions(runtime: Dictionary) -> void:
	var body := StaticBody2D.new(); body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER; body.collision_mask = 0; add_child(body); _environment_nodes.append(body)
	var raw_size: Array = runtime.design.get("design_size", [256,256]); var size := Vector2i(int(raw_size[0]),int(raw_size[1]))
	_editor_runtime_size = size
	# Runtime ground chunks only cover the authored diamond.  Internal blocked
	# tiles do not stop an actor from crossing that diamond and walking into the
	# black area outside it, so build a permanent four-sided collision ring.
	# The ring lives just outside the last logical tile and applies equally to
	# the player and monsters through environment collision layer 1.
	_add_editor_map_boundary(body, size)
	var blocked_by_row := {}
	for raw_key: Variant in runtime.collision.get("blocked_tiles", []):
		var parts := str(raw_key).split(",")
		if parts.size()!=2: continue
		_editor_runtime_blocked_tiles[str(raw_key)] = true
		var y:=int(parts[1]); var xs:Array=blocked_by_row.get(y,[]); xs.append(int(parts[0])); blocked_by_row[y]=xs
	for y: int in blocked_by_row:
		var xs:Array=blocked_by_row[y]; xs.sort(); if xs.is_empty():continue
		var run_start:=int(xs[0]); var previous:=run_start
		for index in range(1,xs.size()+1):
			var flush:=index==xs.size() or int(xs[index])!=previous+1
			if flush:
				_add_editor_collision_tile_rect(body,Rect2i(run_start,y,previous-run_start+1,1),size)
				if index<xs.size():run_start=int(xs[index])
			if index<xs.size():previous=int(xs[index])
	for manual: Dictionary in runtime.collision.get("manual_shapes", []):
		if str(manual.get("shape", "")) != "rect": continue
		var rect: Array = manual.get("data", {}).get("rect", [])
		if rect.size()!=4: continue
		var x:=float(rect[0]); var y:=float(rect[1]); var w:=float(rect[2]); var h:=float(rect[3])
		_editor_runtime_manual_rects.append(Rect2(x - 0.5, y - 0.5, w, h))
		var shape := ConvexPolygonShape2D.new()
		shape.points = PackedVector2Array([EditorCoordinateScript.tile_to_world(Vector2(x-.5,y-.5),size), EditorCoordinateScript.tile_to_world(Vector2(x+w-.5,y-.5),size), EditorCoordinateScript.tile_to_world(Vector2(x+w-.5,y+h-.5),size), EditorCoordinateScript.tile_to_world(Vector2(x-.5,y+h-.5),size)])
		var node := CollisionShape2D.new(); node.shape=shape; body.add_child(node); _source_collision_shape_count += 1


func _editor_runtime_blocks_world(world_position: Vector2) -> bool:
	if _editor_runtime_size == Vector2i.ZERO:
		return false
	var tile := EditorCoordinateScript.world_to_tile(world_position, _editor_runtime_size)
	if not EditorCoordinateScript.contains_tile(tile, _editor_runtime_size):
		return true
	var nearest := Vector2i(tile.round())
	if _editor_runtime_blocked_tiles.has("%d,%d" % [nearest.x, nearest.y]):
		return true
	for rect: Rect2 in _editor_runtime_manual_rects:
		if rect.has_point(tile):
			return true
	return false


func _add_editor_map_boundary(body: StaticBody2D, size: Vector2i) -> void:
	var inner := [
		Vector2(-0.5, -0.5),
		Vector2(float(size.x) - 0.5, -0.5),
		Vector2(float(size.x) - 0.5, float(size.y) - 0.5),
		Vector2(-0.5, float(size.y) - 0.5),
	]
	var margin := 8.0
	var outer := [
		Vector2(-0.5 - margin, -0.5 - margin),
		Vector2(float(size.x) - 0.5 + margin, -0.5 - margin),
		Vector2(float(size.x) - 0.5 + margin, float(size.y) - 0.5 + margin),
		Vector2(-0.5 - margin, float(size.y) - 0.5 + margin),
	]
	for side in range(4):
		var next := (side + 1) % 4
		var shape := ConvexPolygonShape2D.new()
		shape.points = PackedVector2Array([
			EditorCoordinateScript.tile_to_world(outer[side], size),
			EditorCoordinateScript.tile_to_world(outer[next], size),
			EditorCoordinateScript.tile_to_world(inner[next], size),
			EditorCoordinateScript.tile_to_world(inner[side], size),
		])
		var collision := CollisionShape2D.new()
		collision.name = "MapBoundary%d" % side
		collision.shape = shape
		body.add_child(collision)
		_source_collision_shape_count += 1


func _add_editor_collision_tile_rect(body:StaticBody2D,rect:Rect2i,size:Vector2i)->void:
	var x:=float(rect.position.x);var y:=float(rect.position.y);var w:=float(rect.size.x);var h:=float(rect.size.y)
	var shape:=ConvexPolygonShape2D.new()
	shape.points=PackedVector2Array([EditorCoordinateScript.tile_to_world(Vector2(x-.5,y-.5),size),EditorCoordinateScript.tile_to_world(Vector2(x+w-.5,y-.5),size),EditorCoordinateScript.tile_to_world(Vector2(x+w-.5,y+h-.5),size),EditorCoordinateScript.tile_to_world(Vector2(x-.5,y+h-.5),size)])
	var node:=CollisionShape2D.new();node.shape=shape;body.add_child(node);_source_collision_shape_count+=1


func _build_profile_environment(profile: Dictionary) -> void:
	if _active_map_id() == 4 and bool(profile.get("gothic_camp_enabled", true)):
		var built := GothicBichCampBuilderScript.build(self, profile.get("runtime_home_position", Vector2.ZERO))
		_gothic_camp_layout = built.get("layout", {})
		_environment_nodes.append_array(built.get("nodes", []))
		for collision: Dictionary in built.get("collisions", []):
			var definition: Dictionary = collision.get("definition", {})
			if str(definition.get("type", "")) == "circle":
				_bich_collision_shapes.append({"kind": "circle", "position": collision.position, "radius": float(definition.get("radius", 16.0))})
			else:
				_bich_collision_shapes.append({"kind": "rect", "position": collision.position, "size": GothicBichCampBuilderScript._vector(definition.get("size", [32, 20]))})
		_add_bich_map_boundaries(profile)
		return
	if _active_asset_set() == "bich":
		for prop_data: Dictionary in profile.get("props", []):
			var position: Vector2 = prop_data.get("position", Vector2.ZERO)
			_add_prop(int(prop_data.get("kind", 0)), position, bool(prop_data.get("canopy", false)))
			match str(prop_data.get("shape", "")):
				"circle": _add_circle_obstacle(position + prop_data.get("collision_offset", Vector2.ZERO), float(prop_data.get("radius", 22.0)))
				"rect": _add_rect_obstacle(position + prop_data.get("collision_offset", Vector2.ZERO), prop_data.get("size", Vector2(88, 34)))
		_add_bich_map_boundaries(profile)
		return
	_build_dungeon_profile(profile)


func _build_dungeon_profile(profile: Dictionary) -> void:
	for prop_data: Dictionary in profile.get("props", []):
		var kind := int(prop_data.get("kind", 0))
		var position: Vector2 = prop_data.get("position", Vector2.ZERO)
		var canopy := bool(prop_data.get("canopy", kind in [0, 1, 5]))
		_add_tomb_prop(kind, position, canopy)
		match str(prop_data.get("shape", "")):
			"circle": _add_tomb_circle_obstacle(position + prop_data.get("collision_offset", Vector2.ZERO), float(prop_data.get("radius", 22.0)))
			"rect": _add_tomb_rect_obstacle(position + prop_data.get("collision_offset", Vector2(0, -8)), prop_data.get("size", Vector2(88, 34)))
	for brazier_position: Vector2 in profile.get("braziers", []):
		_add_tomb_prop(2, brazier_position, true)
		_add_tomb_light(brazier_position + Vector2(0, -54))
	if str(profile.get("coordinate_projection", "")) == "isometric_64x32_full_size":
		_add_dungeon_map_boundaries(profile)


func _build_orc_tomb_environment() -> void:
	_build_dungeon_profile(environment_profile())


func _add_prop(kind: int, foot_position: Vector2, canopy: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = BICH_PROP_ATLAS
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(kind * 96, 0), BICH_PROP_SIZE)
	sprite.centered = false
	sprite.position = foot_position - Vector2(48, 118)
	sprite.z_as_relative = false
	sprite.z_index = -5
	add_child(sprite)
	_environment_nodes.append(sprite)
	if canopy:
		var crown := Sprite2D.new()
		crown.texture = BICH_PROP_ATLAS
		crown.region_enabled = true
		crown.region_rect = Rect2(Vector2(kind * 96, 0), Vector2(96, 86))
		crown.centered = false
		crown.position = foot_position - Vector2(48, 118)
		crown.z_as_relative = false
		crown.z_index = 5
		add_child(crown)
		_environment_nodes.append(crown)


func _add_tomb_prop(kind: int, foot_position: Vector2, canopy: bool) -> void:
	var prop_texture: Texture2D = ORC_TOMB_PROP_ATLAS
	var override_path := str(environment_profile().get("prop_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		prop_texture = load(override_path) as Texture2D
	elif uses_mine_art():
		prop_texture = MINE_PROP_ATLAS
	elif uses_wooma_temple_art():
		prop_texture = WOOMA_TEMPLE_PROP_ATLAS
	elif uses_wooma_forest_art():
		prop_texture = WOOMA_FOREST_PROP_ATLAS
	elif uses_wooma_cave_art():
		prop_texture = WOOMA_CAVE_PROP_ATLAS
	elif uses_snake_valley_art():
		prop_texture = SNAKE_VALLEY_PROP_ATLAS
	elif uses_snake_mine_art():
		prop_texture = SNAKE_MINE_PROP_ATLAS
	var sprite := Sprite2D.new()
	sprite.texture = prop_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(kind * 96, 0), ORC_TOMB_PROP_SIZE)
	sprite.centered = false
	sprite.position = foot_position - Vector2(48, 118)
	sprite.z_as_relative = false
	sprite.z_index = -5
	add_child(sprite)
	_environment_nodes.append(sprite)
	if canopy:
		var foreground := Sprite2D.new()
		foreground.texture = prop_texture
		foreground.region_enabled = true
		foreground.region_rect = Rect2(Vector2(kind * 96, 0), Vector2(96, 86))
		foreground.centered = false
		foreground.position = foot_position - Vector2(48, 118)
		foreground.z_as_relative = false
		foreground.z_index = 5
		add_child(foreground)
		_environment_nodes.append(foreground)


func _add_tomb_light(position: Vector2) -> void:
	var light_texture: Texture2D = ORC_TOMB_FIRE_GLOW
	var override_path := str(environment_profile().get("light_texture_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		light_texture = load(override_path) as Texture2D
	elif uses_mine_art():
		light_texture = MINE_LAMP_GLOW
	elif uses_wooma_temple_art():
		light_texture = WOOMA_TEMPLE_FIRE_GLOW
	elif uses_wooma_cave_art():
		light_texture = WOOMA_CAVE_GLOW
	elif uses_snake_mine_art():
		light_texture = SNAKE_MINE_GLOW
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
	add_child(glow)
	_environment_nodes.append(glow)
	var light := PointLight2D.new()
	light.texture = light_texture
	light.position = position
	light.texture_scale = 2.0
	light.energy = 0.75
	light.color = Color(1.0, 0.52, 0.22)
	light.z_as_relative = false
	light.z_index = -3
	add_child(light)
	_environment_nodes.append(light)


func _add_circle_obstacle(position: Vector2, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	_add_static_body(position, shape)
	_bich_collision_shapes.append({"kind": "circle", "position": position, "radius": radius})


func _add_rect_obstacle(position: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	_add_static_body(position, shape)
	_bich_collision_shapes.append({"kind": "rect", "position": position, "size": size})


func _add_bich_map_boundaries(profile: Dictionary) -> void:
	var corners: PackedVector2Array = profile.get("world_corners", PackedVector2Array())
	if corners.size() != 4:
		return
	for index in range(4):
		var start := corners[index]
		var finish := corners[(index + 1) % 4]
		var shape := SegmentShape2D.new()
		shape.a = start
		shape.b = finish
		_add_static_body(Vector2.ZERO, shape)
		_bich_collision_shapes.append({"kind": "segment", "start": start, "finish": finish})


func _add_dungeon_map_boundaries(profile: Dictionary) -> void:
	var corners: PackedVector2Array = profile.get("world_corners", PackedVector2Array())
	if corners.size() != 4:
		return
	for index in range(4):
		var start := corners[index]
		var finish := corners[(index + 1) % 4]
		var shape := SegmentShape2D.new()
		shape.a = start
		shape.b = finish
		_add_static_body(Vector2.ZERO, shape)
		_tomb_collision_shapes.append({"kind": "segment", "start": start, "finish": finish})


func _load_source_collision_mask(profile: Dictionary) -> void:
	_source_mask_path = str(profile.get("collision_mask_path", ""))
	if _source_mask_path.is_empty() or not ResourceLoader.exists(_source_mask_path):
		return
	var texture := load(_source_mask_path) as Texture2D
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
	var source_size: Vector2i = profile.get("source_size", Vector2i.ZERO)
	if source_size == Vector2i.ZERO:
		return
	var atlas: Texture2D = GOTHIC_BICH_GROUND_ATLAS if uses_bich_art() else ORC_TOMB_GROUND_ATLAS
	var override_path := str(profile.get("ground_atlas_override", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		atlas = load(override_path) as Texture2D
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
	add_child(ground)
	_environment_nodes.append(ground)
	_full_ground_ready = true


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
	if _active_map_id() == 4 and not _gothic_camp_layout.is_empty():
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


func _add_tomb_circle_obstacle(position: Vector2, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	_add_static_body(position, shape)
	_tomb_collision_shapes.append({"kind": "circle", "position": position, "radius": radius})


func _add_tomb_rect_obstacle(position: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	_add_static_body(position, shape)
	_tomb_collision_shapes.append({"kind": "rect", "position": position, "size": size})


func _add_static_body(position: Vector2, shape: Shape2D) -> void:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_environment_nodes.append(body)


func _orc_tomb_map_id() -> int:
	var map_id := int(zone_data.get("mapId", -1))
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
		return 4
	return _orc_tomb_map_id()


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
