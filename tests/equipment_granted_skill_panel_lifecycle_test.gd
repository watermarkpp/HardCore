extends Node

## UI lifecycle fixture for equipment grant rows. The root-owned state fixture
## controls availability; this test only exercises SkillPanel's synchronization
## boundary and verifies that ordinary rows survive equip/unequip refreshes.
const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillLoadoutRulesScript := preload("res://scripts/skill_loadout_rules.gd")
const Icons := preload("res://scripts/hud_skill_icon_catalog.gd")
const ItemTextures := preload("res://scripts/ui_item_texture_cache.gd")
const HUDScript := preload("res://scripts/hud.gd")


func _ready() -> void:
	var panel := SkillPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	assert(panel.has_method("_sync_equipment_granted_entries"))
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	var skill_id := "hc.skill.equipment.ring_teleport"
	assert(not PlayerState.is_skill_available(skill_id))
	PlayerState.add_item("传送戒指")
	var item_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "传送戒指":
			item_index = index
	assert(item_index >= 0)
	assert(PlayerState.equip_inventory_index(item_index).begins_with("已装备"))
	assert(PlayerState.is_skill_available(skill_id))
	panel.open_for("技能导师")
	assert(_grant_count(panel) == 1, "wear must add exactly one grant row")
	assert(_ordinary_count(panel) > 0, "ordinary skill rows must remain")
	var grant_index := _grant_index(panel, skill_id)
	var captured: Dictionary = {"request": {}}
	panel.skill_button_assignment_requested.connect(func(request: Dictionary) -> void:
		captured["request"] = request.duplicate(true)
	)
	panel._open_assignment_popup_for(grant_index)
	assert(panel.assignment_popup.visible, "available equipment grant did not open assignment popup")
	panel._assign_selected_to_target("attack_ring", 0)
	var emitted_request: Dictionary = captured["request"]
	assert(not emitted_request.is_empty(), "panel did not emit grant assignment request")
	assert(SkillDataLoaderScript.entity_skill_id(str(emitted_request.get("skill_id", ""))) == skill_id, "panel emitted wrong grant identity")
	var assignment_result := SkillLoadoutRulesScript.assign_button_slot(
		PlayerState.skill_button_assignments_snapshot(),
		PlayerState.skill_assignment_roster(),
		emitted_request,
	)
	assert(bool(assignment_result.get("ok", false)), "formal loadout rejected available equipment grant")
	assert(PlayerState.apply_skill_button_assignment(assignment_result))
	assert(PlayerState.skill_id_for_slot("attack_ring", 0) == skill_id)
	var record := GameData.get_entity_record("hc.item.000254")
	var expected_texture := ItemTextures.texture_for(record, "inventoryIcon")
	var actual_texture := Icons.texture_for(skill_id)
	assert(actual_texture != null and expected_texture != null)
	assert(actual_texture == expected_texture or actual_texture.resource_path == expected_texture.resource_path)
	assert(PlayerState.unequip_slot("hc.slot.ring_left").begins_with("已卸下"))
	panel.refresh()
	assert(_grant_count(panel) == 0, "unequip must remove grant row")
	assert(PlayerState.skill_id_for_slot("attack_ring", 0).is_empty(), "unequip must revoke grant assignment")
	panel.assignment_popup.hide()
	panel._open_assignment_popup_for(grant_index)
	assert(not panel.assignment_popup.visible, "unworn grant reopened assignment popup")
	PlayerState.add_item("传送戒指")
	item_index = -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "传送戒指":
			item_index = index
	assert(PlayerState.equip_inventory_index(item_index).begins_with("已装备"))
	panel.refresh()
	assert(_grant_count(panel) == 1, "rewear must restore grant row")
	var ring: Dictionary = PlayerState.equipment["hc.slot.ring_left"]
	PlayerState.damage_equipment_durability("hc.slot.ring_left", int(ring.get("max_durability", ring.get("max_durability_raw", 1))))
	panel.refresh()
	assert(_grant_count(panel) == 0, "durability zero must remove grant row")
	var hud := HUDScript.new()
	assert(hud.get_node_or_null("SpecialActionButton") == null)
	assert(not hud.has_signal("special_action_pressed"))
	print("EQUIPMENT_GRANTED_SKILL_PANEL_LIFECYCLE_PASS wear=1 unequip=0 rewear=1 dur0=0 ordinary=%d" % _ordinary_count(panel))
	hud.free()
	panel.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _grant_count(panel: Node) -> int:
	var count := 0
	for raw_entry: Variant in panel.skill_entries:
		if raw_entry is Dictionary and bool((raw_entry as Dictionary).get("equipment_granted", false)):
			count += 1
	return count


func _grant_index(panel: Node, skill_id: String) -> int:
	for index in range(panel.skill_entries.size()):
		var entry: Dictionary = panel.skill_entries[index]
		if bool(entry.get("equipment_granted", false)) and str(entry.get("skill_id", "")) == skill_id:
			return index
	return -1


func _ordinary_count(panel: Node) -> int:
	return panel.skill_entries.size() - _grant_count(panel)
