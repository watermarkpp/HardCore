extends SceneTree


func _init() -> void:
	var existing := MapEditorLoadService.load_document(MapEditorSaveService.default_path("bich_province"))
	if existing.ok:
		var backup := MapEditorSaveService.save_document(existing.document, "res://map_editor_workspace/bich_province_auto_backup/bich_province_auto_backup.editor.json")
		assert(backup.ok, str(backup.get("errors", [])))
	var document := MapEditorTypes.new_map_from_catalog("bich_province", "bich_city_outdoor", 4, "比奇省·人工设计模板")
	document.editor_meta.workspace = "res://map_editor_workspace/bich_province_manual"
	document.editor_meta.revision = 1
	document.editor_meta.milestone = "BICH-MANUAL-BLANK"
	document.editor_meta.authority = "human_layout_required"
	document.editor_meta.runtime_approved = false
	document.ground.blank_fill_asset_id = "ground.dark_grass.001"
	document.design["city_rect"] = [96,96,64,64]
	document.design["safe_area_rect"] = [112,112,32,32]
	document.design["functional_zones"] = []
	for layer: String in MapEditorTypes.LAYER_NAMES:
		document.layers[layer] = []
	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	var saved := MapEditorSaveService.save_document(document)
	assert(saved.ok, str(saved.get("errors", [])))
	print("BICH_BLANK_MANUAL_TEMPLATE_PASS size=256x256 layers_empty=true path=%s" % saved.path)
	quit()
