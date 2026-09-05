extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.reset_progress()
	_run_gameplay_experience_threshold_contract()
	_run_levels_gained_signal_contract()
	PlayerState.reset_progress()
	assert(PlayerState.experience_to_next_level() == 10, "Gameplay level 1 experience threshold is invalid")
	while PlayerState.level < 22:
		var previous_level := PlayerState.level
		PlayerState.add_experience(PlayerState.experience_to_next_level())
		assert(PlayerState.level == previous_level + 1, "Level progression skipped or stalled")
	assert(PlayerState.experience_to_next_level() == 30000, "Gameplay level 22 to 23 should require 30000 experience")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var home_map_id := GameData.service_home_runtime_map_id(false)
	assert(MapEditorRuntimeBridge.has_runtime_map(home_map_id))
	game.travel_to_map(home_map_id)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == home_map_id, "Progression fixture did not enter formal Home")

	var authored_spawns: Array = MapEditorRuntimeBridge.game_content().get("spawns", [])
	var expected_monsters := 0
	for spawn: Dictionary in authored_spawns:
		expected_monsters += maxi(1, mini(int(spawn.get("count", 1)), int(spawn.get("max_alive", spawn.get("count", 1)))))
	var runtime_enemies := get_tree().get_nodes_in_group("enemies")
	assert(runtime_enemies.size() == expected_monsters, "Runtime monsters differ from the editor spawn plan")
	for runtime_enemy: EnemyActor in runtime_enemies:
		assert(runtime_enemy.display_name not in ["鸡", "鹿"], "Removed chicken/deer content returned to Bich")

	var npc_count := 0
	var bookseller: NPCActor
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is NPCActor:
			npc_count += 1
			if node.stock_key == "books":
				bookseller = node
	assert(npc_count == 7, "Bich must expose all seven authored NPCs")
	assert(bookseller != null, "Bich bookseller is missing")

	for profession_name: String in ProfessionRules.PROFESSIONS:
		PlayerState.select_profession(profession_name)
		var available_skills := 0
		var profession_skills: Array = GameData.get_profession_skills(
			profession_name
		)
		for skill: Variant in profession_skills:
			if int(skill.get("requiredCharacterLevel", 99)) <= 22:
				available_skills += 1
		assert(available_skills >= 2, "%s lacks early skills" % profession_name)
		var expected_stock: Array[Dictionary] = _official_book_stock_for_profession(
			profession_skills
		)
		assert(not expected_stock.is_empty(), "%s has no official book offers" % profession_name)
		bookseller.interact(game)
		var actual_stock: Array = game.hud.shop_panel.stock
		assert(
			actual_stock.size() == expected_stock.size(),
			"%s bookseller stock is stale" % profession_name
		)
		for stock_index: int in range(expected_stock.size()):
			var actual_offer: Dictionary = actual_stock[stock_index]
			var expected_offer: Dictionary = expected_stock[stock_index]
			assert(
				str(actual_offer.get("name", ""))
				== str(expected_offer.get("name", ""))
				and str(actual_offer.get("offer_id", ""))
				== str(expected_offer.get("offer_id", "")),
				"%s bookseller offer order/identity drifted at %d"
				% [profession_name, stock_index]
			)

	assert(GameData.ensure_loaded(), "GameData direct baseline failed to load")
	assert(GameData.is_dpv2_direct_baseline_loaded(), "DPV2 direct baseline is not active")
	for monster: Variant in GameData.monsters:
		assert(monster is Dictionary, "canonical runtime monster record is invalid")
		var monster_id := int(monster.get("monster_id", -1))
		assert(monster_id > 0, "canonical runtime monster lacks monster_id")
		var profile := GameData.dpv2_direct_profile(monster_id)
		assert(
			not profile.is_empty()
				and int(profile.get("canonical_monster_id", -1)) == monster_id,
			"DPV2 profile identity mismatch: %d" % monster_id
		)
		var slots_value: Variant = profile.get("slots", [])
		assert(slots_value is Array, "DPV2 slots invalid: %d" % monster_id)
		var slots: Array = slots_value
		if not bool(profile.get("drop_enabled", false)):
			assert(slots.is_empty(), "disabled profile has slots: %d" % monster_id)
			continue
		for raw_slot: Variant in slots:
			assert(raw_slot is Dictionary, "DPV2 slot invalid: %d" % monster_id)
			var slot: Dictionary = raw_slot
			var slot_uid := str(slot.get("slot_uid", ""))
			assert(
				slot_uid.begins_with("dpv2.direct.m%d." % monster_id),
				"DPV2 slot identity mismatch: %s" % slot_uid
			)
			var reward := GameData.dpv2_direct_resolve_slot_reward(slot)
			assert(
				bool(reward.get("ok", false)),
				"DPV2 reward unresolved: %d/%s" % [monster_id, slot_uid]
			)
			var probability := GameData.dpv2_direct_slot_probability(monster_id, slot_uid)
			assert(
				bool(probability.get("ok", false)),
				"DPV2 probability unresolved: %d/%s" % [monster_id, slot_uid]
			)
			assert(
				int(probability.get("base_numerator", 0)) > 0
					and int(probability.get("base_denominator", 0)) > 0,
				"DPV2 base probability invalid: %d/%s" % [monster_id, slot_uid]
			)
			assert(
				int(probability.get("final_numerator", 0)) > 0
					and int(probability.get("final_denominator", 0)) > 0,
				"DPV2 final probability invalid: %d/%s" % [monster_id, slot_uid]
			)
			if str(reward.get("kind", "")) == "gold":
				assert(
					int(reward.get("gold_amount", 0)) > 0,
					"DPV2 gold reward invalid: %d/%s" % [monster_id, slot_uid]
				)
			else:
				var item_name := str(reward.get("item_name", ""))
				assert(
					not item_name.is_empty()
						and not GameData.get_item_record(item_name).is_empty(),
					"DPV2 item reward unresolved: %d/%s" % [monster_id, slot_uid]
				)

	print("PROGRESSION_PASS: experience, editor spawns, NPCs, skills and drops are consistent")
	get_tree().quit(0)


