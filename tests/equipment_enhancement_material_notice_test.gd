extends Node

const EnhancementPanelScript := preload("res://scripts/enhancement_panel.gd")

class NoticeHost extends Control:
	var messages: Array[String] = []

	func show_error_message(message: String, _seconds := 2.0) -> void:
		messages.append(message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	for item_id: int in [81, 940010, 252, 191]:
		var catalog := GameData.get_item_record({"item_id": item_id})
		assert(not catalog.is_empty())
		assert(bool(PlayerState.receive_record({"item_id": item_id, "name": str(catalog.name)}, false).success))
	var host := NoticeHost.new()
	add_child(host)
	var forge := EnhancementPanelScript.new()
	host.add_child(forge)
	for frame in 4:
		await get_tree().process_frame
	for placement: Array in [[81, 4], [940010, 1], [252, 3], [191, 5]]:
		var inventory_index := _index_for_id(int(placement[0]))
		assert(inventory_index >= 0)
		forge.selected_inventory_index = inventory_index
		forge._on_forge_slot_pressed(int(placement[1]))
	var special_slot := forge.get_node("ForgeMaterialPanel/ForgeMaterialGrid/ForgeSlot_3") as Button
	assert(special_slot.theme_type_variation == "GothicComponentSelectedSlotButton", "forbidden jewelry should still be placeable for explicit submit feedback")
	assert(not forge.forge_button.disabled, "forbidden material must allow a real button press")
	var inventory_before := PlayerState.inventory.duplicate(true)
	var gold_before := PlayerState.gold
	forge.forge_button.pressed.emit()
	assert(host.messages.back() == "麻痹戒指不可以作为锻造材料")
	assert(PlayerState.inventory == inventory_before and PlayerState.gold == gold_before, "rejected forge consumed resources")
	print("EQUIPMENT_ENHANCEMENT_MATERIAL_NOTICE_PASS")
	get_tree().quit(0)


func _index_for_id(item_id: int) -> int:
	for index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[index]
		if record is Dictionary and int((record as Dictionary).get("item_id", -1)) == item_id:
			return index
	return -1
