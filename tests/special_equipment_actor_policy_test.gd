extends Node

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index: int in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _equip(item_name: String) -> Dictionary:
	PlayerState.add_item(item_name)
	var index := _inventory_index(item_name)
	assert(index >= 0, "fixture item missing: %s" % item_name)
	assert(
		PlayerState.equip_inventory_index(index).begins_with("已装备"),
		"fixture item did not equip: %s" % item_name,
	)
	return PlayerState.equipment["hc.slot.ring_left"]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	# The source contract changed from the legacy one-minute charge to the
	# five-minute charge. The production reader and the automatic-revival path
	# must agree on this value.
	var rules_file := FileAccess.open("res://assets/data/equipment_special_rules.json", FileAccess.READ)
	assert(rules_file != null, "special equipment rules source missing")
	var rules_value: Variant = JSON.parse_string(rules_file.get_as_text())
	assert(rules_value is Dictionary, "special equipment rules source is invalid")
	var rules := rules_value as Dictionary
	var rules_api: RefCounted = EquipmentRulesScript.new()
	assert(
		int((rules.get("rules", {}) as Dictionary).get("revivalCooldownMs", 0)) == 300000,
		"revival cooldown contract must be 300 seconds",
	)

	# EquipmentRules is the shared duration policy used by the real melee
	# consumer. Boss classification comes from EnemyActor's canonical identity;
	# no display name or caller_boss hint is accepted as a substitute.
	assert(
		rules_api.has_method("paralysis_duration_for_classification"),
		"equipment rules must expose the canonical paralysis duration helper",
	)
	assert(
		float(rules_api.call("paralysis_duration_for_classification", "boss")) == 2.5,
		"canonical bosses must receive 2.5 seconds of paralysis",
	)
	assert(
		float(rules_api.call("paralysis_duration_for_classification", "elite")) == 2.5,
		"canonical elites must receive 2.5 seconds of paralysis",
	)
	assert(
		float(rules_api.call("paralysis_duration_for_classification", "ordinary")) == 5.0,
		"ordinary monsters must retain 5 seconds of paralysis",
	)

	var player := PlayerCharacter.new()
	player.max_hp = 10000
	player.current_hp = 10000
	add_child(player)
	await get_tree().process_frame

	# Exercise the real EnemyActor control state for each canonical class. The
	# player-melee proc is owned by GameRoot and is tested through its callsite.
	for case: Dictionary in [
		{"id": 46, "classification": "ordinary", "expected": 5.0},
		{"id": 75, "classification": "elite", "expected": 2.5},
		{"id": 76, "classification": "boss", "expected": 2.5},
	]:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(int(case["id"])), player, false)
		add_child(enemy)
		if int(case["id"]) == 46:
			var target_event_count := {"value": 0}
			enemy.combat_target_changed.connect(func(_actor: EnemyActor, _target: Node2D) -> void:
				target_event_count["value"] = int(target_event_count["value"]) + 1
			)
			enemy.target = player
			enemy.target = player
			assert(int(target_event_count["value"]) == 1, "unchanged combat target must not emit a second transition")
		enemy.apply_control(float(rules_api.call("paralysis_duration_for_classification", str(case["classification"]))))
		assert(
			is_equal_approx(enemy.control_time, float(case["expected"])),
			"enemy %d (%s) control duration mismatch: %f" % [int(case["id"]), str(case["classification"]), enemy.control_time],
		)
		enemy.queue_free()

	# A ring worn by the actor is immediately visible to the combat state.
	_reset_equipment()
	_equip("隐身戒指")
	assert(player.is_stealthed(), "wearing stealth ring must immediately hide the actor")
	assert(player.request_attack(), "real attack submission should be accepted by the fixture")
	assert(not player.is_stealthed(), "a real attack must break stealth immediately")

	# The parent combat owner must call this only after its authoritative combat
	# state leaves combat; an arbitrary timer must not re-arm stealth.
	assert(
		player.has_method("recover_equipment_stealth_after_combat_exit"),
		"player must expose an authoritative combat-exit stealth rearm helper",
	)
	assert(
		bool(player.call("recover_equipment_stealth_after_combat_exit")),
		"real combat exit must re-arm worn stealth equipment",
	)
	assert(player.is_stealthed(), "stealth did not recover at real combat exit")

	var stealth_ring := PlayerState.equipment["hc.slot.ring_left"] as Dictionary
	PlayerState.damage_equipment_durability(
		"hc.slot.ring_left",
		int(stealth_ring.get("max_durability", 1)),
	)
	assert(not player.is_stealthed(), "zero durability must clear stealth immediately")

	# Automatic revival by the ring must preserve experience. This invokes the
	# real lethal-hit branch instead of calling the penalty helper directly.
	_reset_equipment()
	# The ring has a level requirement; equip at the legal fixture level, then
	# lower level only for the XP preservation assertion.
	_equip("复活戒指")
	PlayerState.level = 7
	PlayerState.experience = 100
	PlayerState.recalculate_stats()
	var experience_before := PlayerState.experience
	assert(PlayerState.has_special_effect("revival"), "revival fixture did not activate")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await preload("res://tests/helpers/formal_world_skill_fixture.gd").wait_for_formal_world(
		self,
		game,
		"special_equipment_actor_policy",
	)
	var death_signal_count := {"value": 0}
	var on_death := func() -> void: death_signal_count["value"] = int(death_signal_count["value"]) + 1
	game.player.death_requested.connect(on_death)
	game.player.current_hp = game.player.max_hp
	game.player.take_damage(999999, true)
	game.player.death_requested.disconnect(on_death)
	assert(
		PlayerState.experience == experience_before,
		"automatic revival must not reduce experience",
	)
	assert(game.player.current_hp == game.player.max_hp and not game.player._dead, "revival did not restore the real actor")
	assert(int(death_signal_count["value"]) == 0, "automatic revival emitted formal death_requested")

	# Ordinary formal death keeps the existing level-local penalty. This guards
	# against broad changes that would hide a normal death's established loss.
	_reset_equipment()
	PlayerState.level = 7
	PlayerState.experience = 100
	var normal_experience_before := PlayerState.experience
	var death_threshold := PlayerState.experience_to_next_level()
	var expected_normal_loss := int(floor(float(death_threshold) * 0.10))
	game.player._dead = true
	game.player.current_hp = 0
	game._on_player_death_requested()
	assert(
		PlayerState.experience == normal_experience_before - expected_normal_loss,
		"ordinary formal death must retain the established XP loss",
	)

	game.queue_free()
	player.queue_free()
	print("SPECIAL_EQUIPMENT_ACTOR_POLICY_PASS")
	get_tree().quit(0)


func _reset_equipment() -> void:
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
