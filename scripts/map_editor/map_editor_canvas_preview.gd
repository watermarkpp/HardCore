class_name MapEditorCanvasPreview
extends Control

const VIRTUAL_TILE_DRAW_LIMIT := 2048

signal paint_requested(tile: Vector2i, asset_id: String)
signal tile_hovered(tile: Vector2i)
signal manual_collision_tile_clicked(tile: Vector2i)
signal manual_collision_erase_requested(tile: Vector2i)
signal manual_collision_cancelled
signal semantic_tile_clicked(tile: Vector2i)
signal lasso_context_requested(tiles: Array, screen_position: Vector2)
signal erase_tile_requested(tile: Vector2i)
signal selectable_selected(selectable_id: String, additive: bool)
signal selectable_move_requested(selectable_id: String, delta_tile: Vector2i)
signal selectable_delete_requested(selectable_id: String)
signal selectable_context_requested(selectable_id: String, screen_position: Vector2)

var document: Dictionary = {}
var show_grid := true
var grid_interval := 1
var _ground_texture: Texture2D
var _texture_cache := {}
var _paint_overrides := {}
var _baked_ground_chunks: Array[Dictionary] = []
var _ground_overlay_keys := {}
var _cached_map_id := ""
var selected_brush_asset_id := "ground.dark_grass.001"
var selected_placement_layer := "ground_base"
var interaction_mode := "place"
var show_walkable_preview := false
var _blocked_tiles := {}
var _draw_offset := Vector2.ZERO
var _draw_scale := 1.0
var _last_drag_tile := Vector2i(-1, -1)
var _hover_tile := Vector2i(-1, -1)
var _view_pan := Vector2.ZERO
var _zoom_multiplier := 1.0
var _panning := false
var _region_paint_mode := false
var _lasso_drawing := false
var _lasso_points := PackedVector2Array()
var _selected_lasso_points := PackedVector2Array()
var _selected_lasso_tiles: Array[Vector2i] = []
var _manual_collision_shape := "rect"
var _manual_collision_start := Vector2i(-1, -1)
var _manual_collision_points: Array[Vector2i] = []
var hovered_selectable_id := ""
var selected_selectable_id := ""


func set_document(value: Dictionary) -> void:
	var next_map_id := str(value.get("map_id", ""))
	if next_map_id != _cached_map_id:
		_cached_map_id = next_map_id
		_baked_ground_chunks.clear()
		_ground_overlay_keys.clear()
		_paint_overrides.clear()
		_reset_transient_document_state()
	document = value
	if show_walkable_preview:
		_blocked_tiles = MapEditorCollisionService.build_walkability(document).get("blocked_tiles", {}) if not document.is_empty() else {}
	if _ground_texture == null:
		_ground_texture = load("res://assets/art/maps/_shared/terrain/old_grass/ground_old_grass_001.png") as Texture2D
	queue_redraw()


func reset_for_document_open() -> void:
	_baked_ground_chunks.clear()
	_ground_overlay_keys.clear()
	_paint_overrides.clear()
	_reset_transient_document_state()


func _reset_transient_document_state() -> void:
	_blocked_tiles.clear()
	_last_drag_tile = Vector2i(-1, -1)
	_hover_tile = Vector2i(-1, -1)
	_view_pan = Vector2.ZERO
	_zoom_multiplier = 1.0
	_panning = false
	_region_paint_mode = false
	_lasso_drawing = false
	_lasso_points.clear()
	_selected_lasso_points.clear()
	_selected_lasso_tiles.clear()
	_manual_collision_start = Vector2i(-1, -1)
	_manual_collision_points.clear()
	hovered_selectable_id = ""
	selected_selectable_id = ""


func set_ground_state(state: Dictionary) -> void:
	var next_overrides := MapEditorGroundService.tile_overrides(state)
	if _baked_ground_chunks.is_empty():
		_paint_overrides = next_overrides
		_rebuild_baked_ground_cache()
		_ground_overlay_keys.clear()
	else:
		for key: String in next_overrides:
			if str(_paint_overrides.get(key, "")) != str(next_overrides[key]):
				_ground_overlay_keys[key] = true
		for key: String in _paint_overrides:
			if not next_overrides.has(key):
				_ground_overlay_keys[key] = true
		_paint_overrides = next_overrides
	queue_redraw()


