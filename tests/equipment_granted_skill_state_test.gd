extends Node

const Loadout := preload("res://scripts/skill_loadout_rules.gd")
const Icons := preload("res://scripts/hud_skill_icon_catalog.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(PlayerState.has_method("is_skill_available"), "equipment availability API missing")
	assert(PlayerState.has_method("skill_assignment_roster"), "equipment assignment roster API missing")
	for binding: Array in [["传送戒指", "hc.skill.equipment.ring_teleport"], ["防御戒指", "hc.skill.equipment.ring_healing"], ["火焰戒指", "hc.skill.equipment.ring_fireball"]]:
		PlayerState.reset_progress()
		PlayerState.level = 50
		PlayerState.recalculate_stats()
		var learned_before := PlayerState.learned_skills.duplicate(true)
		var skill_id := str(binding[1])
		assert(not bool(PlayerState.call("is_skill_available", skill_id)), "unworn grant must be unavailable")
		PlayerState.add_item(str(binding[0]))
		var item_index := -1
		for index in range(PlayerState.inventory.size()):
			if str(PlayerState.inventory[index].get("name", "")) == str(binding[0]): item_index = index
		assert(item_index >= 0)
		assert(PlayerState.equip_inventory_index(item_index).begins_with("已装备"))
		assert(bool(PlayerState.call("is_skill_available", skill_id)), "worn ring must grant skill")
		assert(not PlayerState.is_skill_learned(skill_id), "grant must not teach a skill")
		assert(Icons.texture_for(skill_id) != null, "ring skill must use actual item icon")
		var request := {"contract_id": "ui.skill.button_assignment.v3", "slot_group": "attack_ring", "slot_index": 0, "skill_id": skill_id, "skill_name": Loader.display_name(skill_id)}
		var roster: Dictionary = PlayerState.call("skill_assignment_roster")
		var result := Loadout.assign_button_slot(PlayerState.skill_button_assignments_snapshot(), roster, request)
		assert(bool(result.ok), "equipment grant must assign to skill bar")
		assert(PlayerState.apply_skill_button_assignment(result), "equipment skill binding must save")
		assert(PlayerState.skill_id_for_slot("attack_ring", 0) == skill_id)
		var saved_bindings := PlayerState.skill_button_assignments_snapshot()
		PlayerState.call("_restore_skill_button_assignments", saved_bindings, [])
		assert(PlayerState.skill_id_for_slot("attack_ring", 0) == skill_id, "load must preserve available equipment binding")
		PlayerState._test_force_atomic_write_failure = true
		assert(PlayerState.unequip_slot("hc.slot.ring_left").contains("存档失败"))
		PlayerState._test_force_atomic_write_failure = false
		assert(PlayerState.is_skill_available(skill_id), "failed unequip must preserve worn grant")
		assert(PlayerState.skill_id_for_slot("attack_ring", 0) == skill_id, "failed unequip must preserve binding")
		var valid_ring: Dictionary = PlayerState.equipment["hc.slot.ring_left"].duplicate(true)
		PlayerState.equipment["hc.slot.ring_left"] = {}
		PlayerState.equipment["hc.slot.helmet"] = valid_ring
		assert(not PlayerState.is_skill_available(skill_id), "wrong equipment slot must not grant a skill")
		PlayerState.equipment["hc.slot.helmet"] = {}
		PlayerState.equipment["hc.slot.ring_left"] = valid_ring
		var ring: Dictionary = PlayerState.equipment["hc.slot.ring_left"]
		PlayerState.damage_equipment_durability("hc.slot.ring_left", int(ring.max_durability))
		assert(not bool(PlayerState.call("is_skill_available", skill_id)), "broken ring must revoke skill")
		assert(PlayerState.skill_id_for_slot("attack_ring", 0).is_empty(), "revoked grant binding must clear")
		assert(PlayerState.learned_skills == learned_before, "grant lifecycle must leave learned progression intact")
	print("EQUIPMENT_GRANTED_SKILL_STATE_PASS grants=3 bindings=3 learned_unchanged=true")
	get_tree().quit(0)
