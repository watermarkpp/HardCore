class_name EquipmentCharacterPreview
extends Control

# Retained for serialized callers that still set the legacy property.  Bounds
# are diagnostics only now: a weapon or helmet must never move the actor.
const OPAQUE_CENTER_CONTRACT_ID := "ui.equipment.paper_doll.opaque_center.v1"
const FOOT_STAGE_ANCHOR_CONTRACT_ID := "ui.equipment.paper_doll.foot_stage_anchor.v2"
const ORIGINAL_CLIENT_STAGE_CONTRACT_ID := "equipment.paper_doll.original_client_stage.v1"
const AVATAR_ONLY_CONTRACT_ID := "equipment.paper_doll.avatar_only.v1"
const PRESENTATION_MODES_CONTRACT_ID := "equipment.paper_doll.presentation_modes.v1"
const ORIGINAL_CLIENT_DRAW_ORDER := ["base", "hair", "dress", "weapon", "helmet"]
const ORIGINAL_CLIENT_BASE_SCREEN_ORIGIN := Vector2(38.0, 52.0)
const ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR := Vector2(31.0, 96.0)
const BODY_FOOT_CONTACT_FIELD := "footContact"
const PAPER_DOLL_MANIFEST := "res://assets/data/warrior_paper_doll_sources.json"
const EQUIPMENT_VISUAL_CATALOG := "res://assets/data/equipment_visual_catalog.json"
const ORIGINAL_CLIENT_STAGE_MANIFEST := "res://assets/data/equipment_original_client_paper_doll_stage.json"
const PRESENTATION_MODES_MANIFEST := "res://assets/data/equipment_paper_doll_presentation_modes.json"
const CLASSIC_HEAD_PATCHES_MANIFEST := "res://assets/data/equipment_classic_avatar_head_patches.json"
const CLASSIC_HEAD_PATCHES_CONTRACT_ID := "equipment.paper_doll.classic_flattened_head_patch.v1"
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
# Player-facing screens render an avatar, never the complete historical
# equipment-window record.  The legacy record contains its own wallpaper and
# six slot frames, so it is retained solely for explicit compatibility/audit
# callers that request classic_avatar.
var presentation_mode := "world_avatar"
var _direction_row := 4
var _paper_mappings: Dictionary = {}
var _paper_layers: Array[Dictionary] = []
var _equipment_snapshot: Dictionary = {}
var _use_equipment_snapshot := false
var _source_document_override: Dictionary = {}
var _base_texture: Texture2D
var _base_source_texture: Texture2D
var _hair_layer: Dictionary = {}
var _body_layer: Dictionary = {}
var _body_texture: Texture2D
var _weapon_texture: Texture2D
var _helmet_texture: Texture2D
var _canvas_size := ORIGINAL_CANVAS_SIZE
var _manifest_foot_anchor := FOOT_STAGE_CENTER
var _foot_stage_center := FOOT_STAGE_CENTER
var _composition_opaque_bounds := Rect2(Vector2.ZERO, ORIGINAL_CANVAS_SIZE)
var _uses_original_client_stage := false
var _uses_world_avatar := false
var _uses_avatar_only_stage := false
var _base_record: Dictionary = {}
var _world_base_layer: Dictionary = {}
var _equipment_screen_anchor := ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR
var _viewport_origin := Vector2.ZERO
var _render_revision := 0
var _presentation_config: Dictionary = {}

static var _json_cache: Dictionary = {}
static var _opaque_rect_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	custom_minimum_size = Vector2(230, 286)
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
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


func configure_presentation_mode(mode: String) -> void:
	var requested := mode.strip_edges()
	if requested == "legacyFullPanel":
		# This mode is an archival source record, not a player UI presentation.
		requested = "classic_avatar"
	presentation_mode = requested if not requested.is_empty() else "world_avatar"
	if is_node_ready():
		_load_paper_mappings()
		refresh()


func refresh() -> void:
	if _paper_mappings.is_empty():
		_load_paper_mappings()
	_base_texture = _base_source_texture
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
		var mapping_value: Variant = _classic_head_patch_for_equipped(equipped) if slot == str(PAPER_LAYER_SLOTS[2]) else {}
		if not mapping_value is Dictionary or mapping_value.is_empty():
			mapping_value = _mapping_for_equipped(equipped)
		if not mapping_value is Dictionary or mapping_value.is_empty():
			continue
		var texture := _texture_from_record(mapping_value)
		if texture == null:
			continue
		var layer: Dictionary = mapping_value.duplicate(true)
		layer["texture"] = texture
		layer["equipmentSlot"] = slot
		layer["layerKind"] = _slot_layer_kind(slot)
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
	_apply_classic_head_erase_mask()
	_recalculate_composition_opaque_bounds()
	_render_revision += 1
	queue_redraw()