func _rebuild_baked_ground_cache() -> void:
	if document.is_empty():
		return
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.get("ok", false):
		return
	var root := MapEditorGroundService.workspace_root(document)
	var expected_fill_asset_id := str(document.get("ground", {}).get("blank_fill_asset_id", ""))
	for chunk: Dictionary in initialized.manifest.get("chunks", []):
		var relative := str(chunk.get("preview_png", ""))
		var rect: Array = chunk.get("rect_px", [])
		if relative.is_empty() or rect.size() != 4:
			continue
		if expected_fill_asset_id.is_empty() and not chunk.has("baked_default_fill_asset_id"):
			continue
		if chunk.has("baked_default_fill_asset_id") and str(chunk.get("baked_default_fill_asset_id", "")) != expected_fill_asset_id:
			continue
		var absolute := root.path_join(relative)
		var image := Image.load_from_file(ProjectSettings.globalize_path(absolute))
		if image == null:
			continue
		_baked_ground_chunks.append({"rect": Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])), "texture": ImageTexture.create_from_image(image)})


func reload_ground_state(state: Dictionary) -> void:
	_baked_ground_chunks.clear()
	_ground_overlay_keys.clear()
	_paint_overrides.clear()
	set_ground_state(state)


func set_selected_brush(asset_id: String) -> void:
	selected_brush_asset_id = asset_id
	queue_redraw()


func set_placement_layer(layer: String) -> void:
	selected_placement_layer = layer
	queue_redraw()


func set_interaction_mode(mode: String) -> void:
	interaction_mode = mode
	_last_drag_tile = Vector2i(-1, -1)
	if mode != "manual_collision":
		_manual_collision_start = Vector2i(-1, -1)
		_manual_collision_points.clear()
	queue_redraw()


func set_manual_collision_draft(shape: String, start: Vector2i, points: Array[Vector2i]) -> void:
	_manual_collision_shape = shape
	_manual_collision_start = start
	_manual_collision_points = points.duplicate()
	queue_redraw()


func set_region_paint_mode(enabled: bool) -> void:
	_region_paint_mode = enabled
	_lasso_drawing = false
	_lasso_points.clear()
	_selected_lasso_points.clear()
	_selected_lasso_tiles.clear()
	queue_redraw()


