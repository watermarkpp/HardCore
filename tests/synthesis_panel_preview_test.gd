extends Node

const EnhancementPanelScript := preload("res://scripts/enhancement_panel.gd")
const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	var panel := EnhancementPanelScript.new() as Control
	add_child(panel)
	for frame in 5:
		await get_tree().process_frame
	panel.call("_set_mode", "synthesis")
	for frame in 4:
		await get_tree().process_frame
	var scroll := panel.get_node("ForgeArtworkPanel/SynthesisRecipeScroll") as ScrollContainer
	var grid := scroll.get_node("SynthesisRecipeGrid") as GridContainer
	assert(scroll.visible and grid.columns == 4)
	assert(grid.get_child_count() == 40)
	assert(scroll.position.distance_to(Vector2(81.8460922241211, 14.0000066757202)) < 0.2, "user-calibrated recipe position changed")
	assert(absf(scroll.size.x - 239.93994140625) < 0.2, "user-calibrated recipe width changed")
	assert(scroll.size.y == 3 * InventoryPanelScript.BAG_CELL_SIZE.y + 2 * InventoryPanelScript.BAG_VERTICAL_SEPARATION)
	var chance_title := panel.get_node("ForgeChancePanel/ChanceFrame/Title") as Label
	var fee_title := panel.get_node("ForgeChancePanel/FeeFrame/Title") as Label
	var rules_title := panel.get_node("ForgeRulesPanel/ForgeRulesTitle") as Label
	assert(scroll.get_global_rect().end.y < chance_title.get_global_rect().position.y, "recipe viewport overlaps success-rate title")
	for title: Label in [rules_title, chance_title, fee_title]:
		assert(title.get_theme_font_size("font_size") == 18, "synthesis heading must render at 30 physical pixels")
	assert(grid.size.y > scroll.size.y and scroll.get_v_scroll_bar().max_value > scroll.size.y, "40 recipe cells must be vertically scrollable")
	for index in 40:
		var cell := grid.get_child(index) as Button
		assert(cell.size == InventoryPanelScript.BAG_CELL_SIZE and cell.disabled)
		assert(cell.get_theme_stylebox("disabled") == panel.forge_slots[0].get_theme_stylebox("disabled"), "recipe cells must match inventory cells")
	for art: TextureRect in panel.forge_artwork.values():
		assert(not art.visible, "forge result art must be absent in synthesis mode")
	assert(panel.forge_button.text == "开始合成" and panel.forge_button.disabled)
	assert((panel.get_node("ForgeRulesPanel/ForgeRulesText") as Label).text == "请选择合成配方")
	var entries: Array[Dictionary] = [{"title": "测试图标", "details": "测试材料 ×2", "icon": preload("res://assets/ui/forge/forge_initial.png")}]
	panel.set_synthesis_recipe_previews(entries)
	assert(not (grid.get_child(0) as Button).disabled)
	panel.call("_on_synthesis_recipe_pressed", 0)
	assert((panel.get_node("ForgeRulesPanel/ForgeRulesText") as Label).text == "测试材料 ×2")
	var gold_before := PlayerState.gold
	var inventory_before := PlayerState.inventory.duplicate(true)
	panel.preview_synthesis_animation()
	await get_tree().create_timer(0.25).timeout
	assert(panel._forging and panel._synthesis_audio.playing)
	assert((panel._forge_glow_overlays[0] as Panel).modulate.a > 0.0)
	await get_tree().create_timer(2.85).timeout
	assert(not panel._forging and not panel._synthesis_audio.playing)
	assert(panel._synthesis_audio_plays_in_cycle == 1, "synthesis sound must play exactly once")
	assert((panel._forge_glow_overlays[0] as Panel).modulate.a == 0.0)
	assert(PlayerState.gold == gold_before and PlayerState.inventory == inventory_before, "UI preview must not commit a recipe")
	panel.call("_set_mode", "forge")
	for frame in 4:
		await get_tree().process_frame
	assert(not scroll.visible and (panel.forge_artwork["ForgeImageInitial"] as TextureRect).visible)
	assert(panel.forge_button.text == "开始锻造")
	for title: Label in [rules_title, chance_title, fee_title]:
		assert(title.get_theme_font_size("font_size") == 18, "forge heading must render at 30 physical pixels")
	print("SYNTHESIS_PANEL_PREVIEW_PASS")
	get_tree().quit(0)
