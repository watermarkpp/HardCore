extends SceneTree

const MAP_ID := "orc_tomb_3"
const WALL_FAMILY_ID := "orc_tomb_rough_stone_u0"
const STRUCTURE_ID := "orc_tomb_3.outer_closed_loop.v1"
const BOUNDS := Rect2i(0, 0, 38, 38)


func _init() -> void:
	var path := MapEditorSaveService.default_path(MAP_ID)
	var loaded := MapEditorLoadService.load_document(path)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s" % loaded.get("errors", []))
		return
	var document: Dictionary = loaded.document
	var preserved := _preserved_counts(document)
	var result: Dictionary = MapEditorWallLoopService.apply_closed_rectangle(
		document,
		WALL_FAMILY_ID,
		BOUNDS,
		"outer_corner",
		"terrain_base",
		true,
		STRUCTURE_ID
	)
	if not bool(result.get("ok", false)):
		_fail("loop_apply_failed:%s" % result.get("errors", []))
		return
	var validation := MapEditorWallLoopService.validate_closed_rectangle(
		document,
		WALL_FAMILY_ID,
		BOUNDS,
		STRUCTURE_ID
	)
	if not bool(validation.get("ok", false)):
		_fail("loop_validation_failed:%s" % validation.get("errors", []))
		return
	if _preserved_counts(document) != preserved:
		_fail("non_wall_content_changed:%s->%s" % [preserved, _preserved_counts(document)])
		return
	var meta: Dictionary = document.get("editor_meta", {})
	meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["wall_visual_milestone"] = "ORC-TOMB-3-VISUAL-CLOSED-LOOP-V1"
	document["editor_meta"] = meta
	var saved := MapEditorSaveService.save_document(document, path)
	if not bool(saved.get("ok", false)):
		_fail("save_failed:%s" % saved.get("errors", []))
		return
	print(
		"ORC_TOMB_3_VISUAL_LOOP_PASS removed=%d added=%d perimeter_cells=%d"
		% [
			int(result.get("removed_count", 0)),
			int(result.get("added_count", 0)),
			int(validation.get("perimeter_cell_count", 0)),
		]
	)
	quit(0)


func _preserved_counts(document: Dictionary) -> Dictionary:
	return {
		"collision": document.get("layers", {}).get("collision", []).size(),
		"collision_erase": document.get("layers", {}).get("collision_erase", []).size(),
		"monster_spawn": document.get("layers", {}).get("monster_spawn", []).size(),
		"boss_spawn": document.get("layers", {}).get("boss_spawn", []).size(),
		"map_entrance_points": document.get("layers", {}).get("map_entrance_points", []).size(),
		"map_exit_points": document.get("layers", {}).get("map_exit_points", []).size(),
		"object_instances": _non_family_instance_count(document),
	}


func _non_family_instance_count(document: Dictionary) -> int:
	var count := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		if str(asset.get("wall_family_id", "")) != WALL_FAMILY_ID:
			count += 1
	return count


func _fail(message: String) -> void:
	push_error("ORC_TOMB_3_VISUAL_LOOP_FAILED %s" % message)
	quit(1)
