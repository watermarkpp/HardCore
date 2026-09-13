extends Node

func _ready() -> void:
	_run.call_deferred()

func _naked() -> void:
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.recalculate_stats(false)
	for key: String in PlayerState.base_stats:
		assert(PlayerState.computed_stats[key] == PlayerState.base_stats[key], "naked mismatch " + key)

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.set_process(false)
	PlayerState.test_mode = true
	var root := "user://base_growth_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("index.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	var initial := {"战士":[19,15,1,1,0,0,0,0,15], "法师":[16,18,0,1,0,1,0,0,15], "道士":[17,13,0,1,0,0,0,1,18]}
	var keys := ["max_hp","max_mp","attack_min","attack_max","magic_min","magic_max","tao_min","tao_max","agility"]
	for job: String in ProfessionRules.PROFESSIONS:
		assert(PlayerState.create_character("成长" + job, job, "男").is_empty())
		for i in keys.size():
			assert(PlayerState.base_stats[keys[i]] == initial[job][i], job + " " + keys[i])
		var starter := PlayerState.equipment.duplicate(true)
		var base := PlayerState.base_stats.duplicate()
		_naked()
		assert(PlayerState.base_stats == base)
		PlayerState.equipment = starter
		PlayerState.recalculate_stats(false)
		var wood := GameData.get_item("木剑")
		assert(PlayerState.computed_stats.attack_max == base.attack_max + int(wood.attackMax))
		_naked()
		for target_level in range(2,61):
			var before := PlayerState.base_stats.duplicate()
			PlayerState.add_experience(PlayerState.experience_to_next_level())
			assert(PlayerState.level == target_level)
			for key: String in before:
				assert(PlayerState.base_stats[key] >= before[key], job + " nonmonotonic " + key)
			_naked()
			assert(GameData.service_profession_stats(job,target_level) == PlayerState.base_stats)
			assert(EquipmentRules.max_hand_weight(job,target_level) == PlayerState.base_stats.max_hand_weight)
			if target_level == 30:
				assert(PlayerState.base_stats.attack_max == (6 if job == "战士" else 4))
				assert(PlayerState.base_stats.magic_max == (4 if job == "法师" else 0))
				assert(PlayerState.base_stats.tao_max == (4 if job == "道士" else 0))
			if target_level == 45:
				assert(PlayerState.base_stats.defense_max == (6 if job == "战士" else 0))
				assert(PlayerState.base_stats.magic_defense_min == (4 if job == "道士" else 0))
				assert(PlayerState.base_stats.magic_defense_max == (9 if job == "道士" else 0))
		base = PlayerState.base_stats.duplicate()
		var profile := {"contractId":"item.temporary_stat_buff.v1","durationSeconds":2.0,"buffGroup":"growth_test","modifiers":{"magic_max":5,"max_hp":50}}
		assert(PlayerState.apply_temporary_item_buff("测试神水",profile).ok)
		assert(PlayerState.computed_stats.magic_max == base.magic_max + 5)
		assert(PlayerState.computed_stats.max_hp == base.max_hp + 50)
		assert(PlayerState.base_stats == base)
		# Exercise the actual runtime callback; helper-only tests missed the bug.
		PlayerState._process(1.0)
		assert(not PlayerState.temporary_item_buffs.is_empty())
		PlayerState._process(1.01)
		assert(PlayerState.temporary_item_buffs.is_empty())
		assert(PlayerState.base_stats == base)
		_naked()
		assert(PlayerState.save_game())
		PlayerState.level = 2
		PlayerState.load_save()
		assert(PlayerState.last_load_result.success)
		assert(PlayerState.base_stats == base)
		var actor := PlayerCharacter.new()
		actor._apply_profile_stats()
		assert(actor.max_hp == base.max_hp and actor.attack_max == base.attack_max)
		actor._dead = true
		actor.current_hp = 0
		actor.complete_death_revival()
		assert(actor.current_hp == base.max_hp and PlayerState.base_stats == base)
		actor.free()
		PlayerState.saved_map_id = 910001
		PlayerState.recalculate_stats(false)
		assert(PlayerState.base_stats == base)
	print("BASE_GROWTH_PASS: 3 professions, creation, 177 level transitions, naked, equipment, runtime buff expiry, save/load, revival")
	get_tree().quit(0)
