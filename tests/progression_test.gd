extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(PlayerState.experience_to_next_level() == 100, "Level 1 experience table is invalid")
	while PlayerState.level < 22:
		var previous_level := PlayerState.level
		PlayerState.add_experience(PlayerState.experience_to_next_level())
		assert(PlayerState.level == previous_level + 1, "Level progression skipped or stalled")
	assert(PlayerState.experience_to_next_level() == 300000, "Level 22 to 23 should require 300000 experience")

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
