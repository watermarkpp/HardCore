class_name EquipmentCharacterPreview
extends Control

const PAPER_DOLL_MANIFEST := "res://assets/data/warrior_paper_doll_sources.json"
const PAPER_LAYER_SLOTS := ["衣服", "武器", "头盔"]
const ORIGINAL_CANVAS_SIZE := Vector2(168.0, 199.0)
const PREVIEW_SCALE := 1.22
const FOOT_STAGE_CENTER := Vector2(84.0, 181.0)
const FOOT_STAGE_RADII := Vector2(49.0, 13.5)

var _direction_row := 4
var _paper_mappings: Dictionary = {}
var _paper_layers: Array[Dictionary] = []
var _base_texture: Texture2D
var _hair_layer: Dictionary = {}
var _body_layer: Dictionary = {}
var _body_texture: Texture2D
var _weapon_texture: Texture2D
var _helmet_texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	custom_minimum_size = Vector2(230, 286)
	_load_paper_mappings()
	if not PlayerState.equipment_changed.is_connected(refresh):
		PlayerState.equipment_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _paper_mappings.is_empty():
		_load_paper_mappings()
	_paper_layers.clear()
	_body_layer.clear()
	_body_texture = null
	_weapon_texture = null
	_helmet_texture = null
	for slot: String in PAPER_LAYER_SLOTS:
		var equipped: Variant = PlayerState.equipment.get(slot, {})
		if not equipped is Dictionary or equipped.is_empty():
			continue
		var mapping_value: Variant = _paper_mappings.get(str(equipped.get("name", "")), {})
		if not mapping_value is Dictionary or mapping_value.is_empty():
			continue
		var path := str(mapping_value.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var layer: Dictionary = mapping_value.duplicate(true)
		layer["texture"] = texture
		layer["equipmentSlot"] = slot
		_paper_layers.append(layer)
		if slot == "衣服":
			_body_layer = layer
			_body_texture = texture
		elif slot == "武器":
			_weapon_texture = texture
		elif slot == "头盔":
			_helmet_texture = texture
	queue_redraw()


func _draw() -> void:
	if _base_texture == null:
		return
	var scaled_canvas := ORIGINAL_CANVAS_SIZE * PREVIEW_SCALE
	# Put the original 199px client canvas near the bottom of the available
	# preview.  This uses the space below the character while preserving every
	# original layer coordinate.
	var origin := Vector2((size.x - scaled_canvas.x) * 0.5, size.y - scaled_canvas.y - 6.0)
	# A flattened stage sits under the character's feet. The previous circle
	# read as a misplaced halo and did not match the paper-doll perspective.
	var stage_center := origin + FOOT_STAGE_CENTER * PREVIEW_SCALE
	var stage_radii := FOOT_STAGE_RADII * PREVIEW_SCALE
	var shadow_points := _ellipse_points(stage_center + Vector2(0, 4), stage_radii + Vector2(5, 3))
	draw_colored_polygon(shadow_points, Color(0.008, 0.005, 0.004, 0.72))
	var stage_points := _ellipse_points(stage_center, stage_radii)
	draw_colored_polygon(stage_points, Color(0.055, 0.032, 0.018, 0.92))
	var stage_outline := stage_points.duplicate()
	stage_outline.append(stage_points[0])
	draw_polyline(stage_outline, Color(0.56, 0.37, 0.18, 0.94), 2.0, true)
	var inner_points := _ellipse_points(stage_center, stage_radii - Vector2(7, 3))
	var inner_outline := inner_points.duplicate()
	inner_outline.append(inner_points[0])
	draw_polyline(inner_outline, Color(0.20, 0.11, 0.055, 0.86), 1.0, true)

	draw_texture_rect(_base_texture, Rect2(origin, scaled_canvas), false)
	# Helmet records now have a clean alpha edge, so suppress the underlying
	# hair exactly as a paper-doll occlusion layer would.
	if _helmet_texture == null:
		_draw_layer(_hair_layer, origin)
	for layer: Dictionary in _paper_layers:
		_draw_layer(layer, origin)


func _ellipse_points(center: Vector2, radii: Vector2, segments := 64) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _draw_layer(layer: Dictionary, origin: Vector2) -> void:
	if layer.is_empty():
		return
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return
	var target := Rect2(
		origin + _mapping_offset(layer) * PREVIEW_SCALE,
		texture.get_size() * PREVIEW_SCALE
	)
	draw_texture_rect(texture, target, false)


func _load_paper_mappings() -> void:
	_paper_mappings.clear()
	_base_texture = null
	_hair_layer.clear()
	if not FileAccess.file_exists(PAPER_DOLL_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAPER_DOLL_MANIFEST))
	if not parsed is Dictionary:
		return
	var mappings: Variant = parsed.get("runtimeMappings", {})
	if mappings is Dictionary:
		_paper_mappings = mappings
	var base: Variant = parsed.get("base", {})
	if base is Dictionary:
		var base_path := str(base.get("path", ""))
		if ResourceLoader.exists(base_path):
			_base_texture = load(base_path) as Texture2D
	var hair: Variant = parsed.get("hair", {})
	if hair is Dictionary:
		var hair_path := str(hair.get("path", ""))
		if ResourceLoader.exists(hair_path):
			_hair_layer = hair.duplicate(true)
			_hair_layer["texture"] = load(hair_path) as Texture2D


func _mapping_offset(layer: Dictionary) -> Vector2:
	var value: Variant = layer.get("drawOffset", [0, 0])
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func paper_layer_source_index(slot: String) -> int:
	for layer: Dictionary in _paper_layers:
		if str(layer.get("equipmentSlot", "")) == slot:
			return int(layer.get("sourceIndex", -1))
	return -1