func activate_normal_placement(asset_id: String) -> void:
	interaction_mode = "place"
	_region_paint_mode = false
	_lasso_drawing = false
	_lasso_points.clear()
	_selected_lasso_points.clear()
	_selected_lasso_tiles.clear()
	_last_drag_tile = Vector2i(-1, -1)
	if not asset_id.is_empty(): selected_brush_asset_id = asset_id
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func set_walkability_preview(result: Dictionary, enabled: bool) -> void:
	show_walkable_preview = enabled
	_blocked_tiles = result.get("blocked_tiles", {}) if enabled else {}
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if document.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if interaction_mode == "select":
			var context_id := _hit_selectable(event.position)
			if not context_id.is_empty():
				selected_selectable_id = context_id
				selectable_selected.emit(context_id, false)
				selectable_context_requested.emit(context_id, event.global_position)
				queue_redraw()
		elif interaction_mode in ["manual_collision", "manual_collision_erase", "manual_collision_erase_whole"]:
			manual_collision_cancelled.emit()
		elif interaction_mode == "place" and _region_paint_mode and not _selected_lasso_tiles.is_empty() and Geometry2D.is_point_in_polygon(event.position, _selected_lasso_points):
			lasso_context_requested.emit(_selected_lasso_tiles.duplicate(), event.global_position)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		_zoom_multiplier = clampf(_zoom_multiplier * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.65, 4.0)
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if interaction_mode == "select":
				selected_selectable_id = _hit_selectable(event.position)
				selectable_selected.emit(selected_selectable_id,event.ctrl_pressed)
				queue_redraw(); accept_event(); return
			_last_drag_tile = Vector2i(-1, -1)
			if interaction_mode == "place" and _region_paint_mode:
				_lasso_drawing = true
				_lasso_points = PackedVector2Array([event.position])
				_selected_lasso_points.clear()
				_selected_lasso_tiles.clear()
				accept_event()
				return
			if interaction_mode == "manual_collision":
				var manual_tile := screen_to_tile(event.position)
				if manual_tile.x >= 0:
					_hover_tile = manual_tile
					if _manual_collision_shape == "cell":
						_last_drag_tile = manual_tile
					manual_collision_tile_clicked.emit(manual_tile)
					queue_redraw()
			elif interaction_mode in ["manual_collision_erase", "manual_collision_erase_whole"]:
				var erase_collision_tile := screen_to_tile(event.position)
				if erase_collision_tile.x >= 0:
					_hover_tile = erase_collision_tile
					_last_drag_tile = erase_collision_tile
					manual_collision_erase_requested.emit(erase_collision_tile)
					queue_redraw()
			elif interaction_mode == "semantic":
				var semantic_tile := screen_to_tile(event.position)
				if semantic_tile.x >= 0: semantic_tile_clicked.emit(semantic_tile)
			elif interaction_mode == "erase":
				var erase_tile := screen_to_tile(event.position)
				if erase_tile.x >= 0: erase_tile_requested.emit(erase_tile)
			else:
				_request_paint(event.position)
			accept_event()
		elif interaction_mode == "place" and _region_paint_mode and _lasso_drawing:
			_lasso_drawing = false
			if _lasso_points.size() >= 3:
				_selected_lasso_points = _lasso_points.duplicate()
				_selected_lasso_tiles = _tiles_inside_lasso(_selected_lasso_points)
			_lasso_points.clear()
			queue_redraw()
			accept_event()
		return
	if event is InputEventMouseMotion:
		if _panning:
			_view_pan += event.relative
			queue_redraw()
			accept_event()
			return
		if _lasso_drawing:
			if _lasso_points.is_empty() or _lasso_points[-1].distance_to(event.position) >= 3.0:
				_lasso_points.append(event.position)
				queue_redraw()
			accept_event()
			return
		var tile := screen_to_tile(event.position)
		var hover_changed := tile != _hover_tile
		_hover_tile = tile
		if interaction_mode == "select":
			var next_hovered := _hit_selectable(event.position)
			hover_changed = hover_changed or next_hovered != hovered_selectable_id
			hovered_selectable_id = next_hovered
		# Placement ghost only changes when it enters a different logical tile.
		# Selection mode redraws only when the hit target changes.
		if hover_changed:
			queue_redraw()
		if tile.x >= 0:
			tile_hovered.emit(tile)
		if interaction_mode == "place" and not _region_paint_mode and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_request_paint(event.position)
		elif interaction_mode == "erase" and event.button_mask & MOUSE_BUTTON_MASK_LEFT and tile.x >= 0 and tile != _last_drag_tile:
			_last_drag_tile = tile
			erase_tile_requested.emit(tile)
		elif interaction_mode == "manual_collision" and _manual_collision_shape == "cell" and event.button_mask & MOUSE_BUTTON_MASK_LEFT and tile.x >= 0 and tile != _last_drag_tile:
			_last_drag_tile = tile
			manual_collision_tile_clicked.emit(tile)
		elif interaction_mode in ["manual_collision_erase", "manual_collision_erase_whole"] and event.button_mask & MOUSE_BUTTON_MASK_LEFT and tile.x >= 0 and tile != _last_drag_tile:
			_last_drag_tile = tile
			manual_collision_erase_requested.emit(tile)
	if event is InputEventKey and event.pressed and not event.echo and interaction_mode=="select" and not selected_selectable_id.is_empty():
		var delta:Vector2i = {KEY_UP:Vector2i(0,-1),KEY_DOWN:Vector2i(0,1),KEY_LEFT:Vector2i(-1,0),KEY_RIGHT:Vector2i(1,0)}.get(event.keycode,Vector2i.ZERO)
		if delta!=Vector2i.ZERO: selectable_move_requested.emit(selected_selectable_id,delta); accept_event()
		elif event.keycode==KEY_DELETE: selectable_delete_requested.emit(selected_selectable_id); accept_event()