func _draw() -> void:
	if _base_texture == null:
		return
	if _uses_original_client_stage:
		_draw_original_client_stage()
		return
	if _uses_world_avatar:
		_draw_world_avatar()
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


func _draw_original_client_stage() -> void:
	# Source-faithful reconstruction of MirClient/FState.pas DStateWinDirectPaint.
	# The complete Prguse #376 record is the first layer. StateItem records stay
	# rectangular and are drawn with their WIL HotX/HotY values, including the
	# helmet pixels which deliberately restore portions of the original stage.
	for command: Dictionary in original_stage_draw_commands():
		var texture: Texture2D = command.get("texture")
		if texture == null:
			continue
		draw_texture_rect(texture, command.get("targetRect", Rect2()), false)


func _draw_world_avatar() -> void:
	# This is the same male world-wear atlas family used by PlayerVisual:
	# idle action, south direction and frame zero.  A Control preview crops the
	# one source cell instead of baking/borrowing the old equipment-page art.
	var stage_center := foot_stage_center()
	var stage_radii := Vector2(
		clampf(size.x * 0.23, 42.0, 60.0),
		clampf(size.y * 0.055, 12.0, 18.0)
	)
	var shadow_points := _ellipse_points(stage_center + Vector2(0, 4), stage_radii + Vector2(5, 3))
	draw_colored_polygon(shadow_points, Color(0.008, 0.005, 0.004, 0.56))
	# World dress atlases are complete body appearances.  As in PlayerVisual,
	# an equipped dress replaces the bare world base instead of being composited
	# on top of it; this prevents the anatomy from bleeding through clothing.
	if not _has_world_layer_kind("dress"):
		_draw_world_avatar_layer(_world_base_layer)
	for kind: String in ["dress", "weapon", "helmet"]:
		for layer: Dictionary in _paper_layers:
			if str(layer.get("layerKind", "")) == kind:
				_draw_world_avatar_layer(layer)
	var front_rim := _ellipse_arc_points(stage_center, stage_radii, 0.0, PI)
	draw_polyline(front_rim, Color(0.58, 0.36, 0.15, 0.72), 1.0, true)


func _draw_world_avatar_layer(layer: Dictionary) -> void:
	if layer.is_empty():
		return
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return
	var cell := _vector_from_value(layer.get("cell", [224, 224]), Vector2(224, 224))
	if cell.x <= 0.0 or cell.y <= 0.0:
		return
	var source_anchor := _vector_from_value(layer.get("footAnchor", [64, 80]), Vector2(64, 80))
	var destination_anchor := foot_stage_center()
	var target := Rect2(
		destination_anchor - source_anchor * preview_scale,
		cell * preview_scale
	)
	var direction_row := int(layer.get("directionRow", _direction_row))
	draw_texture_rect_region(
		texture,
		target,
		Rect2(Vector2(0, direction_row * cell.y), cell),
		Color.WHITE,
		false
	)