func _run_gameplay_experience_threshold_contract() -> void:
	assert(GameData.ensure_loaded(), "Experience policy fixture could not load GameData")
	assert(GameData.service_exp_to_next_level(1) == 100, "Raw service level 1 experience changed")
	assert(GameData.service_exp_to_next_level(23) == 350000, "Raw service level 23 experience changed")
	assert(PlayerState._gameplay_experience_threshold(15) == 2, "Threshold rounding policy is not nearest integer")
	assert(PlayerState._gameplay_experience_threshold(0) == 1, "Threshold minimum policy is not 1")
	assert(PlayerState._gameplay_experience_threshold(-1) == 1, "Negative source threshold did not fail closed to 1")
	assert(PlayerState.experience_to_next_level() == 10, "Gameplay threshold did not scale the raw level 1 value")
	PlayerState.add_experience(9)
	assert(PlayerState.level == 1 and PlayerState.experience == 9, "Sub-threshold experience changed level")
	PlayerState.add_experience(1)
	assert(PlayerState.level == 2 and PlayerState.experience == 0, "Scaled threshold did not level at 10 raw reward XP")
	PlayerState.level = 23
	PlayerState.experience = 0
	assert(PlayerState.experience_to_next_level() == 35000, "Gameplay threshold did not scale the raw level 23 value")

	# Exercise the production kill settlement boundary with an active quest.  The
	# source monster reward remains 12 per kill; only the level threshold is tuned.
	PlayerState.reset_progress()
	var scarecrow := GameData.get_monster_by_id(21)
	var combat: Dictionary = scarecrow.get("combat", {})
	var stats: Dictionary = combat.get("stats", {})
	var kill_experience := int(stats.get("exp", 0))
	assert(str(scarecrow.get("canonical_name", "")) == "稻草人" and kill_experience == 12, "Scarecrow kill fixture drifted")
	assert(PlayerState.accept_quest("bich_beginner_gear").begins_with("已接受"), "Quest fixture could not be accepted")
	PlayerState.experience = 9
	PlayerState._test_force_atomic_write_failure = true
	var failed_batch := PlayerState.record_kills_and_experience_batch([
		{"monster_name": "稻草人", "experience": kill_experience},
	], true)
	PlayerState._test_force_atomic_write_failure = false
	assert(
		not bool(failed_batch.get("success", false))
			and PlayerState.level == 1
			and PlayerState.experience == 9
			and PlayerState.quest_progress("bich_beginner_gear") == 0,
		"Kill/quest batch save failure did not restore scaled XP and quest state",
	)
	var kills: Array = []
	for _index in range(3):
		kills.append({"monster_name": "稻草人", "experience": kill_experience})
	var settled_batch := PlayerState.record_kills_and_experience_batch(kills, true)
	assert(
		bool(settled_batch.get("success", false))
			and int(settled_batch.get("experience_gained", 0)) == kill_experience * 3
			and PlayerState.level == 3
			and PlayerState.experience == 15
			and PlayerState.quest_progress("bich_beginner_gear") == 3
			and str(PlayerState.quest_states["bich_beginner_gear"].get("status", "")) == "ready",
		"Real kill/quest settlement did not use the scaled threshold consistently",
	)
	assert(PlayerState.experience_to_next_level() == 30, "Multi-level kill settlement left the wrong next threshold")
	var level_before_claim := PlayerState.level
	var experience_before_claim := PlayerState.experience
	var gold_before_claim := PlayerState.gold
	var quest_rewards: Dictionary = GameData.get_bich_quest("bich_beginner_gear").get("rewards", {})
	assert(not quest_rewards.has("experience") and not quest_rewards.has("exp"), "Quest source unexpectedly added an unhandled experience reward")
	assert(PlayerState.claim_quest("bich_beginner_gear").begins_with("已领取"), "Completed quest could not be claimed")
	assert(
		PlayerState.level == level_before_claim
			and PlayerState.experience == experience_before_claim
			and PlayerState.experience_to_next_level() == 30
			and PlayerState.gold > gold_before_claim
			and str(PlayerState.quest_states["bich_beginner_gear"].get("status", "")) == "claimed",
		"Actual quest claim changed scaled XP/threshold or did not commit its reward",
	)


