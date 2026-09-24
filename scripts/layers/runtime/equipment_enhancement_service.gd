class_name EquipmentEnhancementService
extends RefCounted

const Rules := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")
const Grade := preload("res://scripts/layers/rules/equipment_enhancement_grade.gd")
const BlackIron := preload("res://scripts/layers/rules/equipment_enhancement_black_iron.gd")

var _player
var _rng := RandomNumberGenerator.new()
var _session_id := ""
var _serial := 0
var _issued: Dictionary = {}
var _consumed: Dictionary = {}
var _enhancement_transaction_in_progress := false


func _init(player: Node) -> void:
	_player = player
	_rng.randomize()
	_session_id = "%d:%d" % [Time.get_ticks_usec(), _rng.randi()]


func configure_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


func reset() -> void:
	_issued.clear()
	_consumed.clear()
	_enhancement_transaction_in_progress = false


func quote_forge(target_index: int, iron_index: int, accessory_a_index: int, accessory_b_index: int) -> Dictionary:
	var quote := _build_quote(target_index, iron_index, accessory_a_index, accessory_b_index)
	if not bool(quote.get("valid", false)):
		return quote
	_serial += 1
	quote["quote_id"] = "forge:%s:%d" % [_session_id, _serial]
	if _issued.size() >= 128:
		_issued.clear()
	_issued[quote.quote_id] = quote.duplicate(true)
	return quote


func commit_forge(quote: Dictionary) -> Dictionary:
	var quote_id := str(quote.get("quote_id", ""))
	if _enhancement_transaction_in_progress:
		return _failure("锻造正在进行，请稍候。")
	if quote_id.is_empty() or _consumed.has(quote_id) or not _issued.has(quote_id) or _issued[quote_id] != quote:
		return _failure("锻造报价已失效，请重新选择材料。")
	var refreshed := _build_quote(int(quote.target_index), int(quote.iron_index), int(quote.accessory_a_index), int(quote.accessory_b_index))
	if not bool(refreshed.get("valid", false)):
		return refreshed
	var expected := quote.duplicate(true)
	expected.erase("quote_id")
	if refreshed != expected:
		return _failure("装备或材料已变化，请重新选择。")
	if int(_player.gold) < int(quote.gold_cost):
		return _failure("金币不足，无法锻造。")
	_enhancement_transaction_in_progress = true
	_consumed[quote_id] = true
	_issued.erase(quote_id)
	var inventory_before: Array = _player.inventory.duplicate(true)
	var gold_before: int = _player.gold
	var next_inventory := inventory_before.duplicate(true)
	var target_index := int(quote.target_index)
	var target: Dictionary = (next_inventory[target_index] as Dictionary).duplicate(true)
	var catalog := GameData.get_item_record(target)
	var roll := _rng.randi_range(0, 9999)
	var forge_succeeded := roll < int(quote.final_success_bps)
	var history: Array = []
	if forge_succeeded:
		var previous: Variant = target.get("enhancement", {})
		if previous is Dictionary:
			var previous_forge: Variant = (previous as Dictionary).get("forge", {})
			if previous_forge is Dictionary:
				history = (previous_forge as Dictionary).get("history", []).duplicate(true)
		history.append(_success_stat(quote, next_inventory))
	var totals := {}
	for raw_stat: Variant in history:
		var stat := str(raw_stat)
		totals[stat] = int(totals.get(stat, 0)) + 1
		if stat == "defense_max":
			totals["magic_defense_max"] = int(totals.get("magic_defense_max", 0)) + 1
	var modifiers: Array = []
	for stat: String in totals:
		modifiers.append({"stat": stat, "op": "add", "value": int(totals[stat])})
	target["enhancement"] = {
		"contract_id": Rules.CONTRACT_ID,
		"forge": {"stage": history.size(), "modifiers": modifiers, "history": history},
	}
	if not Rules.validate_enhancement(target.enhancement, str(catalog.get("category", ""))) or (target.has("drop_instance_contract_id") and not GameData.validate_item_drop_instance(target)):
		_enhancement_transaction_in_progress = false
		return _failure("装备锻造数据校验失败，物品未改变。")
	next_inventory[target_index] = target
	for material_index: int in [int(quote.iron_index), int(quote.accessory_a_index), int(quote.accessory_b_index)]:
		var material: Dictionary = next_inventory[material_index]
		var count := int(material.get("count", 1))
		if count <= 1:
			next_inventory[material_index] = {}
		else:
			material["count"] = count - 1
	_player.inventory = next_inventory
	_player.gold = gold_before - int(quote.gold_cost)
	if not bool(_player.call("_commit_save")):
		_player.inventory = inventory_before
		_player.gold = gold_before
		_enhancement_transaction_in_progress = false
		return _failure("锻造存档失败，装备、材料和金币均未改变。")
	_enhancement_transaction_in_progress = false
	_player.emit_signal("inventory_changed")
	_player.emit_signal("profile_changed")
	return {
		"valid": true,
		"committed": true,
		"forge_succeeded": forge_succeeded,
		"stage_after": history.size(),
		"message": "锻造成功" if forge_succeeded else "锻造失败，锻造等级已归零",
	}