func _has_world_layer_kind(kind: String) -> bool:
	for layer: Dictionary in _paper_layers:
		if str(layer.get("layerKind", "")) == kind:
			return true
	return false


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
	_base_source_texture = null
	_hair_layer.clear()
	_base_record.clear()
	_uses_original_client_stage = false
	_uses_world_avatar = false
	_uses_avatar_only_stage = false
	_world_base_layer.clear()
	_canvas_size = ORIGINAL_CANVAS_SIZE
	_manifest_foot_anchor = FOOT_STAGE_CENTER
	_foot_stage_center = FOOT_STAGE_CENTER
	_equipment_screen_anchor = ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR
	_viewport_origin = Vector2.ZERO
	_presentation_config.clear()
	preview_scale = DEFAULT_PREVIEW_SCALE
	var source_document := _resolve_source_document()
	if source_document.is_empty():
		return
	_presentation_config = _presentation_config_from_document(source_document)
	var parsed := _profession_manifest(source_document)
	# A full Prguse #376 record embeds the legacy panel artwork and six empty
	# equipment slots.  It must never enter the character hall or inventory
	# preview merely because the catalog also contains that archival record.
	# An explicit source document is the compatibility/audit escape hatch for
	# the old original-stage test and for the optional classic_avatar mode.
	var explicit_legacy_source := (
		not _source_document_override.is_empty()
		and _document_contract_id(parsed) == ORIGINAL_CLIENT_STAGE_CONTRACT_ID
	)
	_uses_original_client_stage = (
		(presentation_mode == "classic_avatar" or explicit_legacy_source)
		and _document_contract_id(parsed) == ORIGINAL_CLIENT_STAGE_CONTRACT_ID
	)
	if _uses_original_client_stage:
		_load_original_client_stage(parsed, source_document)
		return
	if presentation_mode == "world_avatar":
		_load_world_avatar(parsed, source_document)
		return
	_load_avatar_only_stage(parsed)
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
	if not _uses_avatar_only_stage:
		var base: Variant = parsed.get("base", {})
		if base is Dictionary:
			_base_texture = _texture_from_record(base)
			_base_source_texture = _base_texture
		var hair: Variant = parsed.get("hair", {})
		if hair is Dictionary:
			var hair_texture := _texture_from_record(hair)
			if hair_texture != null:
				_hair_layer = hair.duplicate(true)
				_hair_layer["texture"] = hair_texture
	_recalculate_composition_opaque_bounds()


func _load_world_avatar(parsed: Dictionary, source_document: Dictionary) -> void:
	# world_avatar is deliberately sourced from the formal world actor/wear
	# catalog, not from StateItem equipment-page records.  It mirrors the
	# runtime selection of idle/S/frame0 while keeping this Control transparent.
	var gender_bases: Variant = parsed.get("worldBaseByGender", {})
	if not gender_bases is Dictionary:
		return
	var base_value: Variant = gender_bases.get("男", gender_bases.get("male", {}))
	if not base_value is Dictionary:
		return
	var base_action := _world_idle_action(base_value)
	var base_texture := _texture_from_record(base_action)
	if base_texture == null:
		return
	_world_base_layer = base_action.duplicate(true)
	_world_base_layer["texture"] = base_texture
	_world_base_layer["layerKind"] = "base"
	_world_base_layer["directionRow"] = _direction_row
	_base_texture = base_texture
	_base_source_texture = base_texture
	_canvas_size = _vector_from_value(
		_presentation_config.get("canvasSize", [224, 224]),
		Vector2(224, 224)
	)
	_manifest_foot_anchor = _vector_from_value(
		_presentation_config.get("footAnchor", [84, 186]),
		FOOT_STAGE_CENTER
	)
	_foot_stage_center = _manifest_foot_anchor
	_paper_mappings = _world_avatar_mappings(source_document)
	_uses_world_avatar = not _paper_mappings.is_empty()
	# A naked avatar remains valid even if no item overlay was found. The base
	# is formal world art and remains useful for character creation/empty saves.
	if not _uses_world_avatar:
		_uses_world_avatar = true
	_recalculate_composition_opaque_bounds()


func _world_idle_action(appearance: Dictionary) -> Dictionary:
	var actions_value: Variant = appearance.get("actions", {})
	if not actions_value is Dictionary:
		return {}
	var action_value: Variant = actions_value.get("idle", {})
	if action_value is Dictionary:
		return action_value.duplicate(true)
	return {}


