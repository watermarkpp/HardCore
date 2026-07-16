class_name MapEditorTypes
extends RefCounted

const SCHEMA_VERSION := 4
const TILE_SIZE := Vector2i(64, 32)
const DEFAULT_CHUNK_SIZE := Vector2i(1024, 1024)
const DEFAULT_GROUND_MODE := "generated_painted_chunks"
const DEFAULT_CONTENT_LAYER := "personal_expansion"

const LAYER_NAMES: Array[String] = [
	"ground_base", "ground_overlay", "terrain_base", "terrain_front", "object_base", "object_front",
	"shadow", "collision", "npc_points", "monster_spawn", "boss_spawn", "door_points",
	"safe_area", "interactables", "region_semantics", "light", "region_trigger", "editor_guides",
]


static func new_map(map_id: String, runtime_map_id: int, display_name: String, design_size: Vector2i) -> Dictionary:
	var layers := {}
	for layer_name: String in LAYER_NAMES:
		layers[layer_name] = []
	var origin := MapEditorCoordinate.origin_px(design_size)
	return {
		"schema_version": SCHEMA_VERSION,
		"map_id": map_id,
		"runtime_map_id": runtime_map_id,
		"display_name": display_name,
		"content_layer": DEFAULT_CONTENT_LAYER,
		"source_policy": "expansion_editable",
		"design": {
			"design_size": [design_size.x, design_size.y],
			"tile_size": [TILE_SIZE.x, TILE_SIZE.y],
			"view_type": "isometric_2_to_1",
		},
		"ground": {
			"ground_mode": DEFAULT_GROUND_MODE,
			"master_image": null,
			"chunk_manifest": "res://assets/data/maps/ground/%s.ground_chunks.json" % map_id,
			"source_manifest": "res://assets/data/maps/ground_paint/%s.ground_source_manifest.json" % map_id,
			"paint_manifest": "res://assets/data/maps/ground_paint/%s.ground_paint_ops.json" % map_id,
			"paint_state": "res://assets/data/maps/ground_paint/%s.ground_paint_state.json" % map_id,
			"workspace_manifest": "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id,
			"workspace_state": "res://map_editor_workspace/%s/ground/ground_state.json" % map_id,
			"chunk_size": [DEFAULT_CHUNK_SIZE.x, DEFAULT_CHUNK_SIZE.y],
			"origin_px": [int(origin.x), int(origin.y)],
			"tile_anchor_mode": "center",
			"visual_only": true,
			"collision_from_ground": false,
			"blank_generated": true,
			"blank_fill_asset_id": "ground.old_grass.001",
			"editable_source_required": true,
			"blank_chunk_policy": "virtual_shared_until_dirty",
			"mask_storage": "chunked_l8",
		},
		"layers": layers,
		"editor_meta": {
			"created_by": "human_codex_shared_tool",
			"workspace": "res://map_editor_workspace/%s" % map_id,
			"revision": 1,
		},
	}


static func new_map_from_catalog(map_id: String, map_type := "dungeon_floor", runtime_map_id := 0, display_name := "") -> Dictionary:
	var catalog_entry := MapDesignCatalogService.find_map(map_id)
	var resolved_runtime_id := int(catalog_entry.get("runtime_map_id", runtime_map_id))
	var resolved_name := str(catalog_entry.get("name", display_name if not display_name.is_empty() else map_id))
	var resolved_size := MapDesignCatalogService.recommended_size(map_id, map_type)
	var document := new_map(map_id, resolved_runtime_id, resolved_name, resolved_size)
	document.design["map_type"] = str(catalog_entry.get("map_type", map_type))
	document.design["strategy"] = str(catalog_entry.get("strategy", MapDesignCatalogService.get_template(map_type).get("strategy", "shrink_and_recompose")))
	document.design["source_size"] = catalog_entry.get("source_size", [null, null])
	document.design["source_size_is_design_size"] = false
	document["source_reference"] = {
		"source_map_path": catalog_entry.get("source_map_path", null),
		"audit_status": catalog_entry.get("source_audit_status", "not_audited"),
		"coordinate_system": "mir2_48x32",
	}
	return document


static func validate_document(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in ["schema_version", "map_id", "runtime_map_id", "display_name", "design", "ground", "layers"]:
		if not document.has(key):
			errors.append("missing_field:%s" % key)
	if int(document.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("unsupported_schema_version")
	if str(document.get("map_id", "")).strip_edges().is_empty():
		errors.append("invalid_map_id")
	var design: Dictionary = document.get("design", {})
	var size: Array = design.get("design_size", [])
	if size.size() != 2 or int(size[0]) <= 0 or int(size[1]) <= 0:
		errors.append("invalid_design_size")
	var tile_size: Array = design.get("tile_size", [])
	if tile_size.size() != 2 or int(tile_size[0]) != 64 or int(tile_size[1]) != 32 or str(design.get("view_type", "")) != "isometric_2_to_1":
		errors.append("invalid_coordinate_standard")
	var ground: Dictionary = document.get("ground", {})
	if str(ground.get("ground_mode", "")) != DEFAULT_GROUND_MODE:
		errors.append("invalid_ground_mode")
	if bool(ground.get("collision_from_ground", true)):
		errors.append("ground_must_not_generate_collision")
	var layers: Dictionary = document.get("layers", {})
	for layer_name: String in LAYER_NAMES:
		if not layers.has(layer_name):
			errors.append("missing_layer:%s" % layer_name)
	return errors


static func upgrade_document(document: Dictionary) -> Dictionary:
	var upgraded := document.duplicate(true)
	if int(upgraded.get("schema_version", -1)) == SCHEMA_VERSION:
		var layers: Dictionary = upgraded.get("layers", {})
		for layer_name: String in LAYER_NAMES:
			if not layers.has(layer_name):
				layers[layer_name] = []
		upgraded["layers"] = layers
	return upgraded