func _tiles_inside_lasso(points: PackedVector2Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if points.size() < 3:
		return result
	var raw_size: Array = document.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var min_tile := Vector2i(design_size.x - 1, design_size.y - 1)
	var max_tile := Vector2i.ZERO
	for point: Vector2 in points:
		var tile := screen_to_tile(point)
		if tile.x >= 0:
			min_tile = Vector2i(mini(min_tile.x, tile.x), mini(min_tile.y, tile.y))
			max_tile = Vector2i(maxi(max_tile.x, tile.x), maxi(max_tile.y, tile.y))
	min_tile = Vector2i(maxi(0, min_tile.x - 2), maxi(0, min_tile.y - 2))
	max_tile = Vector2i(mini(design_size.x - 1, max_tile.x + 2), mini(design_size.y - 1, max_tile.y + 2))
	for y in range(min_tile.y, max_tile.y + 1):
		for x in range(min_tile.x, max_tile.x + 1):
			var center := _draw_offset + MapEditorCoordinate.tile_to_ground_px(Vector2(x, y), design_size) * _draw_scale
			if Geometry2D.is_point_in_polygon(center, points):
				result.append(Vector2i(x, y))
	return result


func screen_to_tile(screen_position: Vector2) -> Vector2i:
	if document.is_empty() or _draw_scale <= 0.0:
		return Vector2i(-1, -1)
	var raw_size: Array = document.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var ground_px := (screen_position - _draw_offset) / _draw_scale
	var tile := MapEditorCoordinate.ground_px_to_tile(ground_px, design_size).round()
	var result := Vector2i(int(tile.x), int(tile.y))
	return result if MapEditorCoordinate.contains_tile(result, design_size) else Vector2i(-1, -1)


func _request_paint(screen_position: Vector2) -> void:
	var tile := screen_to_tile(screen_position)
	if tile.x < 0 or tile == _last_drag_tile:
		return
	_last_drag_tile = tile
	paint_requested.emit(tile, selected_brush_asset_id)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("17191d"), true)
	if document.is_empty():
		_draw_center_text("新建或打开地图")
		return
	var raw_size: Array = document.get("design", {}).get("design_size", [64, 64])
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var image_size := Vector2(MapEditorCoordinate.ground_image_size(design_size))
	var available := Vector2(maxf(size.x - 40.0, 1.0), maxf(size.y - 40.0, 1.0))
	var fit_scale := minf(available.x / image_size.x, available.y / image_size.y)
	# A 256x256 map must open as an editable working view, not as a full-map
	# thumbnail.  0.28 yields ~18px wide logical tiles before user zoom.
	var scale_factor := maxf(fit_scale, 0.28) * _zoom_multiplier
	var offset := (size - image_size * scale_factor) * 0.5 + _view_pan
	_draw_offset = offset
	_draw_scale = scale_factor
	_draw_virtual_ground(design_size, offset, scale_factor)
	var corners := PackedVector2Array([
		MapEditorCoordinate.tile_to_ground_px(Vector2(0, 0), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(design_size.x, 0), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(design_size.x, design_size.y), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(0, design_size.y), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(0, 0), design_size),
	])
	for i in range(corners.size() - 1):
		draw_line(offset + corners[i] * scale_factor, offset + corners[i + 1] * scale_factor, Color("d7aa62"), 2.0)
	if show_grid:
		var interval := maxi(grid_interval, 1)
		if max(design_size.x, design_size.y) > 160:
			interval = maxi(interval, 4)
		elif max(design_size.x, design_size.y) > 80:
			interval = maxi(interval, 2)
		for line: PackedVector2Array in MapEditorGridService.visible_grid_lines(design_size, interval):
			draw_line(offset + line[0] * scale_factor, offset + line[1] * scale_factor, Color(0.32, 0.43, 0.47, 0.42), 1.0)
	_draw_instances(design_size, offset, scale_factor)
	_draw_selection_overlays(design_size,offset,scale_factor)
	_draw_blocked_tiles(design_size, offset, scale_factor)
	_draw_ghost(design_size, offset, scale_factor)
	_draw_semantics(design_size, offset, scale_factor)
	_draw_lasso_selection(design_size, offset, scale_factor)
	_draw_manual_collision_draft(design_size, offset, scale_factor)


