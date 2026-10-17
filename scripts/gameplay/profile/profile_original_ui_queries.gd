extends RefCounted
## Only the current Profile owner evaluates these original algorithms.
## Main receives plain immutable values; no second weight/XP formula exists.
const Model := preload("res://scripts/gameplay/profile/profile_model.gd")
const FIELD := "_original_ui_queries"
const TYPES := {"inventory_weight":TYPE_INT,"max_inventory_weight":TYPE_INT,"experience_to_next_level":TYPE_INT,"inventory_occupied_count":TYPE_INT,"available_skill_ids":TYPE_ARRAY,"current_bich_quest_id":TYPE_STRING,"skill_facts":TYPE_DICTIONARY,"quest_facts":TYPE_DICTIONARY,"item_counts":TYPE_DICTIONARY,"slot_names":TYPE_DICTIONARY,"skill_assignments":TYPE_DICTIONARY,"skill_slots":TYPE_DICTIONARY}
static func capture(profile: RefCounted) -> Dictionary:
	assert(profile != null and profile.get_script() == Model and profile.get("_owner_thread_id") == OS.get_thread_caller_id())
	var available: Array[String] = profile.available_skill_ids()
	var skill_ids: Array = available.duplicate()
	for id: String in profile.learned_skills:
		if not skill_ids.has(id): skill_ids.append(id)
	var skills: Dictionary = {}
	for id: String in skill_ids:
		var key: String = preload("res://scripts/skills/skill_data_loader.gd").entity_skill_id(id)
		if not key.is_empty(): skills[key] = {"learned":profile.is_skill_learned(id),"level":profile.effective_skill_level(id),"available":profile.is_skill_available(id)}
	var counts: Dictionary = {}
	for record: Variant in profile.inventory:
		if not record is Dictionary or record.is_empty(): continue
		var id: String = profile._content_port.item_entity_id(record)
		if not id.is_empty() and not counts.has(id): counts[id] = profile.item_count_by_entity_id(id)
	var quests: Dictionary = {}
	for raw: Variant in profile._content_port.get_bich_quests():
		if not raw is Dictionary: continue
		var id: String = str(raw.get("id",""))
		if not id.is_empty(): quests[id] = {"lines":profile.quest_objective_lines(id),"reward":profile.quest_reward_label(id)}
	var slots: Dictionary = {}
	var names: Dictionary = {}
	for group: String in [profile.SKILL_SLOT_GROUP_CENTER,profile.SKILL_SLOT_GROUP_ATTACK,profile.SKILL_SLOT_GROUP_ATTACK_RING]:
		slots[group] = profile.skill_slots_for_group(group)
		for index: int in range(slots[group].size()): names["%s:%d" % [group,index]] = profile.skill_name_for_slot(group,index)
	return {"inventory_weight":profile.inventory_weight(),"max_inventory_weight":profile.max_inventory_weight(),"experience_to_next_level":profile.experience_to_next_level(),"inventory_occupied_count":profile.inventory_occupied_count(),"available_skill_ids":available,"current_bich_quest_id":profile.current_bich_quest_id(),"skill_facts":skills,"quest_facts":quests,"item_counts":counts,"slot_names":names,"skill_slots":slots,"skill_assignments":profile.skill_button_assignments_snapshot()}
