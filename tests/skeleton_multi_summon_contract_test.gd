extends Node

var game: Node
var player: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	var skill_name := ProfessionRules.skill_display_name("taoist.summon_skeleton")
	PlayerState.learned_skills = {skill_name: 3}
	PlayerState.recalculate_stats()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	player = game.player
	player.set_physics_process(false)
	player.global_position = Vector2(240.0, 240.0)
	player.facing = Vector2.RIGHT
	player.current_mp = 999
	for raw_enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if raw_enemy is EnemyActor:
			var enemy := raw_enemy as EnemyActor
			enemy.set_combat_position(enemy.global_position + Vector2(5000.0, 5000.0), &"multi_summon_fixture")
			enemy.set_physics_process(false)
	PlayerState.computed_stats["skill_level_affix"] = {"contributions": {"all": 2}, "legacy": {}}
	assert(PlayerState.effective_skill_level(skill_name) == 5)
	var first := _cast(skill_name, "multi:spawn:0")
	assert(bool(first.get("accepted", false)))
	var pets: Array = game._canonical_main_pets("skeleton")
	assert(pets.size() == 1 and pets[0].pet_slot_index == 0)
	var first_pet := pets[0] as SummonActor
	first_pet.current_hp = first_pet.max_hp - 5
	first_pet.pet_growth_exp = 17
	var first_hp := first_pet.current_hp
	var mp_after_first := player.current_mp
	var second := _cast(skill_name, "multi:spawn:1")
	assert(bool(second.get("accepted", false)))
	pets = game._canonical_main_pets("skeleton")
	assert(pets.size() == 2 and pets[0].pet_slot_index == 0 and pets[1].pet_slot_index == 1)
	assert((pets[0] as SummonActor).current_hp == first_hp)
	assert((pets[0] as SummonActor).pet_growth_exp == 17)
	assert(player.current_mp < mp_after_first)
	var second_pet := pets[1] as SummonActor
	assert(second_pet.summon_exp_level == 3 and first_pet.summon_exp_level == 3)
	assert(first_pet.rest_formation_contract_snapshot().desired_screen_position_px != second_pet.rest_formation_contract_snapshot().desired_screen_position_px)
	var first_id := first_pet.get_instance_id()
	var dead_second_id := second_pet.get_instance_id()
	second_pet._apply_resolved_damage(second_pet.max_hp + 1)
	assert(game._canonical_main_pets("skeleton").size() == 1)
	var refill := _cast(skill_name, "multi:refill:1")
	assert(bool(refill.get("accepted", false)))
	pets = game._canonical_main_pets("skeleton")
	assert(pets.size() == 2 and (pets[1] as SummonActor).pet_slot_index == 1)
	assert((pets[1] as SummonActor).get_instance_id() != dead_second_id)
	var second_id := (pets[1] as SummonActor).get_instance_id()
	player.current_mp = 0
	var recall := _cast(skill_name, "multi:recall")
	assert(bool(recall.get("accepted", false)))
	assert(game._canonical_main_pets("skeleton").size() == 2)
	assert((game._canonical_main_pets("skeleton")[0] as SummonActor).get_instance_id() == first_id)
	assert((game._canonical_main_pets("skeleton")[1] as SummonActor).get_instance_id() == second_id)
	assert(player.current_mp == 0)
	var captured: Dictionary = game._capture_taoist_main_pet_runtime_states()
	assert(str(captured.get("contract_id", "")) == "skills.taoist_main_pets.v3")
	assert((captured.get("groups", {}).get("skeleton", []) as Array).size() == 2)
	assert(PlayerState.apply_taoist_main_pet_runtime_states(captured))
	# A map transition can lack a legal birth tile for one saved pet. A live
	# sibling must not overwrite that still-valid saved slot on recapture.
	(pets[1] as SummonActor).queue_free()
	await get_tree().process_frame
	var partially_restored: Dictionary = game._capture_taoist_main_pet_runtime_states()
	assert((partially_restored.get("groups", {}).get("skeleton", []) as Array).size() == 2)
	assert(game._owned_skeleton_slots().size() == 2)
	assert(game._next_skeleton_slot_index(game._owned_skeleton_slots()) == 2)
	assert(PlayerState.apply_taoist_main_pet_runtime_states(partially_restored))
	var map_data: Dictionary = game.current_map_data.duplicate(true)
	game._load_zone("%s:multi-skeleton-restore" % game.current_zone, false, map_data)
	pets = game._canonical_main_pets("skeleton")
	assert(pets.size() == 2)
	assert((pets[0] as SummonActor).pet_slot_index == 0 and (pets[1] as SummonActor).pet_slot_index == 1)
	assert((pets[0] as SummonActor).current_hp == first_hp)
	assert((pets[0] as SummonActor).pet_growth_exp == 17)
	PlayerState.computed_stats["skill_level_affix"] = {"contributions": {}, "legacy": {}}
	assert(PlayerState.effective_skill_level(skill_name) == 3)
	PlayerState.equipment_changed.emit()
	assert(game._canonical_main_pets("skeleton").size() == 1)
	assert((game._canonical_main_pets("skeleton")[0] as SummonActor).pet_slot_index == 0)
	assert(PlayerState.apply_taoist_main_pet_runtime_states(captured))
	PlayerState.equipment_changed.emit()
	assert((PlayerState.taoist_main_pet_runtime_states_for_restore().get("groups", {}).get("skeleton", []) as Array).size() == 1)
	var legacy_snapshot: Dictionary = captured.get("groups", {}).get("skeleton", [])[0]
	legacy_snapshot.erase("pet_slot_index")
	legacy_snapshot.erase("effective_skill_rank")
	for legacy_contract: String in ["skills.summon.persistence.runtime_states.v1", "skills.taoist_main_pet.v2"]:
		assert(PlayerState.apply_taoist_main_pet_runtime_states({
			"contract_id": legacy_contract,
			"slots": {"skeleton": legacy_snapshot},
		}))
		var migrated: Dictionary = PlayerState.taoist_main_pet_runtime_states_for_restore()
		assert((migrated.get("groups", {}).get("skeleton", []) as Array).size() == 1)
		assert(int(migrated.get("groups", {}).get("skeleton", [])[0].get("pet_slot_index", -1)) == 0)
	print("SKELETON_MULTI_SUMMON_CONTRACT_PASS")
	get_tree().quit(0)


func _cast(skill_name: String, release_id: String) -> Dictionary:
	return game._execute_canonical_skill(skill_name, player.global_position, player.facing, 0, {"release_id": release_id})
