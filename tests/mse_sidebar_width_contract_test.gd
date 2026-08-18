extends Node

const MapEditorAppScript := preload("res://scripts/map_editor/map_editor_app.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapEditorContentCatalogService.reset_source_parse_counts()
	var ordinary := MapEditorContentCatalogService.entries("monster_spawn", 4)
	var elite_boss := MapEditorContentCatalogService.entries("boss_spawn", 4)
	var special := MapEditorContentCatalogService.entries("special_monster", 4)
	var unresolved := MapEditorContentCatalogService.entries("unresolved_monster", 4)
	var total := ordinary.size() + elite_boss.size() + special.size() + unresolved.size()
	assert(total == 214, "catalog total drifted: %d" % total)
	assert(ordinary.size() == 133, "ordinary count %d" % ordinary.size())
	assert(elite_boss.size() == 50, "elite_boss count %d" % elite_boss.size())
	assert(special.size() == 31, "special count %d" % special.size())
	assert(unresolved.size() == 0, "unresolved count %d" % unresolved.size())

	var woma := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 76)
	assert(not woma.is_empty(), "ID 76 沃玛教主 missing")
	assert(int(woma.get("drop_entry_count", 0)) == 33, "ID 76 drops %d" % int(woma.get("drop_entry_count", 0)))
	var dark_woma := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 239)
	assert(not dark_woma.is_empty(), "ID 239 暗之沃玛教主 missing")
	assert(int(dark_woma.get("drop_entry_count", 0)) == 54, "ID 239 drops %d" % int(dark_woma.get("drop_entry_count", 0)))
	var dark_rainbow := MapEditorContentCatalogService.find_by_monster_id("boss_spawn", 240)
	assert(not dark_rainbow.is_empty(), "ID 240 暗之虹魔教主 missing from boss_spawn")
	assert(MapEditorContentCatalogService.find_by_monster_id("unresolved_monster", 240).is_empty(), "ID 240 must NOT be in unresolved_monster")
	assert(str(dark_rainbow.get("classification", "")) == "boss", "ID 240 must be classification boss")
	assert(int(dark_rainbow.get("drop_entry_count", 0)) == 54, "ID 240 drops %d" % int(dark_rainbow.get("drop_entry_count", 0)))
	assert(not bool(dark_rainbow.get("authoring_allowed", false)), "ID 240 placement policy must stay closed")
	assert(not bool(dark_rainbow.get("runtime_ready", false)), "ID 240 must not be runtime-ready")

	# Retired identities (鸡/鹿/鹿1) are excluded from the canonical catalog
	# and must stay absent from every browse group.
	for mid: int in [14, 16, 17]:
		assert(MapEditorContentCatalogService.find_any_monster(mid).is_empty(), "retired identity must stay absent: %d" % mid)
	var vd := MapEditorContentCatalogService.find_by_monster_id("special_monster", 78)
	assert(not vd.is_empty(), "ID78 version_difference must be visible")
	assert(not bool(vd.get("authoring_allowed", false)), "version_difference must not be authoring-allowed")

	var editor := MapEditorAppScript.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	editor.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var base := int(editor.sidebar_scroll.size.x)
	assert(base <= 340, "sidebar too wide: %d" % base)
	for folder_prefix: String in ["普通怪物", "精英与Boss", "特殊怪物", "待分类 / 待核验"]:
		_expand_folder(editor, folder_prefix)
		await get_tree().process_frame
		var after := int(editor.sidebar_scroll.size.x)
		assert(after - base <= 2, "sidebar widened after %s: %d -> %d" % [folder_prefix, base, after])
	editor.queue_free()
	print(
		"MSE_SIDEBAR_WIDTH_CONTRACT_PASS: total=%d ordinary=%d elite_boss=%d special=%d unresolved=%d sidebar=%d"
		% [total, ordinary.size(), elite_boss.size(), special.size(), unresolved.size(), base]
	)
	get_tree().quit(0)


func _expand_folder(editor: MapEditorApp, folder_prefix: String) -> void:
	var root := editor.semantic_catalog_tree.get_root()
	if root == null:
		return
	var child := root.get_first_child()
	while child != null:
		if str(child.get_text(0)).begins_with(folder_prefix):
			child.collapsed = false
			return
		child = child.get_next()
