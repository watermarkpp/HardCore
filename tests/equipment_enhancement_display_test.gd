extends Node

const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")
const NameStyle := preload("res://scripts/ui_item_name_style.gd")
const Rules := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	var panel := InventoryPanelScript.new()
	add_child(panel)
	for index in 3:
		await get_tree().process_frame
	var item := GameData.get_item_record({"item_id": 105})
	assert(item.name == "裁决之杖" and item.category == "武器")
	var view = panel.item_detail_presenter
	view.show_item(item)
	await get_tree().process_frame
	assert("攻击 0-30" in view.detail_label.get_parsed_text())
	assert(not view.forge_marker.visible)
	var history: Array[String] = []
	for stage in 7:
		history.append("attack_max")
	var instance := {"item_id": 105, "name": "裁决之杖", "enhancement": {
		"contract_id": Rules.CONTRACT_ID,
		"forge": {"stage": 7, "history": history, "modifiers": [{"stat": "attack_max", "op": "add", "value": 7}]},
	}}
	assert(Rules.validate_enhancement(instance.enhancement, "武器"))
	view.show_item(item, instance)
	await get_tree().process_frame
	assert(view.debug_layout_valid())
	assert(view.title_label.text == "裁决之杖" and view.forge_marker.text == "+7" and view.forge_marker.visible)
	assert(NameStyle.forge_suffix(item, instance) == "+7")
	assert(is_equal_approx(view.title_label.position.x + view.title_label.size.x / 2.0, view.size.x / 2.0), "forge suffix moved the original centered name")
	assert(view.forge_marker.position.x >= view.title_label.position.x + view.title_label.size.x + 1.0)
	assert(view.forge_marker.get_theme_color("font_color") == view.title_label.get_theme_color("font_color"))
	assert("攻击 0-37" in Detail.format_item(item, instance), "forge bonus must join the displayed final attack stat")
	assert("攻击 0-37" in view.detail_label.get_parsed_text())
	var invalid := instance.duplicate(true)
	invalid.enhancement.forge.modifiers[0].value = 8
	assert(NameStyle.forge_suffix(item, invalid).is_empty())
	assert("攻击 0-30" in Detail.format_item(item, invalid))
	print("EQUIPMENT_ENHANCEMENT_DISPLAY_PASS")
	get_tree().quit(0)