func _build_quote(target_index: int, iron_index: int, accessory_a_index: int, accessory_b_index: int) -> Dictionary:
	var indices := [target_index, iron_index, accessory_a_index, accessory_b_index]
	var inventory: Array = _player.inventory
	var seen_indices := {}
	for index: int in indices:
		if index < 0 or index >= inventory.size() or seen_indices.has(index):
			return _failure("请依次放入需锻造装备与所需材料。")
		seen_indices[index] = true
	if seen_indices.size() != 4:
		return _failure("请依次放入需锻造装备与所需材料。")
	var records: Array[Dictionary] = []
	for index: int in indices:
		var value: Variant = inventory[index]
		if not value is Dictionary or (value as Dictionary).is_empty():
			return _failure("装备或材料已变化，请重新选择。")
		records.append(value)
	var target_item := GameData.get_item_record(records[0])
	var target_id := int(target_item.get("itemId", -1))
	var category := str(target_item.get("category", ""))
	var stage_before := Rules.forge_stage(records[0])
	var target_grade := Grade.grade_for_id(target_id)
	if str(target_item.get("kind", "")) != "equipment" or category not in ["武器", "盔甲", "头盔"] or target_grade < 0 or stage_before < 0:
		return _failure("只能锻造武器、衣服或头盔。")
	if records[0].has("enhancement") and not Rules.validate_enhancement(records[0].enhancement, category):
		return _failure("装备锻造数据无效。")
	if stage_before >= Rules.max_stage(category):
		return _failure("这件装备已达到锻造等级上限。")
	var purity := BlackIron.purity_for(records[1])
	if purity < 0:
		return _failure("请放入黑铁矿。")
	var accessories: Array[Dictionary] = []
	var grades: Array[int] = []
	for record: Dictionary in [records[2], records[3]]:
		var accessory := GameData.get_item_record(record)
		var accessory_id := int(accessory.get("itemId", -1))
		if not Grade.can_use_as_accessory_material(accessory_id):
			return _failure("%s不可以作为锻造材料" % str(accessory.get("name", record.get("name", "该物品"))))
		accessories.append(accessory)
		grades.append(Grade.grade_for_id(accessory_id))
	var probability := Rules.quote_probability(category, stage_before + 1, purity, target_grade, grades[0], grades[1])
	var cost := Rules.forge_gold_cost(category, stage_before + 1)
	if probability.is_empty() or cost < 0:
		return _failure("锻造规则不可用。")
	var result := {
		"valid": true,
		"profile_id": str(_player.active_profile_id),
		"target_index": target_index,
		"iron_index": iron_index,
		"accessory_a_index": accessory_a_index,
		"accessory_b_index": accessory_b_index,
		"target_instance_id": str(records[0].get("instance_id", "")),
		"target_item_id": target_id,
		"target_stage_before": stage_before,
		"target_stage_after": stage_before + 1,
		"black_iron_item_id": int(records[1].get("item_id", -1)),
		"black_iron_purity": purity,
		"accessory_a_identity": str(records[2].get("instance_id", "slot:%d" % accessory_a_index)),
		"accessory_b_identity": str(records[3].get("instance_id", "slot:%d" % accessory_b_index)),
		"accessory_a_grade": grades[0],
		"accessory_b_grade": grades[1],
		"raw_success_bps": int(probability.raw_success_bps),
		"difficulty_scale_bps": int(probability.difficulty_scale_bps),
		"final_success_bps": int(probability.final_success_bps),
		"gold_cost": cost,
		"inventory_snapshot_digest": JSON.stringify(inventory).sha256_text(),
		"equipment_snapshot_digest": JSON.stringify(_player.equipment).sha256_text(),
	}
	return result


func _success_stat(quote: Dictionary, inventory: Array) -> String:
	var target := GameData.get_item_record(inventory[int(quote.target_index)])
	if str(target.get("category", "")) != "武器":
		return "defense_max"
	var accessory_a := GameData.get_item_record(inventory[int(quote.accessory_a_index)])
	var accessory_b := GameData.get_item_record(inventory[int(quote.accessory_b_index)])
	accessory_a["modifiers"] = (inventory[int(quote.accessory_a_index)] as Dictionary).get("modifiers", [])
	accessory_b["modifiers"] = (inventory[int(quote.accessory_b_index)] as Dictionary).get("modifiers", [])
	var weights := Rules.forge_attribute_weights(accessory_a, accessory_b)
	var total := int(weights.attack_max) + int(weights.magic_max) + int(weights.tao_max)
	var roll := _rng.randi_range(1, total)
	for stat: String in ["attack_max", "magic_max", "tao_max"]:
		roll -= int(weights[stat])
		if roll <= 0:
			return stat
	return "tao_max"


func _failure(message: String) -> Dictionary:
	return {"valid": false, "committed": false, "message": message}
