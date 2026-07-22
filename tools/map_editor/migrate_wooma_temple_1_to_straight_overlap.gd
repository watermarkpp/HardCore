extends SceneTree

const MAP_ID := "wooma_temple_1"
const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const LEGACY_CORNER_INSTANCE_IDS := [
	"inst_000045",
	"inst_000047",
	"inst_000049",
	"inst_000050",
]
const FILLERS := [
	{"asset_id": "wooma_temple_wall_straight_x_l2_v01", "tile": Vector2i(0, 0), "role": "corner_min_min_x"},
	{"asset_id": "wooma_temple_wall_straight_y_l1_v01", "tile": Vector2i(0, 0), "role": "corner_min_min_y"},
	{"asset_id": "wooma_temple_wall_straight_x_l2_v01", "tile": Vector2i(42, 0), "role": "corner_max_min_x"},
	{"asset_id": "wooma_temple_wall_straight_y_l1_v01", "tile": Vector2i(43, 0), "role": "corner_max_min_y"},
	{"asset_id": "wooma_temple_wall_straight_x_l2_v01", "tile": Vector2i(0, 43), "role": "corner_min_max_x"},
	{"asset_id": "wooma_temple_wall_straight_y_l2_v01", "tile": Vector2i(0, 42), "role": "corner_min_max_y"},
	{"asset_id": "wooma_temple_wall_straight_x_l1_v01", "tile": Vector2i(43, 43), "role": "corner_max_max_x"},
	{"asset_id": "wooma_temple_wall_straight_y_l2_v01", "tile": Vector2i(43, 42), "role": "corner_max_max_y"},
]


func _init() -> void:
	MapAssetCatalogService.invalidate_cache()
	var path := MapEditorSaveService.default_path(MAP_ID)
	var loaded := MapEditorLoadService.load_document(path)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s" % loaded.get("errors", []))
		return
	var document: Dictionary = loaded.document
	var preserved := _preserved_counts(document)
	for instance_id: String in LEGACY_CORNER_INSTANCE_IDS:
		var deleted := MapEditorInstanceService.delete_instance(document, instance_id)
		if not bool(deleted.get("ok", false)):
			_fail("legacy_corner_delete_failed:%s:%s" % [instance_id, deleted.get("errors", [])])
			return

	var added_ids: Array[String] = []
	for filler: Dictionary in FILLERS:
		var placed := MapEditorInstanceService.create_instance(
			document,
			str(filler.asset_id),
			"terrain",
			filler.tile,
			"terrain_base"
		)
		if not bool(placed.get("ok", false)):
			_fail("filler_place_failed:%s@%s:%s" % [
				filler.asset_id,
				filler.tile,
				placed.get("errors", []),
			])
			return
		var entries: Array = document.layers.terrain_base
		var instance: Dictionary = entries.back()
		instance["structure_id"] = "wooma_temple_1.straight_overlap_corners.v1"
		instance["structure_role"] = str(filler.role)
		instance["generated_by"] = "migrate_wooma_temple_1_to_straight_overlap"
		instance["collision_policy"] = "none"
		instance["collision_profile_id"] = "none_visual"
		instance["collision_footprint_tiles"] = [0, 0]
		instance["collision_cells"] = []
		instance["navigation_policy"] = "ignore"
		instance["manual_collision_expected"] = true
		instance["map_collision_override"] = "disabled"
		entries[entries.size() - 1] = instance
		document.layers.terrain_base = entries
		added_ids.append(str(instance.instance_id))

	if _preserved_counts(document) != preserved:
		_fail("non_wall_content_changed:%s->%s" % [preserved, _preserved_counts(document)])
		return
	if _legacy_corner_count(document) != 0:
		_fail("legacy_corner_instances_remain")
		return
	if _straight_filler_count(document) != FILLERS.size():
		_fail("straight_filler_count_mismatch:%d" % _straight_filler_count(document))
		return

	var meta: Dictionary = document.get("editor_meta", {})
	meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["wooma_wall_corner_contract"] = "native_2to1_straight_overlap_v1"
	meta["wooma_wall_corner_migration"] = "WOOMA-TEMPLE-1-NO-PILLAR-V1"
	document["editor_meta"] = meta
	var saved := MapEditorSaveService.save_document(document, path)
	if not bool(saved.get("ok", false)):
		_fail("save_failed:%s" % saved.get("errors", []))
		return
	var verified := MapEditorLoadService.load_document(path)
	if not bool(verified.get("ok", false)):
		_fail("reload_failed:%s" % verified.get("errors", []))
		return
	print(
		"WOOMA_TEMPLE_1_STRAIGHT_OVERLAP_MIGRATION_PASS removed=4 added=%d ids=%s"
		% [added_ids.size(), added_ids]
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
		"npc_points": document.get("layers", {}).get("npc_points", []).size(),
		"ground_base": document.get("layers", {}).get("ground_base", []).size(),
		"non_family_instances": _non_family_instance_count(document),
	}


func _non_family_instance_count(document: Dictionary) -> int:
	var count := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var asset_id := str(instance.get("asset_id", ""))
		var asset := MapAssetCatalogService.find_asset(asset_id)
		if (
			not asset_id.begins_with("wooma_temple_wall_")
			and str(asset.get("wall_family_id", "")) != FAMILY_ID
		):
			count += 1
	return count


func _legacy_corner_count(document: Dictionary) -> int:
	var count := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("instance_id", "")) in LEGACY_CORNER_INSTANCE_IDS:
			count += 1
	return count


func _straight_filler_count(document: Dictionary) -> int:
	var count := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if (
			str(instance.get("structure_id", ""))
			== "wooma_temple_1.straight_overlap_corners.v1"
		):
			count += 1
	return count


func _fail(message: String) -> void:
	push_error("WOOMA_TEMPLE_1_STRAIGHT_OVERLAP_MIGRATION_FAILED %s" % message)
	quit(1)