func _draw_manual_collision_draft(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	if interaction_mode in ["manual_collision_erase", "manual_collision_erase_whole"]:
		var erase_color := Color("ff6b5f")
		var erase_label := "单格擦除碰撞" if interaction_mode == "manual_collision_erase" else "整块擦除碰撞"
		draw_string(ThemeDB.fallback_font, Vector2(18, 28), erase_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, erase_color)
		if _hover_tile.x >= 0:
			var tile_outline := PackedVector2Array()
			for tile_point: Vector2 in [Vector2(_hover_tile), Vector2(_hover_tile.x + 1, _hover_tile.y), Vector2(_hover_tile) + Vector2.ONE, Vector2(_hover_tile.x, _hover_tile.y + 1), Vector2(_hover_tile)]:
				tile_outline.append(offset + MapEditorCoordinate.tile_to_ground_px(tile_point, design_size) * scale_factor)
			draw_colored_polygon(tile_outline, Color(erase_color, 0.24))
			draw_polyline(tile_outline, erase_color, 3.0)
		return
	if interaction_mode != "manual_collision":
		return
	var color := Color("ffb84d")
	draw_string(ThemeDB.fallback_font, Vector2(18, 28), "手工碰撞：%s" % {"cell":"单格", "rect":"矩形", "ellipse":"椭圆", "polygon":"多边形"}.get(_manual_collision_shape, _manual_collision_shape), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if _manual_collision_shape == "cell":
		if _hover_tile.x >= 0:
			var cell_outline := PackedVector2Array()
			for tile_point: Vector2 in [Vector2(_hover_tile), Vector2(_hover_tile.x + 1, _hover_tile.y), Vector2(_hover_tile) + Vector2.ONE, Vector2(_hover_tile.x, _hover_tile.y + 1), Vector2(_hover_tile)]:
				cell_outline.append(offset + MapEditorCoordinate.tile_to_ground_px(tile_point, design_size) * scale_factor)
			draw_colored_polygon(cell_outline, Color(color, 0.24))
			draw_polyline(cell_outline, color, 3.0)
		return
	if _manual_collision_shape == "polygon":
		var screen_points := PackedVector2Array()
		for tile: Vector2i in _manual_collision_points:
			screen_points.append(offset + MapEditorCoordinate.tile_to_ground_px(Vector2(tile), design_size) * scale_factor)
		if _hover_tile.x >= 0 and not screen_points.is_empty():
			screen_points.append(offset + MapEditorCoordinate.tile_to_ground_px(Vector2(_hover_tile), design_size) * scale_factor)
		for point: Vector2 in screen_points:
			draw_circle(point, 5.0, color)
		if screen_points.size() >= 2:
			draw_polyline(screen_points, color, 3.0)
		return
	if _manual_collision_start.x < 0:
		return
	var end := _hover_tile if _hover_tile.x >= 0 else _manual_collision_start
	var minimum := Vector2i(mini(_manual_collision_start.x, end.x), mini(_manual_collision_start.y, end.y))
	var maximum := Vector2i(maxi(_manual_collision_start.x, end.x) + 1, maxi(_manual_collision_start.y, end.y) + 1)
	var outline := PackedVector2Array()
	if _manual_collision_shape == "ellipse":
		var center := (Vector2(minimum) + Vector2(maximum)) * 0.5
		var radius := (Vector2(maximum) - Vector2(minimum)) * 0.5
		for step in 33:
			var angle := TAU * float(step) / 32.0
			var tile_point := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
			outline.append(offset + MapEditorCoordinate.tile_to_ground_px(tile_point, design_size) * scale_factor)
	else:
		for tile_point: Vector2 in [Vector2(minimum), Vector2(maximum.x, minimum.y), Vector2(maximum), Vector2(minimum.x, maximum.y), Vector2(minimum)]:
			outline.append(offset + MapEditorCoordinate.tile_to_ground_px(tile_point, design_size) * scale_factor)
	if outline.size() >= 3:
		draw_colored_polygon(outline, Color(color, 0.18))
		draw_polyline(outline, color, 3.0)


func _draw_lasso_selection(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	var points := _lasso_points if _lasso_drawing else _selected_lasso_points
	if points.size() >= 2:
		for index in range(points.size() - 1):
			draw_line(points[index], points[index + 1], Color("63d7ff"), 2.0)
		if not _lasso_drawing and points.size() >= 3:
			draw_line(points[-1], points[0], Color("63d7ff"), 2.0)
			draw_colored_polygon(points, Color(0.22, 0.68, 0.92, 0.14))
	if not _selected_lasso_tiles.is_empty():
		for tile: Vector2i in _selected_lasso_tiles:
			var center := offset + MapEditorCoordinate.tile_to_ground_px(Vector2(tile.x, tile.y), design_size) * scale_factor
			draw_circle(center, maxf(1.5, 2.5 * scale_factor), Color(0.35, 0.9, 1.0, 0.8))


func _draw_ghost(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	if interaction_mode != "place" or _region_paint_mode or _hover_tile.x < 0 or selected_brush_asset_id.is_empty():
		return
	var ghost := MapEditorGhostPreview.build(document, selected_brush_asset_id, _hover_tile, selected_placement_layer)
	var polygon: PackedVector2Array = ghost.polygon_ground_px
	var screen_polygon := PackedVector2Array()
	for point in polygon:
		screen_polygon.append(offset + point * scale_factor)
	var color: Color = ghost.color
	draw_colored_polygon(screen_polygon, Color(color, 0.20))
	for index in screen_polygon.size():
		draw_line(screen_polygon[index], screen_polygon[(index + 1) % screen_polygon.size()], color, 2.0)


func _draw_instances(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	for layer_name: String in ["terrain_base", "terrain_front", "object_base", "object_front"]:
		for instance: Dictionary in document.get("layers", {}).get(layer_name, []):
			if not instance.has("asset_id"):
				continue
			var asset := MapAssetCatalogService.find_asset(str(instance.asset_id))
			var texture := _texture_for_asset(str(instance.asset_id))
			if texture == null:
				continue
			var geometry := instance_visual_geometry(instance, design_size, offset, scale_factor, texture.get_size(), asset)
			draw_set_transform(geometry.center, geometry.rotation, geometry.visual_scale)
			draw_texture(texture, -geometry.anchor)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hit_selectable(screen_position: Vector2) -> String:
	var raw_size: Array=document.design.design_size; var design_size:=Vector2i(int(raw_size[0]),int(raw_size[1]))
	var all:=MapEditorInstanceService.all_instances(document); all.reverse()
	for instance: Dictionary in all:
		if bool(instance.get("selection_locked",false)): continue
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		var texture:=_texture_for_asset(str(instance.get("asset_id",""))); if texture==null: continue
		var geometry := instance_visual_geometry(instance, design_size, _draw_offset, _draw_scale, texture.get_size(), asset)
		var hit_rect: Rect2 = geometry.rect.grow(4.0)
		if hit_rect.has_point(screen_position): return str(instance.instance_id)
	for entry: Dictionary in MapEditorGameplaySemanticService.all_entries(document):
		var raw:Array=entry.get("tile",[0,0]); var center:=_draw_offset+MapEditorCoordinate.tile_to_ground_px(Vector2(raw[0],raw[1]),design_size)*_draw_scale
		if center.distance_to(screen_position)<=14.0:return str(entry.get("semantic_id",""))
	return ""


func _draw_selection_overlays(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var iid:=str(instance.get("instance_id","")); if iid!=hovered_selectable_id and iid!=selected_selectable_id:continue
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		var texture:=_texture_for_asset(str(instance.get("asset_id",""))); if texture==null:continue
		var geometry := instance_visual_geometry(instance, design_size, offset, scale_factor, texture.get_size(), asset)
		var visual_rect: Rect2 = geometry.rect
		var color:=Color("ffe16b") if iid==selected_selectable_id else Color("65d8ff")
		draw_rect(visual_rect,color,false,3.0)
		# Pixel centre is explicit so the selected image and its box cannot drift.
		var pixel_center:=visual_rect.get_center()
		draw_line(pixel_center-Vector2(6,0),pixel_center+Vector2(6,0),color,2.0)
		draw_line(pixel_center-Vector2(0,6),pixel_center+Vector2(0,6),color,2.0)


static func instance_visual_geometry(instance: Dictionary, design_size: Vector2i, draw_offset: Vector2, draw_scale: float, texture_size: Vector2, asset := {}) -> Dictionary:
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	var offset_px: Array = instance.get("offset_px", [0, 0])
	var anchor: Array = instance.get("anchor_px", instance.get("placement_anchor_px", asset.get("anchor_px", [0, 0])))
	var instance_scale: Array = instance.get("scale", [1.0, 1.0])
	var foot := Vector2(float(tile[0]) + float(footprint[0]) * 0.5, float(tile[1]) + float(footprint[1]) * 0.5)
	var ground_center := MapEditorCoordinate.tile_to_ground_px(foot, design_size) + Vector2(float(offset_px[0]), float(offset_px[1]))
	var center := draw_offset + ground_center * draw_scale
	var visual_scale := Vector2(float(instance_scale[0]), float(instance_scale[1])) * draw_scale
	var anchor_vector := Vector2(float(anchor[0]), float(anchor[1]))
	var top_left := center - anchor_vector * visual_scale
	return {
		"center": center,
		"anchor": anchor_vector,
		"visual_scale": visual_scale,
		"rotation": deg_to_rad(float(instance.get("rotation_deg", 0.0))),
		"rect": Rect2(top_left, texture_size * visual_scale),
	}


func _draw_blocked_tiles(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	if not show_walkable_preview:
		return
	for key: String in _blocked_tiles:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var center := MapEditorCoordinate.tile_to_ground_px(tile, design_size)
		var polygon := PackedVector2Array([
			offset + (center + Vector2(0, -16)) * scale_factor,
			offset + (center + Vector2(32, 0)) * scale_factor,
			offset + (center + Vector2(0, 16)) * scale_factor,
			offset + (center + Vector2(-32, 0)) * scale_factor,
		])
		draw_colored_polygon(polygon, Color(0.85, 0.15, 0.12, 0.42))


func _draw_semantics(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	for entry: Dictionary in MapEditorGameplaySemanticService.all_entries(document):
		var raw_tile: Array = entry.get("tile", [0, 0])
		var center := offset + MapEditorCoordinate.tile_to_ground_px(Vector2(int(raw_tile[0]), int(raw_tile[1])), design_size) * scale_factor
		var kind := str(entry.get("kind", ""))
		var colors := {"npc": Color("7fc8ff"), "monster_spawn": Color("d96868"), "boss_spawn": Color("f29c38"), "door": Color("bd8eff"), "safe_area": Color("61d69b"), "light": Color("ffe08a"), "region_trigger": Color("6ee7df")}
		var color: Color = colors.get(kind, Color.WHITE)
		var radius := maxf(8.0, 11.0 * scale_factor)
		if kind=="safe_area" and str(entry.get("shape","circle"))=="polygon":
			var safe_polygon:=PackedVector2Array()
			for point:Variant in entry.get("polygon_tiles",[]):
				if point is Array and point.size()==2:safe_polygon.append(offset+MapEditorCoordinate.tile_to_ground_px(Vector2(float(point[0]),float(point[1])),design_size)*scale_factor)
			if safe_polygon.size()>=3:
				draw_colored_polygon(safe_polygon,Color(color,0.16));draw_polyline(PackedVector2Array(Array(safe_polygon)+[safe_polygon[0]]),color,2.0)
		if kind in ["safe_area", "light", "region_trigger", "monster_spawn", "boss_spawn"]:
			if not (kind=="safe_area" and str(entry.get("shape","circle"))=="polygon"):
				var area_radius := maxf(radius, float(entry.get("radius_tiles", 1)) * 24.0 * scale_factor)
				draw_arc(center, area_radius, 0.0, TAU, 32, Color(color, 0.9), 2.0)
		if kind == "npc":
			draw_circle(center + Vector2(0,-radius*.45), radius*.38, Color(color,0.95))
			draw_rect(Rect2(center+Vector2(-radius*.45,-radius*.05),Vector2(radius*.9,radius)),Color(color,0.9),true)
		elif kind in ["monster_spawn","boss_spawn"]:
			var diamond := PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),center+Vector2(0,radius),center+Vector2(-radius,0)])
			draw_colored_polygon(diamond,Color(color,0.9)); draw_polyline(PackedVector2Array([diamond[0],diamond[1],diamond[2],diamond[3],diamond[0]]),Color("101216"),2.0)
		elif kind == "door":
			draw_rect(Rect2(center-Vector2(radius*.8,radius),Vector2(radius*1.6,radius*2)),Color(color,0.25),true)
			draw_arc(center,radius,PI,TAU,16,Color(color,1.0),3.0)
		else:
			draw_circle(center, radius, Color(color, 0.85)); draw_arc(center, radius, 0.0, TAU, 12, Color("101216"), 1.25)
		var display_name := str(entry.get("display_name", ""))
		if display_name.is_empty():
			display_name = {"npc":"NPC","monster_spawn":"怪物刷新","boss_spawn":"Boss刷新","door":"地图出口","safe_area":"安全区","light":"光效","region_trigger":"触发区域"}.get(kind,"功能点")
		draw_string(ThemeDB.fallback_font, center+Vector2(radius+3,4), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		var sid:=str(entry.get("semantic_id",""))
		if sid==hovered_selectable_id or sid==selected_selectable_id:
			var highlight:=Color("ffe16b") if sid==selected_selectable_id else Color("65d8ff")
			draw_rect(Rect2(center-Vector2(15,20),Vector2(30,40)),highlight,false,3.0)
			draw_line(center+Vector2(-6,0),center+Vector2(6,0),highlight,2.0); draw_line(center+Vector2(0,-6),center+Vector2(0,6),highlight,2.0)


func _draw_virtual_ground(design_size: Vector2i, offset: Vector2, scale_factor: float) -> void:
	var corners := PackedVector2Array([
		MapEditorCoordinate.tile_to_ground_px(Vector2(0, 0), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(design_size.x, 0), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(design_size.x, design_size.y), design_size),
		MapEditorCoordinate.tile_to_ground_px(Vector2(0, design_size.y), design_size),
	])
	if not _baked_ground_chunks.is_empty():
		if not str(document.get("ground", {}).get("blank_fill_asset_id", "")).is_empty():
			var filled_polygon := PackedVector2Array()
			for point in corners:
				filled_polygon.append(offset + point * scale_factor)
			draw_colored_polygon(filled_polygon, Color("4d5a35"))
		draw_set_transform(offset, 0.0, Vector2(scale_factor, scale_factor))
		for chunk: Dictionary in _baked_ground_chunks:
			var rect: Rect2 = chunk.rect
			var screen_rect := Rect2(offset + rect.position * scale_factor, rect.size * scale_factor)
			if screen_rect.intersects(Rect2(Vector2.ZERO, size)):
				draw_texture(chunk.texture, rect.position)
		for key: String in _ground_overlay_keys:
			if not _paint_overrides.has(key):
				continue
			var parts := key.split(",")
			if parts.size() != 2:
				continue
			var tile := Vector2i(int(parts[0]), int(parts[1]))
			var center := MapEditorCoordinate.tile_to_ground_px(Vector2(tile.x, tile.y), design_size)
			if not _ground_tile_is_visible(center, offset, scale_factor):
				continue
			var texture := _texture_for_asset(str(_paint_overrides[key]))
			if texture != null:
				draw_texture_rect(texture, Rect2(center - Vector2(32, 16), Vector2(64, 32)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if not str(document.get("ground", {}).get("blank_fill_asset_id", "")).is_empty():
		var virtual_fill_polygon := PackedVector2Array()
		for point in corners:
			virtual_fill_polygon.append(offset + point * scale_factor)
		draw_colored_polygon(virtual_fill_polygon, Color("4d5a35"))
	# A virtual blank map is one flat base surface. Drawing one default texture
	# per logical tile made a 38x38 template issue 1,444 draw calls on every
	# mouse-wheel or hover redraw. Only sparse user paint operations are drawn
	# until the user explicitly bakes dirty chunks.
	draw_set_transform(offset, 0.0, Vector2(scale_factor, scale_factor))
	for key: String in _paint_overrides:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var center := MapEditorCoordinate.tile_to_ground_px(Vector2(tile.x, tile.y), design_size)
		if not _ground_tile_is_visible(center, offset, scale_factor):
			continue
		var texture := _texture_for_asset(str(_paint_overrides[key]))
		if texture != null:
			draw_texture_rect(texture, Rect2(center - Vector2(32, 16), Vector2(64, 32)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ground_tile_is_visible(ground_center: Vector2, offset: Vector2, scale_factor: float) -> bool:
	# The margin absorbs the 64x32 tile and avoids edge pop-in while zooming.
	var screen_center := offset + ground_center * scale_factor
	var margin := 48.0
	return screen_center.x >= -margin and screen_center.y >= -margin and screen_center.x <= size.x + margin and screen_center.y <= size.y + margin


func _texture_for_asset(asset_id: String) -> Texture2D:
	if _texture_cache.has(asset_id):
		return _texture_cache[asset_id]
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var raw_image:Variant=asset.get("image","")
	var image_path := "" if raw_image==null else str(raw_image)
	if image_path.is_empty():
		return _ground_texture
	var texture := load("res://" + image_path) as Texture2D
	_texture_cache[asset_id] = texture
	return texture


func _draw_center_text(text: String) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, (size - text_size) * 0.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("aeb7c2"))
