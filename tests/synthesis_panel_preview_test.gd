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
		assert(cell.size == InventoryPanelScript.BAG_CELL_SIZE and cell.disabled == (index >= 12))
		assert(cell.get_theme_stylebox("disabled") == panel.forge_slots[0].get_theme_stylebox("disabled"), "recipe cells must match inventory cells")
		if index < 12:
			var recipe: Dictionary = panel._synthesis_recipe_previews[index]
			var profession_identity := preload("res://scripts/identity/entity_registry.gd").resolve(str(recipe.get("profession", "")), "profession")
			assert(not profession_identity.is_empty(), "recipe must use a registered profession ID")
			assert((cell.get_node("RecipeProfession") as Label).text == str(profession_identity.display_name).left(1))
	assert(int(panel._synthesis_recipe_previews[9].get("item_id", -1)) == 950201)
	assert(int(panel._synthesis_recipe_previews[10].get("item_id", -1)) == 950202)
	assert(int(panel._synthesis_recipe_previews[11].get("item_id", -1)) == 950203)
	var heart := GameData.get_item_record({"item_id": 950102})
	assert(preload("res://scripts/item_detail_presenter.gd").format_item(heart, {}, {"recipe_profession": "hc.profession.wizard"}).contains("随机法师技能等级 +1"))
	for art: TextureRect in panel.forge_artwork.values():
		assert(not art.visible, "forge result art must be absent in synthesis mode")
	assert(panel.forge_button.text == "开始合成" and panel.forge_button.disabled, "missing recipe must keep action disabled")
	assert((panel.get_node("ForgeRulesPanel/ForgeRulesText") as Label).text == "请选择合成配方")
	panel.call("_on_synthesis_recipe_pressed", 0)
	assert((panel.get_node("ForgeRulesPanel/ForgeRulesText") as Label).text == "材料需求：远古圣物碎片 ×4")
	assert(panel.chance_label.text.contains("100%") and panel.fee_label.text.contains("400000"))
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
	assert(PlayerState.gold == gold_before and PlayerState.inventory == inventory_before and PlayerState.synthesis_tray == PlayerState._empty_workbench_tray(), "UI preview must not commit a recipe")
	PlayerState.gold = 500000
	panel._selected_synthesis_recipe = -1
	for _fragment in 4:
		assert(bool(PlayerState.receive("远古圣物碎片", 1, false).get("success", false)))
	for material_slot: int in [2, 4, 6, 8]:
		panel.selected_inventory_index = _fragment_index()
		panel.call("_on_forge_slot_pressed", material_slot)
		assert(not PlayerState.synthesis_tray[material_slot].is_empty())
	assert(panel.forge_button.disabled, "materials before recipe must be accepted without enabling an invalid action")
	panel.call("_on_synthesis_recipe_pressed", 0)
	assert(not panel.forge_button.disabled)
	assert(PlayerState.receive("远古圣物碎片", 1, false).success)
	assert(PlayerState.place_workbench_item("synthesis", 1, _fragment_index()).success)
	panel._refresh_forge_information()
	assert(panel.forge_button.disabled, "extra materials must disable synthesis")
	assert(PlayerState.take_workbench_item("synthesis", 1).success)
	panel._refresh_forge_information()
	assert(not panel.forge_button.disabled)
	panel.forge_button.pressed.emit()
	assert(panel._forging)
	await get_tree().create_timer(3.1).timeout
	assert(not panel._forging and int(PlayerState.synthesis_tray[0].get("item_id", -1)) == 950101)
	panel.hide()
	panel.show()
	for frame in 3:
		await get_tree().process_frame
	assert(panel.forge_slots[0].get_node("CenteredPixelIcon").visible, "unclaimed relic disappeared when panel reopened")
	panel.call("_on_forge_slot_pressed", 0)
	assert(not PlayerState.synthesis_tray[0].is_empty(), "first click must show item detail")
	panel.call("_on_forge_slot_pressed", 0)
	assert(PlayerState.synthesis_tray[0].is_empty() and _relic_index() >= 0, "relic was not moved into the backpack")
	panel.call("_set_mode", "forge")
	for frame in 4:
		await get_tree().process_frame
	assert(not scroll.visible and (panel.forge_artwork["ForgeImageInitial"] as TextureRect).visible)
	assert(panel.forge_button.text == "开始锻造")
	for title: Label in [rules_title, chance_title, fee_title]:
		assert(title.get_theme_font_size("font_size") == 18, "forge heading must render at 30 physical pixels")
	print("SYNTHESIS_PANEL_PREVIEW_PASS")
	get_tree().quit(0)


func _fragment_index() -> int:
	for index in PlayerState.inventory.size():
		if str(PlayerState.inventory[index].get("name", "")) == "远古圣物碎片":
			return index
	return -1


func _relic_index() -> int:
	for index in PlayerState.inventory.size():
		if int(PlayerState.inventory[index].get("item_id", -1)) == 950101:
			return index
	return -1
