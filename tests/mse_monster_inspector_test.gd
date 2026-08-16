extends Node

const MapEditorAppScript := preload("res://scripts/map_editor/map_editor_app.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapEditorContentCatalogService.reset_source_parse_counts()
	var woma := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 76)
	var dark_woma := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 239)
	var dark_rainbow := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 240)
	assert(not woma.is_empty(), "ID 76 missing")
	assert(not dark_woma.is_empty(), "ID 239 missing")
	assert(not dark_rainbow.is_empty(), "ID 240 missing")

	var editor := MapEditorAppScript.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	editor.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var sidebar_base := int(editor.sidebar_scroll.size.x)
	assert(sidebar_base >= 300 and sidebar_base <= 340, "sidebar width out of range: %d" % sidebar_base)

	# ID76
	editor._show_monster_inspector(woma)
	await get_tree().process_frame
	assert(editor.monster_inspector_panel.visible, "ID76 inspector not visible")
	var inspector_width_76 := int(editor.monster_inspector_panel.size.x)
	assert(inspector_width_76 >= 450 and inspector_width_76 <= 600, "inspector width out of range: %d" % inspector_width_76)
	assert(int(editor.sidebar_scroll.size.x) - sidebar_base <= 2, "sidebar widened after ID76")
	var text_76: String = editor.monster_inspector_detail.text
	assert(text_76.contains("沃玛教主"), "ID76 detail missing name")
	assert(text_76.contains("33"), "ID76 detail missing drop count 33")
	assert(text_76.contains("沃玛号角"), "ID76 detail missing known drop 沃玛号角")
	var panel_76 := editor.monster_inspector_panel

	# ID239 (same panel instance)
	editor._show_monster_inspector(dark_woma)
	await get_tree().process_frame
	assert(editor.monster_inspector_panel == panel_76, "inspector panel must be a single instance")
	assert(int(editor.monster_inspector_panel.size.x) - inspector_width_76 <= 2, "inspector width changed after ID239")
	assert(int(editor.sidebar_scroll.size.x) - sidebar_base <= 2, "sidebar widened after ID239")
	var text_239: String = editor.monster_inspector_detail.text
	assert(text_239.contains("暗之沃玛教主"), "ID239 detail missing name")
	assert(text_239.contains("54"), "ID239 detail missing drop count 54")

	# ID240 (boss, non-placeable)
	editor._show_monster_inspector(dark_rainbow)
	await get_tree().process_frame
	assert(editor.monster_inspector_panel == panel_76, "inspector panel must remain single instance")
	assert(int(editor.sidebar_scroll.size.x) - sidebar_base <= 2, "sidebar widened after ID240")
	var text_240: String = editor.monster_inspector_detail.text
	assert(text_240.contains("暗之虹魔教主"), "ID240 detail missing name")
	assert(text_240.contains("boss"), "ID240 detail missing classification boss")
	assert(text_240.contains("54"), "ID240 detail missing drop count 54")
	assert(text_240.contains("允许放置：否"), "ID240 detail missing non-placeable status")
	assert(text_240.contains("禁止原因"), "ID240 detail missing rejection reason")

	# Reference attributes for an unverified entry that still carries stats.
	var ref_entry := _find_unverified_with_stats()
	if not ref_entry.is_empty():
		editor._show_monster_inspector(ref_entry)
		await get_tree().process_frame
		var ref_text: String = editor.monster_inspector_detail.text
		assert(ref_text.contains("参考数据"), "unverified entry must show reference-data status")
		assert(ref_text.contains("等级：") or ref_text.contains("生命："), "unverified entry must still show stats")

	# Hover contract: hovering a monster row shows the inspector with a
	# real-height body and an opaque panel background; clicking hides it.
	var hover_item := _find_monster_tree_item(editor, 76)
	assert(hover_item != null, "ID76 tree item missing from semantic catalog")
	editor._close_monster_inspector()
	editor._preview_monster_catalog_item(hover_item)
	await get_tree().process_frame
	assert(editor.monster_inspector_panel.visible, "hover did not show inspector")
	assert(editor.monster_inspector_detail.text.contains("沃玛教主"), "hover detail missing name")
	assert(int(editor.monster_inspector_detail.size.y) > 0, "inspector body must have real height")
	var panel_style: StyleBox = editor.monster_inspector_panel.get_theme_stylebox("panel")
	assert(panel_style is StyleBoxFlat, "inspector panel must use an opaque StyleBoxFlat")
	var flat_style: StyleBoxFlat = panel_style
	assert(flat_style.bg_color.a >= 0.99, "inspector panel background must be opaque")
	editor._activate_semantic_catalog_item(hover_item)
	await get_tree().process_frame
	assert(not editor.monster_inspector_panel.visible, "click did not close inspector")

	# Close must hide without changing the current selection.
	var selection_before := editor.semantic_content_option.selected
	editor._close_monster_inspector()
	assert(not editor.monster_inspector_panel.visible, "inspector not hidden after close")
	assert(editor.semantic_content_option.selected == selection_before, "close must not change selection")

	editor.queue_free()
	print("MSE_MONSTER_INSPECTOR_PASS: sidebar=%d inspector=%d" % [sidebar_base, inspector_width_76])
	get_tree().quit(0)


func _find_unverified_with_stats() -> Dictionary:
	for kind: String in ["monster_spawn", "boss_spawn", "special_monster", "unresolved_monster"]:
		for entry: Dictionary in MapEditorContentCatalogService.entries(kind, 4):
			if not bool(entry.get("attributes_verified", false)):
				if entry.get("level", null) != null or entry.get("hp", null) != null:
					return entry
	return {}


func _find_monster_tree_item(editor: MapEditorApp, monster_id: int) -> TreeItem:
	var root := editor.semantic_catalog_tree.get_root()
	if root == null:
		return null
	var pending: Array[TreeItem] = [root]
	while not pending.is_empty():
		var item: TreeItem = pending.pop_back()
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and int(metadata.get("entry", {}).get("monster_id", -1)) == monster_id:
			return item
		var child := item.get_first_child()
		while child != null:
			pending.push_back(child)
			child = child.get_next()
	return null
