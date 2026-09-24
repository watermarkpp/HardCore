extends Node

const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")
const EnhancementPanelScript := preload("res://scripts/enhancement_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded(), "forge panel test requires the item catalog")
	PlayerState.reset_progress(false)
	PlayerState.add_item("匕首")
	PlayerState.add_item("布衣(男)")
	var inventory := InventoryPanelScript.new() as Control
	var forge := EnhancementPanelScript.new() as Control
	add_child(inventory)
	add_child(forge)
	for frame_index in 5:
		await get_tree().process_frame
	var source_bag := inventory.get_node("BagPanel") as Control
	var forge_bag := forge.get_node("BagPanel") as Control
	assert(source_bag.get_rect().is_equal_approx(forge_bag.get_rect()), "forge bag moved away from the inventory source")
	assert(inventory.get_node("BagPanel/InventoryScroll").get_rect().is_equal_approx(forge.get_node("BagPanel/InventoryScroll").get_rect()), "forge bag viewport differs from the inventory source")
	assert(not (forge.get_node("AttributePanel") as Control).visible)
	assert(not (forge.get_node("EquipmentPanel") as Control).visible)
	var forge_grid := forge.get_node("ForgeMaterialPanel/ForgeMaterialGrid") as Control
	assert((forge.get_node("ForgeMaterialPanel/ForgeMaterialHint") as Label).text == "请依次放入需锻造装备与所需材料")
	assert(forge_grid.size.distance_to(Vector2(170, 200)) < 0.1, "forge grid must use bag cell dimensions and spacing")
	for index in 9:
		var forge_slot := forge.get_node("ForgeMaterialPanel/ForgeMaterialGrid/ForgeSlot_%d" % index) as Button
		assert(forge_slot.size.distance_to(InventoryPanelScript.BAG_CELL_SIZE) < 0.1, "forge slot differs from bag cell")
		assert(forge_slot.position.distance_to(Vector2((index % 3) * 57, (index / 3) * 68)) < 0.1, "forge slot spacing differs from bag")
		assert(forge_slot.get_theme_stylebox("normal") == forge_slot.get_theme_stylebox("disabled"), "empty forge slot must match empty bag appearance")
		assert(forge_slot.get_node_or_null("HCActivationOnce") != null, "forge slot must use bag cell activation guard")
		for state: StringName in [&"hover", &"pressed", &"hover_pressed"]:
			assert(forge_slot.get_theme_stylebox(state) == forge_slot.get_theme_stylebox("disabled"), "empty forge slot feedback differs from empty bag")
	assert((forge.get_node("ForgeRulesPanel/ForgeRulesTitle") as Label).text == "材料需求")
	var material_frame := forge.get_node("ForgeRulesPanel/PlainButtonFrame") as NinePatchRect
	var material_text := forge.get_node("ForgeRulesPanel/ForgeRulesText") as Label
	assert(material_frame.size.y >= 96.0, "material frame is too short for two lines")
	assert(absf(material_frame.position.x + material_frame.size.x * 0.5 - material_text.position.x - material_text.size.x * 0.5) < 3.0, "material text is not horizontally centered in its frame")
	assert(absf(material_frame.position.y + material_frame.size.y * 0.5 - material_text.position.y - material_text.size.y * 0.5) < 0.5, "material text is not vertically centered in its frame")
	assert((forge.get_node("ForgeChancePanel/ChanceFrame/PlainButtonFrame") as TextureRect).size.x > 0)
	var initial_art := forge.get_node("ForgeArtworkPanel/ForgeImageInitial") as TextureRect
	assert(initial_art.size.x > 0)
	for result_name in ["ForgeImageSuccess", "ForgeImageFailure"]:
		var result_art := forge.get_node("ForgeArtworkPanel/" + result_name) as TextureRect
		assert(result_art.get_rect().is_equal_approx(initial_art.get_rect()), "%s must match the calibrated initial artwork" % result_name)
	assert((forge.get_node("ForgeButton") as Button).disabled, "forge button must stay disabled until materials are selected")
	var requirements := forge.get_node("ForgeRulesPanel/ForgeRulesText") as Label
	assert(requirements.text == "请在上方放入需要锻造的装备")
	assert(requirements.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and requirements.vertical_alignment == VERTICAL_ALIGNMENT_CENTER)
	var weapon_index := _find_inventory_name("匕首")
	assert(weapon_index >= 0)
	forge.set("selected_inventory_index", weapon_index)
	forge.call("_on_forge_slot_pressed", 4)
	assert(requirements.text == "材料需求：黑铁矿 ×1\n首饰 ×2")
	assert((forge.get_node("ForgeMaterialPanel/ForgeMaterialGrid/ForgeSlot_4") as Button).theme_type_variation == "GothicComponentSelectedSlotButton")
	forge.call("_on_forge_slot_pressed", 4)
	var item_detail := forge.get_node("ItemDetailPresenter") as Control
	assert(item_detail.visible, "clicking the placed equipment must show its attributes")
	var grid_rect := preload("res://scripts/ui_item_detail_dock.gd").rect_in(forge, forge_grid)
	assert(absf(item_detail.position.x + item_detail.size.x - (grid_rect.position.x - 20.0)) < 0.5, "item detail must sit 20 px left of the forge grid")
	assert(absf(item_detail.position.y - grid_rect.position.y) < 0.5, "item detail top must align with forge grid")
	assert(absf(item_detail.size.y - grid_rect.size.y) < 1.0, "item detail height must match forge grid")
	var armor_index := _find_inventory_name("布衣(男)")
	assert(armor_index >= 0)
	forge.set("selected_inventory_index", armor_index)
	forge.call("_on_forge_slot_pressed", 4)
	assert(requirements.text == "材料需求：黑铁矿 ×1\n首饰 ×2")
	print("FORGE_PANEL_LAYOUT_PASS")
	get_tree().quit(0)


func _find_inventory_name(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[index]
		if record is Dictionary and str((record as Dictionary).get("name", "")) == item_name:
			return index
	return -1
