class_name EquipmentCharacterPreview
extends Control

# Retained for serialized callers that still set the legacy property.  Bounds
# are diagnostics only now: a weapon or helmet must never move the actor.
const OPAQUE_CENTER_CONTRACT_ID := "ui.equipment.paper_doll.opaque_center.v1"
const FOOT_STAGE_ANCHOR_CONTRACT_ID := "ui.equipment.paper_doll.foot_stage_anchor.v2"
const BODY_FOOT_CONTACT_FIELD := "footContact"
const PAPER_DOLL_MANIFEST := "res://assets/data/warrior_paper_doll_sources.json"
const EQUIPMENT_VISUAL_CATALOG := "res://assets/data/equipment_visual_catalog.json"
const PROFESSION_IDS := {
	"战士": "warrior",
	"法师": "wizard",
	"道士": "taoist",
}
const PAPER_LAYER_SLOTS := ["衣服", "武器", "头盔"]
const ORIGINAL_CANVAS_SIZE := Vector2(168.0, 199.0)
const DEFAULT_PREVIEW_SCALE := 1.22
const FOOT_STAGE_CENTER := Vector2(84.0, 186.0)
const FOOT_STAGE_RADII := Vector2(52.0, 16.0)

var preview_scale := DEFAULT_PREVIEW_SCALE
# Compatibility input for pre-v2 callers.  It deliberately no longer affects
# placement; the manifest foot anchor is the only composition anchor.
var center_on_opaque_bounds := false
var profession_name := ""
var paper_doll_manifest_path := ""
var visual_catalog_path := EQUIPMENT_VISUAL_CATALOG
var _direction_row := 4
var _paper_mappings: Dictionary = {}
var _paper_layers: Array[Dictionary] = []
var _equipment_snapshot: Dictionary = {}
var _use_equipment_snapshot := false
var _source_document_override: Dictionary = {}
var _base_texture: Texture2D
var _hair_layer: Dictionary = {}
var _body_layer: Dictionary = {}
var _body_texture: Texture2D
var _weapon_texture: Texture2D
var _helmet_texture: Texture2D
var _canvas_size := ORIGINAL_CANVAS_SIZE
var _manifest_foot_anchor := FOOT_STAGE_CENTER
var _foot_stage_center := FOOT_STAGE_CENTER
var _composition_opaque_bounds := Rect2(Vector2.ZERO, ORIGINAL_CANVAS_SIZE)

static var _json_cache: Dictionary = {}
static var _opaque_rect_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	custom_minimum_size = Vector2(230, 286)
	if profession_name.is_empty():
		profession_name = str(PlayerState.profession)
	_load_paper_mappings()
	if not PlayerState.equipment_changed.is_connected(refresh):
		PlayerState.equipment_changed.connect(refresh)
	refresh()


func configure_profile(value: String, equipment_snapshot: Dictionary) -> void:
	profession_name = value
	_equipment_snapshot = equipment_snapshot.duplicate(true)
	_use_equipment_snapshot = true
	if is_node_ready():
		_load_paper_mappings()
		refresh()


func configure_source_paths(manifest_path: String, catalog_path := "") -> void:
	paper_doll_manifest_path = manifest_path
	if not catalog_path.is_empty():
		visual_catalog_path = catalog_path
	if is_node_ready():
		_load_paper_mappings()
		refresh()


func configure_source_document(document: Dictionary) -> void:
	_source_document_override = document
	if is_node_ready():
		_load_paper_mappings()
		refresh()


func refresh() -> void:
	if _paper_mappings.is_empty():
		_load_paper_mappings()
	_paper_layers.clear()
	_body_layer.clear()
	_body_texture = null
	_weapon_texture = null
	_helmet_texture = null
	_foot_stage_center = _manifest_foot_anchor
	var equipment_source := _equipment_snapshot if _use_equipment_snapshot else PlayerState.equipment
	for slot: String in PAPER_LAYER_SLOTS:
		var equipped: Variant = equipment_source.get(slot, {})
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
			_foot_stage_center = _vector_from_value(
				layer.get(BODY_FOOT_CONTACT_FIELD, _manifest_foot_anchor),
				_manifest_foot_anchor
			)
		elif slot == "武器":
			_weapon_texture = texture
		elif slot == "头盔":
			_helmet_texture = texture
	_recalculate_composition_opaque_bounds()
	queue_redraw()


