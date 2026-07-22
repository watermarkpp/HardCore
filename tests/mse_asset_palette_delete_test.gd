extends Node


func _ready() -> void:
	var asset_id := "mse.new_carpet.01"
	var base := MapAssetCatalogService.find_base_asset(asset_id)
	assert(not base.is_empty())
	var override_path := "user://mse_asset_palette_delete_%s.json" % Time.get_ticks_usec()
	var initial := MapAssetCalibrationService.save_override(
		asset_id,
		{
			"anchor_px": [471, 239],
			"footprint_tiles": base.get("footprint_tiles", [1, 1]),
			"collision_policy": base.get("collision_policy", "none"),
		},
		override_path
	)
	assert(initial.get("ok", false), str(initial.get("errors", [])))
	var deleted := MapAssetCalibrationService.delete_from_palette(asset_id, override_path)
	assert(deleted.get("ok", false), str(deleted.get("errors", [])))
	assert(bool(deleted.get("deleted_from_palette", false)))
	var stored: Dictionary = MapAssetCalibrationService.load_overrides(override_path)
	var change: Dictionary = stored.get("overrides", {}).get(asset_id, {})
	var stored_anchor: Array = change.get("anchor_px", [])
	assert(stored_anchor.size() == 2)
	assert(Vector2i(int(stored_anchor[0]), int(stored_anchor[1])) == Vector2i(471, 239))
	assert(change.get("placeable", true) == false)
	var effective := MapAssetCalibrationService.effective_asset(base, override_path)
	assert(effective.get("placeable", true) == false)

	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	await get_tree().process_frame
	assert(editor.asset_size_menu.get_item_index(4) >= 0)
	assert(editor.asset_size_menu.get_item_text(editor.asset_size_menu.get_item_index(4)) == "删除素材")
	editor._request_asset_delete(asset_id)
	assert(editor.pending_asset_delete_id == asset_id)
	assert("原图文件和地图中已放置的内容会保留" in editor.asset_delete_dialog.dialog_text)
	editor.asset_delete_dialog.hide()
	editor._on_asset_delete_cancelled()
	assert(editor.pending_asset_delete_id.is_empty())

	var absolute := ProjectSettings.globalize_path(override_path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	print("MSE_ASSET_PALETTE_DELETE_PASS persistent_hide=true files_preserved=true")
	get_tree().quit(0)