func _world_avatar_mappings(document: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var items_value: Variant = document.get("itemsById", {})
	if not items_value is Dictionary:
		return result
	for item_key: Variant in items_value:
		var item_value: Variant = items_value[item_key]
		if not item_value is Dictionary:
			continue
		var slot := str(item_value.get("slot", ""))
		if not (slot in PAPER_LAYER_SLOTS):
			continue
		var action := _world_item_idle_action(item_value, slot)
		if action.is_empty():
			continue
		var path := str(action.get("path", ""))
		# Exported Godot builds store imported textures as .ctex resources. The
		# source PNG is intentionally absent there, so FileAccess alone would
		# silently discard every equipped overlay while the base still renders.
		# Accept either the runtime resource or a source file (the latter keeps
		# local source-tree tooling usable); texture loading remains centralized.
		if path.is_empty() or (not ResourceLoader.exists(path) and not FileAccess.file_exists(path)):
			continue
		action["slot"] = slot
		action["layerKind"] = _slot_layer_kind(slot)
		action["directionRow"] = _direction_row
		var item_id := str(item_value.get("itemId", item_key))
		var item_name := str(item_value.get("itemName", ""))
		result[item_id] = action
		if not item_name.is_empty():
			result[item_name] = action
	return result


func _world_item_idle_action(item: Dictionary, slot: String) -> Dictionary:
	var world_wear: Variant = item.get("worldWear", {})
	if not world_wear is Dictionary:
		return {}
	var appearance: Dictionary = {}
	if slot == "头盔":
		var helmet_value: Variant = world_wear.get("helmetAppearance", {})
		if helmet_value is Dictionary:
			appearance = helmet_value
	else:
		var gendered_value: Variant = world_wear.get("appearancesByGender", {})
		if gendered_value is Dictionary:
			var male_value: Variant = gendered_value.get("男", gendered_value.get("male", {}))
			if male_value is Dictionary:
				appearance = male_value
	if appearance.is_empty() or not bool(appearance.get("visible", true)):
		return {}
	return _world_idle_action(appearance)


func _load_avatar_only_stage(parsed: Dictionary) -> void:
	# The equipment contract may provide a fully resolved transparent avatar
	# record.  It is intentionally read before the catalog fallback, but only
	# accepts the dedicated avatar-only contract; legacyFullPanel is forbidden.
	var avatar_value: Variant = _presentation_config.get("avatarOnly", {})
	if not avatar_value is Dictionary:
		avatar_value = parsed.get("avatarOnly", {})
	if not avatar_value is Dictionary or avatar_value.is_empty():
		return
	if str(avatar_value.get("contractId", "")) != AVATAR_ONLY_CONTRACT_ID:
		return
	var avatar: Dictionary = avatar_value
	var avatar_base: Variant = avatar.get("base", {})
	if avatar_base is Dictionary:
		var avatar_base_texture := _texture_from_record(avatar_base)
		if avatar_base_texture != null:
			_base_texture = avatar_base_texture
			_base_source_texture = avatar_base_texture
			_uses_avatar_only_stage = true
	var avatar_canvas := _vector_from_value(
		avatar.get("canvasSize", parsed.get("canvasSize", ORIGINAL_CANVAS_SIZE)),
		ORIGINAL_CANVAS_SIZE
	)
	if avatar_canvas.x > 0.0 and avatar_canvas.y > 0.0:
		_canvas_size = avatar_canvas
	_manifest_foot_anchor = _vector_from_value(
		avatar.get("footAnchor", avatar.get("paperDollFootAnchor", FOOT_STAGE_CENTER)),
		FOOT_STAGE_CENTER
	)
	_foot_stage_center = _manifest_foot_anchor
	_viewport_origin = _vector_from_value(avatar.get("viewportOrigin", Vector2.ZERO), Vector2.ZERO)
	var avatar_hair: Variant = avatar.get("hair", {})
	if avatar_hair is Dictionary:
		var avatar_hair_texture := _texture_from_record(avatar_hair)
		if avatar_hair_texture != null:
			_hair_layer = avatar_hair.duplicate(true)
			_hair_layer["texture"] = avatar_hair_texture


func _load_original_client_stage(parsed: Dictionary, source_document: Dictionary) -> void:
	if str(parsed.get("sex", source_document.get("sex", "male"))).to_lower() != "male":
		return
	var stage_value: Variant = parsed.get(
		"stage",
		parsed.get("originalClientStage", parsed.get("base", {}))
	)
	if stage_value is Dictionary:
		_base_record = stage_value.duplicate(true)
		_base_texture = _texture_from_record(_base_record)
	var composition_value: Variant = parsed.get("composition", {})
	var composition: Dictionary = composition_value if composition_value is Dictionary else {}
	_canvas_size = _vector_from_value(
		parsed.get(
			"canvasSize",
			composition.get("canvasSize", _base_record.get("size", ORIGINAL_CANVAS_SIZE))
		),
		ORIGINAL_CANVAS_SIZE
	)
	if _base_texture != null and (
		_canvas_size.x <= 0.0 or _canvas_size.y <= 0.0
	):
		_canvas_size = _base_texture.get_size()
	_equipment_screen_anchor = _vector_from_value(
		composition.get(
			"equipmentScreenAnchor",
			parsed.get("equipmentScreenAnchor", ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR)
		),
		ORIGINAL_CLIENT_EQUIPMENT_SCREEN_ANCHOR
	)
	_viewport_origin = _vector_from_value(
		parsed.get(
			"viewportOrigin",
			composition.get("viewportOrigin", Vector2.ZERO)
		),
		Vector2.ZERO
	)
	var hair_value: Variant = parsed.get("hair", {})
	if hair_value is Dictionary:
		_hair_layer = hair_value.duplicate(true)
		var hair_texture := _texture_from_record(_hair_layer)
		if hair_texture != null:
			_hair_layer["texture"] = hair_texture
	_paper_mappings = _original_stage_mappings(source_document)
	if _paper_mappings.is_empty() and source_document != parsed:
		_paper_mappings = _original_stage_mappings(parsed)
	_recalculate_composition_opaque_bounds()


func _document_contract_id(document: Dictionary) -> String:
	return str(document.get(
		"contractId",
		document.get("stableId", document.get("id", ""))
	))


func _original_stage_mappings(document: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var direct_value: Variant = document.get(
		"itemMappings",
		document.get("runtimeMappings", {})
	)
	if direct_value is Dictionary:
		for key: Variant in direct_value:
			var mapping_value: Variant = direct_value[key]
			if mapping_value is Dictionary:
				result[str(key)] = mapping_value
	var items_value: Variant = document.get("itemsById", {})
	if not items_value is Dictionary:
		return result
	for item_key: Variant in items_value:
		var item_value: Variant = items_value[item_key]
		if not item_value is Dictionary:
			continue
		var mapping_value: Variant = item_value.get(
			"originalClientPaperDoll",
			item_value.get("paperDollOriginalStage", item_value.get("paperDoll", {}))
		)
		if not mapping_value is Dictionary or mapping_value.is_empty():
			continue
		result[str(item_key)] = mapping_value
		var item_id := str(item_value.get("itemId", item_value.get("item_id", "")))
		var item_name := str(item_value.get("itemName", item_value.get("name", "")))
		if not item_id.is_empty():
			result[item_id] = mapping_value
		if not item_name.is_empty():
			result[item_name] = mapping_value
	return result


func _resolve_source_document() -> Dictionary:
	if not _source_document_override.is_empty():
		return _source_document_override
	if not paper_doll_manifest_path.is_empty():
		return _load_json_document(paper_doll_manifest_path)
	var presentation := _load_json_document(PRESENTATION_MODES_MANIFEST)
	var mode_config := _presentation_mode_config(presentation)
	if not mode_config.is_empty():
		var source_catalog := str(mode_config.get("sourceCatalog", ""))
		var catalog_path := source_catalog if not source_catalog.is_empty() else visual_catalog_path
		if FileAccess.file_exists(catalog_path):
			var resolved_catalog := _load_json_document(catalog_path).duplicate(true)
			resolved_catalog["_paperPresentationModes"] = presentation
			resolved_catalog["_paperPresentationMode"] = mode_config
			return resolved_catalog
	# Until the presentation contract is generated, the formal visual catalog
	# remains the routing source. world_avatar resolves its worldBase/worldWear
	# records from it; classic_avatar reads only its transparent anatomy and
	# StateItem records. Neither path loads a complete equipment-window record.
	if FileAccess.file_exists(visual_catalog_path):
		var catalog := _load_json_document(visual_catalog_path)
		if not catalog.is_empty():
			return catalog
	var profession_id := str(PROFESSION_IDS.get(profession_name, "warrior"))
	var profession_path := "res://assets/data/%s_paper_doll_sources.json" % profession_id
	if FileAccess.file_exists(profession_path):
		return _load_json_document(profession_path)
	return _load_json_document(PAPER_DOLL_MANIFEST)


func _presentation_mode_config(document: Dictionary) -> Dictionary:
	if _document_contract_id(document) != PRESENTATION_MODES_CONTRACT_ID:
		return {}
	var modes_value: Variant = document.get("modes", {})
	if not modes_value is Dictionary:
		return {}
	var requested := presentation_mode
	if requested.is_empty():
		requested = str(document.get("defaultMode", "world_avatar"))
	if requested == "legacyFullPanel":
		requested = "world_avatar"
	var value: Variant = modes_value.get(requested, {})
	if not value is Dictionary:
		return {}
	var result: Dictionary = value.duplicate(true)
	result["mode"] = requested
	return result


func _presentation_config_from_document(document: Dictionary) -> Dictionary:
	var embedded: Variant = document.get("_paperPresentationMode", {})
	if embedded is Dictionary and not embedded.is_empty():
		return embedded.duplicate(true)
	return _presentation_mode_config(document)


func _profession_manifest(document: Dictionary) -> Dictionary:
	var manifests: Variant = document.get("professionManifests", {})
	if manifests is Dictionary:
		var profession_id := str(PROFESSION_IDS.get(profession_name, "warrior"))
		var selected: Variant = manifests.get(profession_id, manifests.get(profession_name, {}))
		if selected is Dictionary and not selected.is_empty():
			var result: Dictionary = selected.duplicate(true)
			for shared_key: String in [
				"contractId",
				"stableId",
				"stage",
				"originalClientStage",
				"composition",
				"viewportOrigin",
				"viewportBounds",
				"equipmentScreenAnchor",
				"itemMappings",
			]:
				if not result.has(shared_key) and document.has(shared_key):
					result[shared_key] = document[shared_key]
			var document_mappings := _catalog_paper_mappings(document)
			if not document_mappings.is_empty():
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


func _classic_head_patch_for_equipped(equipped: Dictionary) -> Dictionary:
	# Player UI never consumes the rectangular StateItem helmet record directly.
	# The equipment-owned primary-client contract derives a transparent head-only
	# patch and retains its source record, mask and exact offset for auditing.
	if presentation_mode != "classic_avatar":
		return {}
	var item_id := _formal_item_id_for_equipped(equipped)
	if item_id.is_empty():
		return {}
	var document := _load_json_document(CLASSIC_HEAD_PATCHES_MANIFEST)
	if _document_contract_id(document) != CLASSIC_HEAD_PATCHES_CONTRACT_ID:
		return {}
	var items: Variant = document.get("itemsById", {})
	if not items is Dictionary:
		return {}
	var item_value: Variant = items.get(item_id, {})
	if not item_value is Dictionary:
		return {}
	var patch: Variant = item_value.get("flattenedHeadPatch", {})
	if not patch is Dictionary:
		return {}
	if str(patch.get("contractId", "")) != CLASSIC_HEAD_PATCHES_CONTRACT_ID:
		return {}
	if str(patch.get("slot", "")) != str(PAPER_LAYER_SLOTS[2]):
		return {}
	var result: Dictionary = patch.duplicate(true)
	result["layerAssetKind"] = "classic_flattened_head_patch"
	return result


func _formal_item_id_for_equipped(equipped: Dictionary) -> String:
	var item_id := str(equipped.get("item_id", equipped.get("itemId", "")))
	if not item_id.is_empty():
		return item_id
	# Older player archives may have retained only the visible item name. Resolve
	# it by an exact record-name match in the formal visual catalog; never infer
	# an ID from a display name or consult a lower-priority source.
	var item_name := str(equipped.get("name", ""))
	if item_name.is_empty():
		return ""
	var document := _load_json_document(visual_catalog_path)
	var items: Variant = document.get("itemsById", {})
	if not items is Dictionary:
		return ""
	for key: Variant in items:
		var item_value: Variant = items[key]
		if not item_value is Dictionary:
			continue
		if str(item_value.get("itemName", "")) == item_name:
			return str(key)
	return ""


func _apply_classic_head_erase_mask() -> void:
	if presentation_mode != "classic_avatar" or _base_source_texture == null:
		return
	var helmet_layer := paper_layer_source_record(str(PAPER_LAYER_SLOTS[2]))
	if str(helmet_layer.get("layerAssetKind", "")) != "classic_flattened_head_patch":
		return
	var mask_path := str(helmet_layer.get("eraseMaskPath", ""))
	if mask_path.is_empty():
		return
	var mask_texture := _texture_from_record({"path": mask_path})
	if mask_texture == null:
		return
	var base_image := _base_source_texture.get_image()
	var mask_image := mask_texture.get_image()
	if base_image == null or base_image.is_empty() or mask_image == null or mask_image.is_empty():
		return
	var offset := _mapping_offset(helmet_layer)
	for mask_y: int in mask_image.get_height():
		for mask_x: int in mask_image.get_width():
			if mask_image.get_pixel(mask_x, mask_y).a <= 0.001:
				continue
			var base_x := int(offset.x) + mask_x
			var base_y := int(offset.y) + mask_y
			if base_x < 0 or base_y < 0 or base_x >= base_image.get_width() or base_y >= base_image.get_height():
				continue
			var pixel := base_image.get_pixel(base_x, base_y)
			pixel.a = 0.0
			base_image.set_pixel(base_x, base_y, pixel)
	_base_texture = ImageTexture.create_from_image(base_image)


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


func _mapping_for_equipped(equipped: Dictionary) -> Dictionary:
	for field_name: String in ["item_id", "itemId", "id", "name"]:
		var candidate := str(equipped.get(field_name, ""))
		if candidate.is_empty():
			continue
		var mapping_value: Variant = _paper_mappings.get(candidate, {})
		if mapping_value is Dictionary and not mapping_value.is_empty():
			return mapping_value
	return {}


func _texture_from_record(record: Dictionary) -> Texture2D:
	var texture_value: Variant = record.get("texture")
	if texture_value is Texture2D:
		return texture_value
	var path := str(record.get("path", ""))
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# World-wear atlas files are generated inputs and may not have an editor
	# import record in a freshly synchronized permanent worktree yet.  Loading
	# the verified PNG directly keeps the preview deterministic without falling
	# back to paper-doll StateItem art.
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _slot_layer_kind(slot: String) -> String:
	if slot == str(PAPER_LAYER_SLOTS[0]):
		return "dress"
	if slot == str(PAPER_LAYER_SLOTS[1]):
		return "weapon"
	if slot == str(PAPER_LAYER_SLOTS[2]):
		return "helmet"
	return ""


func _mapping_offset(layer: Dictionary) -> Vector2:
	if _uses_original_client_stage:
		return _original_stage_layer_position(layer)
	# The avatar-only presentation contract names coordinates stagePosition,
	# while decoded StateItem records use drawOffset.  Both are coordinates on
	# the same 168x199 classic canvas.  Ignoring stagePosition placed the hair
	# at the composition origin and left the actor visibly bald.
	var value: Variant = layer.get(
		"drawOffset",
		layer.get("stagePosition", [0, 0])
	)
	return _vector_from_value(value, Vector2.ZERO)


func _record_hot_offset(record: Dictionary) -> Vector2:
	if record.has("hotX") or record.has("hotY"):
		return Vector2(
			float(record.get("hotX", 0.0)),
			float(record.get("hotY", 0.0))
		)
	for field_name: String in ["hot", "rawDrawOffset", "recordOffset"]:
		if record.has(field_name):
			return _vector_from_value(record[field_name], Vector2.ZERO)
	return Vector2.ZERO


func _original_stage_layer_position(layer: Dictionary) -> Vector2:
	# Original screen formula:
	#   (31, 96) + record.HotX/HotY
	# bbx/bby start at the equipment window's local (0, 0).
	if (
		not layer.has("hotX")
		and not layer.has("hotY")
		and not layer.has("hot")
		and not layer.has("rawDrawOffset")
		and not layer.has("recordOffset")
		and layer.has("drawOffset")
	):
		return _vector_from_value(layer.get("drawOffset"), Vector2.ZERO)
	return _equipment_screen_anchor + _record_hot_offset(layer)


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
	if _uses_original_client_stage:
		return original_stage_rect().position
	return foot_stage_center() - _foot_stage_center * preview_scale


func foot_stage_center() -> Vector2:
	if _uses_original_client_stage:
		return original_stage_to_local(_manifest_foot_anchor)
	if _uses_world_avatar:
		# Player UI is deliberately larger than a map actor. Do not re-use the
		# 224px atlas canvas as a screen inset: that pushed a correctly enlarged
		# body above the panel. The actor's verified source foot anchor still
		# determines its position inside the source crop.
		return Vector2(size.x * 0.5, size.y - maxf(22.0, size.y * 0.11))
	# Keep the historical lower inset while pinning the stage horizontally to
	# the preview centre.  The same point is the paper-doll ground contact.
	return Vector2(
		size.x * 0.5,
		size.y - (_canvas_size.y - _foot_stage_center.y) * preview_scale - 6.0
	)


func paper_doll_foot_anchor() -> Vector2:
	return _foot_stage_center


func layer_draw_origin(layer: Dictionary) -> Vector2:
	if _uses_original_client_stage:
		return original_stage_to_local(_original_stage_layer_position(layer))
	return composition_draw_origin() + _mapping_offset(layer) * preview_scale


func original_stage_scale() -> float:
	if _canvas_size.x <= 0.0 or _canvas_size.y <= 0.0:
		return 1.0
	return maxf(0.0, minf(size.x / _canvas_size.x, size.y / _canvas_size.y))


func original_stage_rect() -> Rect2:
	var scale_value := original_stage_scale()
	var fitted_size := _canvas_size * scale_value
	return Rect2((size - fitted_size) * 0.5, fitted_size)


func original_stage_to_local(stage_point: Vector2) -> Vector2:
	var stage_rect := original_stage_rect()
	return (
		stage_rect.position
		+ (stage_point - _viewport_origin) * original_stage_scale()
	)


func local_to_original_stage(local_point: Vector2) -> Vector2:
	var scale_value := original_stage_scale()
	if is_zero_approx(scale_value):
		return Vector2.ZERO
	return (
		(local_point - original_stage_rect().position) / scale_value
		+ _viewport_origin
	)


func original_hit_rect_to_local(stage_hit_rect: Rect2) -> Rect2:
	return Rect2(
		original_stage_to_local(stage_hit_rect.position),
		stage_hit_rect.size * original_stage_scale()
	)


func original_stage_contains_local_point(local_point: Vector2) -> bool:
	return original_stage_rect().has_point(local_point)


func original_stage_draw_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not _uses_original_client_stage or _base_texture == null:
		return commands
	# Prguse #376 is a direct-paint background record. MirClient places it at
	# the explicit stage position (38, 52); unlike cached equipment records,
	# its WIL HotX/HotY are not part of the screen-space formula.
	var base_stage_position := _vector_from_value(
		_base_record.get("stagePosition", ORIGINAL_CLIENT_BASE_SCREEN_ORIGIN),
		ORIGINAL_CLIENT_BASE_SCREEN_ORIGIN
	)
	commands.append({
		"kind": "base",
		"sourceIndex": int(_base_record.get("sourceIndex", _base_record.get("index", 376))),
		"stagePosition": base_stage_position,
		"targetRect": Rect2(
			original_stage_to_local(base_stage_position),
			_base_texture.get_size() * original_stage_scale()
		),
		"texture": _base_texture,
	})
	_append_original_layer_command(commands, "hair", _hair_layer)
	for kind: String in ["dress", "weapon", "helmet"]:
		for layer: Dictionary in _paper_layers:
			if str(layer.get("layerKind", "")) == kind:
				_append_original_layer_command(commands, kind, layer)
	return commands


func _append_original_layer_command(
	commands: Array[Dictionary],
	kind: String,
	layer: Dictionary
) -> void:
	if layer.is_empty():
		return
	var texture: Texture2D = layer.get("texture")
	if texture == null:
		return
	var stage_position := _original_stage_layer_position(layer)
	commands.append({
		"kind": kind,
		"sourceIndex": int(layer.get("sourceIndex", layer.get("index", -1))),
		"stagePosition": stage_position,
		"targetRect": Rect2(
			original_stage_to_local(stage_position),
			texture.get_size() * original_stage_scale()
		),
		"texture": texture,
	})


func composition_opaque_bounds() -> Rect2:
	return _composition_opaque_bounds


func has_renderable_assets() -> bool:
	return _base_texture != null


func uses_original_client_stage() -> bool:
	return _uses_original_client_stage


func uses_world_avatar() -> bool:
	return _uses_world_avatar


func presentation_contract_id() -> String:
	return PRESENTATION_MODES_CONTRACT_ID


func world_avatar_draw_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not _uses_world_avatar:
		return commands
	if not _world_base_layer.is_empty() and not _has_world_layer_kind("dress"):
		commands.append(_world_base_layer.duplicate(true))
	for kind: String in ["dress", "weapon", "helmet"]:
		for layer: Dictionary in _paper_layers:
			if str(layer.get("layerKind", "")) == kind:
				commands.append(layer.duplicate(true))
	return commands


func render_revision() -> int:
	return _render_revision


func paper_layer_source_index(slot: String) -> int:
	for layer: Dictionary in _paper_layers:
		if str(layer.get("equipmentSlot", "")) == slot:
			return int(layer.get("sourceIndex", -1))
	return -1


func paper_layer_source_record(slot: String) -> Dictionary:
	for layer: Dictionary in _paper_layers:
		if str(layer.get("equipmentSlot", "")) == slot:
			return layer.duplicate(true)
	return {}