func _draw() -> void:
	if _base_texture == null:
		return
	var scaled_canvas := _canvas_size * preview_scale
	# Put the original 199px client canvas near the bottom of the available
	# preview.  This uses the space below the character while preserving every
	# original layer coordinate.
	var origin := composition_draw_origin()
	# A flattened stage sits under the character's feet. The previous circle
	# read as a misplaced halo and did not match the paper-doll perspective.
	var stage_center := foot_stage_center()
	var stage_radii := FOOT_STAGE_RADII * preview_scale
	var shadow_points := _ellipse_points(stage_center + Vector2(0, 4), stage_radii + Vector2(5, 3))
	draw_colored_polygon(shadow_points, Color(0.008, 0.005, 0.004, 0.72))
	var stage_points := _ellipse_points(stage_center, stage_radii)
	draw_colored_polygon(stage_points, Color(0.055, 0.032, 0.018, 0.92))
	var back_rim := _ellipse_arc_points(stage_center, stage_radii, PI, TAU)
	draw_polyline(back_rim, Color(0.13, 0.075, 0.035, 0.82), 3.0, true)
	draw_polyline(back_rim, Color(0.50, 0.31, 0.14, 0.86), 1.0, true)

	draw_texture_rect(_base_texture, Rect2(origin, scaled_canvas), false)
	# Helmet records now have a clean alpha edge, so suppress the underlying
	# hair exactly as a paper-doll occlusion layer would.
	if _helmet_texture == null:
		_draw_layer(_hair_layer)
	for layer: Dictionary in _paper_layers:
		_draw_layer(layer)
	# The front rim is drawn after the paper doll so the figure stands inside
	# the stage instead of placing both feet directly on a complete outline.
	var front_rim := _ellipse_arc_points(stage_center, stage_radii, 0.0, PI)
	draw_polyline(front_rim, Color(0.025, 0.012, 0.006, 0.98), 5.0, true)
	draw_polyline(front_rim, Color(0.70, 0.43, 0.19, 0.96), 2.0, true)
	var inner_front := _ellipse_arc_points(stage_center, stage_radii - Vector2(8, 4), 0.0, PI)
	draw_polyline(inner_front, Color(0.24, 0.13, 0.055, 0.78), 1.0, true)


