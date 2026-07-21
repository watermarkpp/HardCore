extends SceneTree

const DOCUMENT_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const ManualCollisionPolicy := preload("res://scripts/map_assets/map_asset_manual_collision_policy.gd")


func _init() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	if not bool(loaded.get("ok", false)):
		push_error("CAVE_TOMB_WALL_COLLISION_STRIP_LOAD_FAILED %s" % loaded.get("errors", []))
		quit(1)
		return
	var document: Dictionary = loaded.document
	var changed_count := 0
	var wall_count := 0
	for layer_name: String in document.layers:
		if layer_name in ["collision", "collision_erase"]:
			continue
		var entries: Array = document.layers[layer_name]
		for index in entries.size():
			var instance: Dictionary = entries[index]
			if not instance.has("asset_id"):
				continue
			var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
			if not ManualCollisionPolicy.is_visual_only_wall(asset):
				continue
			wall_count += 1
			if ManualCollisionPolicy.apply_to_instance(instance, asset):
				changed_count += 1
			entries[index] = instance
		document.layers[layer_name] = entries
	var manual_collision_count := (document.layers.get("collision", []) as Array).size()
	var manual_erase_count := (document.layers.get("collision_erase", []) as Array).size()
	var save := MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	if not bool(save.get("ok", false)):
		push_error("CAVE_TOMB_WALL_COLLISION_STRIP_SAVE_FAILED %s" % save.get("errors", []))
		quit(1)
		return
	# Save a second time so both the live document and its automatic backup carry
	# the same collision-free wall policy.
	save = MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	if not bool(save.get("ok", false)):
		push_error("CAVE_TOMB_WALL_COLLISION_STRIP_BACKUP_FAILED %s" % save.get("errors", []))
		quit(1)
		return
	print(
		"CAVE_TOMB_WALL_COLLISION_STRIP_PASS walls=%d changed=%d manual=%d erase=%d policy=%s"
		% [
			wall_count,
			changed_count,
			manual_collision_count,
			manual_erase_count,
			ManualCollisionPolicy.POLICY_ID,
		]
	)
	quit(0)