func _run_levels_gained_signal_contract() -> void:
	var events: Array = []
	var on_levels_gained := func(previous_level: int, new_level: int) -> void:
		events.append([previous_level, new_level])
	PlayerState.levels_gained.connect(on_levels_gained)
	PlayerState._test_force_atomic_write_failure = false

	PlayerState.reset_progress()
	PlayerState.add_experience(0)
	assert(events.is_empty(), "Zero XP unexpectedly emitted levels_gained")
	PlayerState.add_experience(9)
	assert(PlayerState.level == 1 and events.is_empty(), "Sub-threshold XP emitted levels_gained")
	PlayerState.add_experience(1)
	assert(
		PlayerState.level == 2
			and events.size() == 1
			and events[0] == [1, 2],
		"Single-level add_experience did not emit one exact level event",
	)

	events.clear()
	PlayerState.reset_progress()
	PlayerState.add_experience(30)
	assert(
		PlayerState.level == 3
			and PlayerState.experience == 0
			and events.size() == 1
			and events[0] == [1, 3],
		"Multi-level add_experience did not emit exactly one aggregate event",
	)

	events.clear()
	PlayerState.reset_progress()
	var no_level_batch := PlayerState.record_kills_and_experience_batch([
		{"monster_name": "signal_test", "experience": 5},
	], true)
	assert(
		bool(no_level_batch.get("success", false))
			and PlayerState.level == 1
			and PlayerState.experience == 5
			and events.is_empty(),
		"Successful non-leveling kill batch emitted levels_gained",
	)

	PlayerState.reset_progress()
	var zero_xp_batch := PlayerState.record_kills_and_experience_batch([
		{"monster_name": "signal_test", "experience": 0},
	], true)
	assert(
		bool(zero_xp_batch.get("success", false))
			and PlayerState.level == 1
			and PlayerState.experience == 0
			and events.is_empty(),
		"Zero-XP kill batch emitted levels_gained",
	)

	events.clear()
	PlayerState.reset_progress()
	var multi_level_batch := PlayerState.record_kills_and_experience_batch([
		{"monster_name": "signal_test", "experience": 12},
		{"monster_name": "signal_test", "experience": 12},
		{"monster_name": "signal_test", "experience": 12},
	], true)
	assert(
		bool(multi_level_batch.get("success", false))
			and PlayerState.level == 3
			and PlayerState.experience == 6
			and events.size() == 1
			and events[0] == [1, 3],
		"Multi-level kill batch did not emit one aggregate event",
	)

	events.clear()
	PlayerState.reset_progress()
	PlayerState.experience = 9
	PlayerState._test_force_atomic_write_failure = true
	var failed_add := PlayerState.record_kills_and_experience_batch([
		{"monster_name": "signal_test", "experience": 12},
	], true)
	PlayerState._test_force_atomic_write_failure = false
	assert(
		not bool(failed_add.get("success", false))
			and PlayerState.level == 1
			and PlayerState.experience == 9
			and events.is_empty(),
		"Failed kill batch changed state or emitted levels_gained",
	)

	PlayerState.reset_progress()
	PlayerState.experience = 9
	PlayerState._test_force_atomic_write_failure = true
	PlayerState.add_experience(12)
	PlayerState._test_force_atomic_write_failure = false
	assert(
		PlayerState.level == 1
			and PlayerState.experience == 9
			and events.is_empty(),
		"Failed add_experience changed state or emitted levels_gained",
	)
	PlayerState.levels_gained.disconnect(on_levels_gained)


func _official_book_stock_for_profession(
	profession_skills: Array
) -> Array[Dictionary]:
	var allowed_names := {}
	for raw_skill: Variant in profession_skills:
		assert(raw_skill is Dictionary)
		allowed_names[str((raw_skill as Dictionary).get("skillName", ""))] = true
	var expected: Array[Dictionary] = []
	for raw_offer: Variant in GameData.merchant_stock("books"):
		assert(raw_offer is Dictionary)
		var offer: Dictionary = raw_offer as Dictionary
		if allowed_names.has(str(offer.get("name", ""))):
			expected.append(offer)
	return expected
