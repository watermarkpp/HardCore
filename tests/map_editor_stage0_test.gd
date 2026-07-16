extends Node


func _ready() -> void:
	var bich := MapEditorTypes.new_map_from_catalog("bich_province")
	assert(bich.runtime_map_id == 4)
	assert(bich.design.design_size == [64, 64])
	assert(bich.design.size_status == "user_confirmed_final")
	assert(bich.design.tile_size == [64, 32])
	assert(bich.design.source_size != bich.design.design_size)
	assert(bich.ground.blank_chunk_policy == "virtual_shared_until_dirty")
	assert(bich.ground.mask_storage == "chunked_l8")
	assert(MapEditorTypes.validate_document(bich).is_empty())
	var mengzhong := MapEditorTypes.new_map_from_catalog("mengzhong_province")
	assert(mengzhong.design.design_size == [280, 280])
	var unknown := MapEditorTypes.new_map_from_catalog("sandbox_64", "quest_room", 990001, "64格沙盒")
	assert(unknown.design.design_size == [64, 64])
	assert(unknown.runtime_map_id == 990001)
	assert(MapEditorSaveService.default_path("sandbox_64") == "res://map_editor_workspace/sandbox_64/sandbox_64.editor.json")
	assert(MapAssetCatalogService.validate_catalog().is_empty())
	var palette := MapAssetCatalogService.palette_assets()
	assert(not palette.is_empty())
	assert(palette.all(func(asset: Dictionary) -> bool: return bool(asset.get("placeable", false))))
	var tile := Vector2(73, 81)
	var px := MapEditorCoordinate.tile_to_ground_px(tile, Vector2i(256, 256))
	assert(MapEditorCoordinate.ground_px_to_tile(px, Vector2i(256, 256)).is_equal_approx(tile))
	var counter := [0]
	var stack := MapEditorCommandStack.new()
	assert(stack.execute({"do": func(): counter[0] += 1, "undo": func(): counter[0] -= 1}))
	assert(counter[0] == 1 and stack.undo() and counter[0] == 0 and stack.redo() and counter[0] == 1)
	var path := "user://map_editor_stage0_test.editor.json"
	var saved := MapEditorSaveService.save_document(unknown, path)
	assert(saved.ok, str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(path)
	assert(loaded.ok and loaded.document.map_id == "sandbox_64")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var editor_scene := load("res://scenes/tools/mafa_scene_editor.tscn") as PackedScene
	var editor := editor_scene.instantiate() as MapEditorApp
	add_child(editor)
	assert(editor.current_document.map_id == "sandbox_64")
	var editor_size: Array = editor.current_document.design.design_size
	assert(Vector2i(int(editor_size[0]), int(editor_size[1])) == Vector2i(64, 64))
	assert(editor.asset_tree != null)
	assert("sandbox_64.editor.json" in editor.path_label.text)
	editor._create_map("bich_province", "outdoor_province", 4, "比奇省")
	assert(editor.current_document.design.design_size == [64, 64])
	editor.queue_free()
	print("MAP_EDITOR_STAGE0_PASS")
	get_tree().quit(0)
