extends Node

const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const SkillData := preload("res://scripts/skills/skill_data_loader.gd")

func _ready() -> void:
	_run.call_deferred()

func _equip(id: int, profession: String) -> Dictionary:
	var catalog := Rules.record_for_id(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var item := PlayerState._make_item_instance(str(catalog.name), catalog, -1, false)
	item.merge(Rules.roll_instance(id, profession, rng), true)
	assert(PlayerState.receive_record(item, false).success)
	for index in PlayerState.inventory.size():
		if str(PlayerState.inventory[index].get("instance_id", "")) == str(item.instance_id):
			assert(PlayerState.equip_inventory_index_result(index).success)
			return item
	assert(false, "received equipment was lost")
	return {}

func _trigger_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for value in 100:
		rng.seed = value
		if rng.randi_range(0, 99) < Rules.PROC_CHANCE_PERCENT:
			rng.seed = value
			return rng
	assert(false)
	return rng

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.set_process(false)
	PlayerState.profile_directory = "user://relic_actor_%d/characters" % Time.get_ticks_usec()
	PlayerState.active_profile_id = "relic_actor"
	assert(GameData.ensure_loaded())
	for id in [950101, 950102, 950103, 950201, 950202, 950203]:
		PlayerState.reset_progress(false)
		var profession := "法师" if id == 950202 else ("道士" if id == 950203 else "战士")
		PlayerState.profession = profession
		PlayerState.level = 40
		PlayerState.recalculate_stats(false)
		var naked := PlayerState.computed_stats.duplicate(true)
		var item := _equip(id, profession)
		var slot := "hc.slot.badge" if Rules.is_badge(id) else "hc.slot.relic"
		assert(PlayerState.equipment[slot] == item)
		var skill_name := SkillData.display_name(str(item.relic_roll.skill_id))
		assert(PlayerState.effective_skill_level(skill_name) == 0)
		PlayerState.learned_skills = {SkillData.entity_skill_id(skill_name): 3}
		assert(PlayerState.effective_skill_level(skill_name) == 4)
		var before_reload := PlayerState.equipment.duplicate(true)
		assert(PlayerState.save_game(false))
		PlayerState.reset_progress(false)
		PlayerState.load_save()
		assert(PlayerState.last_load_result.success)
		# Godot JSON decodes numbers as float; compare the full persisted meaning
		# and then revalidate the real instance, including every rolled modifier.
		assert(JSON.parse_string(JSON.stringify(PlayerState.equipment)) == JSON.parse_string(JSON.stringify(before_reload)),
			"save/load changed equipment identity or rolled attributes")
		assert(Rules.valid_instance(PlayerState.equipment[slot], id))
		assert(PlayerState.effective_skill_level(skill_name) == 4, "equipped skill bonus was lost after load")
		var actor := PlayerCharacter.new()
		add_child(actor)
		actor.set_physics_process(false)
		actor.current_hp = 30
		actor.current_mp = 10
		var passive := PlayerState.computed_stats.duplicate(true)
		if id == 950102:
			for stat in ["attack", "magic", "tao"]:
				assert(int(passive[stat + "_max"]) == int(naked[stat + "_max"]) + 5)
				assert(int(passive[stat + "_min"]) == int(naked[stat + "_min"]))
		if Rules.is_relic(id):
			PlayerState.configure_relic_proc_rng(_trigger_rng())
			var save_revision: int = PlayerState._item_save_revision
			var pending: int = PlayerState._json_persistence.pending_count()
			assert(PlayerState.try_trigger_relic_proc())
			assert(actor.current_hp == 30 and actor.current_mp == 10, "proc must preserve live resources")
			assert(actor.attack_min == int(PlayerState.computed_stats.attack_min))
			assert(actor.attack_max == int(PlayerState.computed_stats.attack_max))
			assert(is_equal_approx(actor.attack_cooldown, WarriorCombatMath.physical_attack_interval_seconds(int(PlayerState.computed_stats.attack_speed_tier))))
			if id == 950101:
				assert(actor.attack_cooldown < WarriorCombatMath.physical_attack_interval_seconds(int(passive.attack_speed_tier)))
			elif id == 950102:
				assert(actor.attack_max == roundi(float(passive.attack_max) * 1.15))
			elif id == 950103:
				# Follow the real spell primary-stat consumer, using identical RNG streams.
				var game := preload("res://scripts/game_root.gd").new()
				var comparison := RandomNumberGenerator.new()
				game._rng.seed = 730
				comparison.seed = 730
				for attempt in 30:
					assert(game._canonical_primary_stat_roll("warrior") == WarriorCombatMath.roll_primary_stat(actor.attack_min, actor.attack_max, int(passive.luck) + 2, comparison))
				game.free()
			assert(not PlayerState.try_trigger_relic_proc(), "active effect stacked")
			PlayerState.advance_relic_proc(10.0)
			assert(PlayerState.computed_stats == passive)
			assert(not PlayerState.try_trigger_relic_proc(), "cooldown was bypassed")
			PlayerState.advance_relic_proc(15.0)
			PlayerState.configure_relic_proc_rng(_trigger_rng())
			assert(PlayerState.try_trigger_relic_proc())
			assert(PlayerState._item_save_revision == save_revision and PlayerState._json_persistence.pending_count() == pending,
				"combat proc scheduled persistence")
		else:
			var hp_before := actor.current_hp
			var mp_before := actor.current_mp
			actor._tick_badge_recovery(1.0)
			assert(actor.current_hp == hp_before + (roundi(actor.max_hp * 0.01) if id == 950201 else 0))
			assert(actor.current_mp == mp_before + (0 if id == 950201 else roundi(actor.max_mp * 0.01)))
			actor.current_hp = 0
			actor._dead = true
			actor._tick_badge_recovery(5.0)
			assert(actor.current_hp == 0, "badge revived a dead actor")
			actor.complete_death_revival()
			actor._tick_badge_recovery(1.0)
			assert(actor.current_hp == actor.max_hp and actor.current_mp == actor.max_mp)
		assert(PlayerState.unequip_to_inventory_slot(slot, 60, str(item.instance_id)).success)
		assert(PlayerState.effective_skill_level(skill_name) == 3)
		assert(PlayerState.computed_stats == naked, "unequip retained passive or proc attributes")
		assert(actor.attack_max == int(naked.attack_max))
		actor.current_hp = 30
		actor.current_mp = 10
		actor._tick_badge_recovery(2.0)
		assert(actor.current_hp == 30 and actor.current_mp == 10)
		actor.free()
		print("RELIC_ACTOR_CASE id=", id, " equipped, skill, consumer, removal verified")
	print("RELIC_EQUIPPED_ACTOR_PASS")
	get_tree().quit(0)