func _ellipse_points(center: Vector2, radii: Vector2, segments := 64) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _ellipse_arc_points(center: Vector2, radii: Vector2, start_angle: float, end_angle: float, segments := 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var progress := float(index) / float(segments)
		var angle := lerpf(start_angle, end_angle, progress)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _draw_layer(layer: Dictionary) -> void:
	if layer.is_empty():
		return
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return
	var target := Rect2(
		layer_draw_origin(layer),
		texture.get_size() * preview_scale
	)
	draw_texture_rect(texture, target, false)


func _load_paper_mappings() -> void:
	_paper_mappings.clear()
	_base_texture = null
	_hair_layer.clear()
	_canvas_size = ORIGINAL_CANVAS_SIZE
	_manifest_foot_anchor = FOOT_STAGE_CENTER
	_foot_stage_center = FOOT_STAGE_CENTER
	var source_document := _resolve_source_document()
	if source_document.is_empty():
		return
	var parsed := _profession_manifest(source_document)
	var mappings: Variant = parsed.get("runtimeMappings", {})
	if not mappings is Dictionary or mappings.is_empty():
		mappings = _catalog_paper_mappings(source_document)
	if mappings is Dictionary:
		_paper_mappings = mappings
	_canvas_size = _vector_from_value(
		parsed.get("canvasSize", parsed.get("composition", {}).get("canvasSize", ORIGINAL_CANVAS_SIZE)),
		ORIGINAL_CANVAS_SIZE
	)
	_manifest_foot_anchor = _vector_from_value(
		parsed.get(
			"paperDollFootAnchor",
			parsed.get("footAnchor", parsed.get("composition", {}).get("footAnchor", FOOT_STAGE_CENTER))
		),
		FOOT_STAGE_CENTER
	)
	_foot_stage_center = _manifest_foot_anchor
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
	_recalculate_composition_opaque_bounds()


func _resolve_source_document() -> Dictionary:
	if not _source_document_override.is_empty():
		return _source_document_override
	if not paper_doll_manifest_path.is_empty():
		return _load_json_document(paper_doll_manifest_path)
	if FileAccess.file_exists(visual_catalog_path):
		var catalog := _load_json_document(visual_catalog_path)
		if not catalog.is_empty():
			return catalog
	var profession_id := str(PROFESSION_IDS.get(profession_name, "warrior"))
	var profession_path := "res://assets/data/%s_paper_doll_sources.json" % profession_id
	if FileAccess.file_exists(profession_path):
		return _load_json_document(profession_path)
	return _load_json_document(PAPER_DOLL_MANIFEST)


func _profession_manifest(document: Dictionary) -> Dictionary:
	var manifests: Variant = document.get("professionManifests", {})
	if manifests is Dictionary:
		var profession_id := str(PROFESSION_IDS.get(profession_name, "warrior"))
		var selected: Variant = manifests.get(profession_id, manifests.get(profession_name, {}))
		if selected is Dictionary and not selected.is_empty():
			var result: Dictionary = selected
			var document_mappings := _catalog_paper_mappings(document)
			if not document_mappings.is_empty():
				result = selected.duplicate(true)
				result["runtimeMappings"] = document_mappings
			return result
	return document


func _catalog_paper_mappings(document: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var items: Variant = document.get("itemsById", {})
	if not items is Dictionary:
		return result
	for item_value: Variant in items.values():
		if not item_value is Dictionary:
			continue
		var item_name := str(item_value.get("itemName", ""))
		var paper_doll: Variant = item_value.get("paperDoll", {})
		if item_name.is_empty() or not paper_doll is Dictionary:
			continue
		var path := str(paper_doll.get("path", ""))
		if path.is_empty():
			continue
		result[item_name] = paper_doll
	return result


func _load_json_document(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	if _json_cache.has(path):
		return _json_cache[path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	_json_cache[path] = parsed
	return parsed


func _mapping_offset(layer: Dictionary) -> Vector2:
	var value: Variant = layer.get("drawOffset", [0, 0])
	return _vector_from_value(value, Vector2.ZERO)


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	return fallback


func _recalculate_composition_opaque_bounds() -> void:
	var bounds := Rect2()
	var has_bounds := false
	if _base_texture != null:
		var base_bounds := _texture_opaque_rect(_base_texture)
		if base_bounds.has_area():
			bounds = base_bounds
			has_bounds = true
	if _helmet_texture == null:
		var hair_bounds := _layer_opaque_rect(_hair_layer)
		if hair_bounds.has_area():
			bounds = bounds.merge(hair_bounds) if has_bounds else hair_bounds
			has_bounds = true
	for layer: Dictionary in _paper_layers:
		var layer_bounds := _layer_opaque_rect(layer)
		if not layer_bounds.has_area():
			continue
		bounds = bounds.merge(layer_bounds) if has_bounds else layer_bounds
		has_bounds = true
	_composition_opaque_bounds = bounds if has_bounds else Rect2(Vector2.ZERO, _canvas_size)


func _layer_opaque_rect(layer: Dictionary) -> Rect2:
	if layer.is_empty():
		return Rect2()
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return Rect2()
	var rect := _texture_opaque_rect(texture)
	rect.position += _mapping_offset(layer)
	return rect


func _texture_opaque_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var cache_key := texture.resource_path
	if cache_key.is_empty():
		cache_key = "instance:%d" % texture.get_instance_id()
	if _opaque_rect_cache.has(cache_key):
		return _opaque_rect_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2()
	var used := image.get_used_rect()
	var result := Rect2(Vector2(used.position), Vector2(used.size))
	_opaque_rect_cache[cache_key] = result
	return result


func composition_draw_origin() -> Vector2:
	return foot_stage_center() - _foot_stage_center * preview_scale


func foot_stage_center() -> Vector2:
	# Keep the historical lower inset while pinning the stage horizontally to
	# the preview centre.  The same point is the paper-doll ground contact.
	return Vector2(
		size.x * 0.5,
		size.y - (_canvas_size.y - _foot_stage_center.y) * preview_scale - 6.0
	)


func paper_doll_foot_anchor() -> Vector2:
	return _foot_stage_center


func layer_draw_origin(layer: Dictionary) -> Vector2:
	return composition_draw_origin() + _mapping_offset(layer) * preview_scale


func composition_opaque_bounds() -> Rect2:
	return _composition_opaque_bounds


func has_renderable_assets() -> bool:
	return _base_texture != null


func paper_layer_source_index(slot: String) -> int:
	for layer: Dictionary in _paper_layers:
		if str(layer.get("equipmentSlot", "")) == slot:
			return int(layer.get("sourceIndex", -1))
	return -1
