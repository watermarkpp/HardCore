extends Control

const Layout := preload("res://scripts/ui_runtime_layout_overrides.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const Profiles := preload("res://scripts/test_character_skill_profiles.gd")
const SkillLoadoutRules := preload("res://scripts/skill_loadout_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var _remove_on_callback := false
var _proof := Proof.new()
var _errors: Array[String] = []

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value:
		_errors.append(label)

func _ready() -> void:
	var label := Label.new()
	label.name = "Label"
	label.text = "label"
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)
	var rich := RichTextLabel.new()
	rich.name = "RichText"
	rich.text = "rich"
	rich.add_theme_font_size_override("normal_font_size", 16)
	add_child(rich)
	var button := Button.new()
	button.name = "Button"
	button.text = "button"
	button.add_theme_font_size_override("font_size", 20)
	add_child(button)
	await get_tree().process_frame
	var captured := Layout.capture_external_profile(self, "inventory", {
		"Label": {}, "RichText": {}, "Button": {},
	})
	_check(captured.get("profiles", {}).get("inventory", {}).get("nodes", {}).get("Label", {}).has("logicalFontSize"), "Label capture lost logicalFontSize")
	_check(captured.get("profiles", {}).get("inventory", {}).get("nodes", {}).get("RichText", {}).has("logicalFontSize"), "RichTextLabel capture lost logicalFontSize")
	_check(int(captured.profiles.inventory.nodes.Label.logicalFontSize) == 24, "Label checkpoint font mismatch")
	_check(int(captured.profiles.inventory.nodes.RichText.logicalFontSize) == 16, "RichTextLabel checkpoint font mismatch")
	_check(int(captured.profiles.inventory.nodes.Button.logicalFontSize) == 20, "Button checkpoint font mismatch")
	var contract := {"schemaVersion": Layout.SCHEMA_VERSION, "profiles": {"inventory": {"logicalDesignSize": [1152, 648], "nodes": {
		"Label": {"logicalRect": [0, 0, 80, 24], "logicalFontSize": 32.0},
		"RichText": {"logicalRect": [0, 30, 120, 30], "logicalFontSize": 28.0},
		"Button": {"logicalRect": [0, 70, 100, 32], "logicalFontSize": 26.0},
	}}}}
	var applied := await Layout.apply_external_profile_transaction(self, "inventory", contract)
	_check(applied.ok, "font transaction failed: %s" % applied)
	_check(label.get_theme_font_size("font_size") == 32, "Label logical font was not applied")
	_check(rich.get_theme_font_size("normal_font_size") == 28, "RichTextLabel normal_font_size was not applied")
	_check(button.get_theme_font_size("font_size") == 26, "Button logical font was not applied")
	var checkpoint_apply := await Layout.apply_external_profile_transaction(self, "inventory", captured)
	_check(checkpoint_apply.ok, "capture checkpoint could not be reapplied")
	_check(label.get_theme_font_size("font_size") == 24 and rich.get_theme_font_size("normal_font_size") == 16 and button.get_theme_font_size("font_size") == 20, "checkpoint did not restore original overrides")
	var old_label := label.get_theme_font_size("font_size")
	var old_rich := rich.get_theme_font_size("normal_font_size")
	var old_button := button.get_theme_font_size("font_size")
	var failure_contract := contract.duplicate(true)
	failure_contract.profiles.inventory.nodes.Label.logicalFontSize = 31.0
	failure_contract.profiles.inventory.nodes.RichText.logicalFontSize = 29.0
	failure_contract.profiles.inventory.nodes.Button.logicalFontSize = 27.0
	var root_parent := get_parent()
	_remove_on_callback = true
	var failed := await Layout.apply_external_profile_transaction(self, "inventory", failure_contract)
	_check(not failed.ok and failed.rolledBack, "callback failure did not rollback")
	_check(label.get_theme_font_size("font_size") == old_label and rich.get_theme_font_size("normal_font_size") == old_rich and button.get_theme_font_size("font_size") == old_button, "rollback did not restore font keys")
	root_parent.add_child(self)
	var owner := Control.new()
	owner.size = Vector2(800, 600)
	add_child(owner)
	var equipment := Control.new()
	equipment.name = "EquipmentPanel"
	equipment.position = Vector2(100, 50)
	equipment.size = Vector2(500, 500)
	owner.add_child(equipment)
	var buttons := {}
	var slot_ids := ["hc.slot.relic", "hc.slot.weapon", "hc.slot.helmet", "hc.slot.necklace", "hc.slot.armor", "hc.slot.bracelet_left", "hc.slot.bracelet_right", "hc.slot.ring_left", "hc.slot.ring_right", "hc.slot.badge"]
	var slot_positions := {
		"hc.slot.relic": Vector2(20, 20), "hc.slot.weapon": Vector2(20, 100), "hc.slot.bracelet_left": Vector2(20, 180), "hc.slot.ring_left": Vector2(20, 260), "hc.slot.badge": Vector2(20, 340),
		"hc.slot.helmet": Vector2(230, 20), "hc.slot.necklace": Vector2(440, 20), "hc.slot.armor": Vector2(440, 100), "hc.slot.bracelet_right": Vector2(440, 180), "hc.slot.ring_right": Vector2(440, 260),
	}
	for index in slot_ids.size():
		var slot: String = slot_ids[index]
		var slot_button := Button.new()
		slot_button.position = slot_positions[slot]
		slot_button.size = Vector2(40, 40)
		equipment.add_child(slot_button)
		buttons[slot] = slot_button
	var region := Dock.equipment_region(owner, buttons)
	_check(region.side == "center" and region.region.size.x > 0.0 and region.region.size.y > 0.0, "stable slot equipment region failed")
	for slot: String in slot_ids:
		_check(not region.region.intersects(Dock.rect_in(owner, buttons[slot])), "equipment detail overlaps %s" % slot)
	var profile := Profiles.qa_v2_profile_for_profession("wizard")
	for profession in ["warrior", "wizard", "taoist"]:
		var profession_profile := Profiles.qa_v2_profile_for_profession(profession)
		_check(not profession_profile.is_empty() and profession_profile.learned_skill_ids.size() > 0, "empty QA skill profile: %s" % profession)
		var validation := SkillLoadoutRules.validate_assignments(profession_profile.button_assignments)
		_check(bool(validation.get("valid", false)) and profession_profile.attack_ring_slot_ids.size() == 6, "formal six ring validation failed: %s" % profession)
		for skill_id: String in profession_profile.attack_ring_slot_ids:
			_check(profession_profile.learned_skill_ids.has(skill_id), "unlearned skill entered ring: %s" % skill_id)
	var receipt_ok := _proof.write_receipt("dot_b27_ui_runtime_contract_20261010_test", _proof.records.size(), _errors.size())
	if receipt_ok and _errors.is_empty():
		print("DOT_B27_UI_RUNTIME_CONTRACT_20261010_TEST_PASS logical_font rich_text_rollback stable_slots six_ring")
	else:
		print("DOT_B27_UI_RUNTIME_CONTRACT_20261010_TEST_FAIL logical_font rich_text_rollback stable_slots six_ring")
	get_tree().quit(0 if receipt_ok and _errors.is_empty() else 1)

func _on_runtime_layout_profile_applied(_profile_id: String) -> void:
	if _remove_on_callback and get_parent() != null:
		get_parent().remove_child(self)
