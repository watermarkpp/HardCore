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
	game.travel_to_map(4)
	await get_tree().process_frame
	await get_tree().process_frame

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
		for skill: Variant in GameData.get_profession_skills(profession_name):
			if int(skill.get("requiredCharacterLevel", 99)) <= 22:
				available_skills += 1
		assert(available_skills >= 2, "%s lacks early skills" % profession_name)
		bookseller.interact(game)
		assert(game.hud.shop_panel.stock.size() == GameData.get_profession_skills(profession_name).size(), "%s bookseller stock is stale" % profession_name)

	for monster_name: String in RegionContent.MONSTER_DROPS.keys():
		for drop: Variant in RegionContent.get_monster_drops(monster_name):
			var drop_name := str(drop.get("name", "")) if drop is Dictionary else "<invalid>"
			assert(drop is Dictionary and not GameData.get_item_record(drop_name).is_empty(), "%s has an unresolved drop: %s" % [monster_name, drop_name])
			assert(int(drop.get("denominator", 0)) > 0, "%s has an invalid drop probability" % monster_name)

	print("PROGRESSION_PASS: experience, editor spawns, NPCs, skills and drops are consistent")
	get_tree().quit(0)
