extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
var proof := Proof.new()
var failures: Array[String] = []
var requests: Array[String] = []
var scroll_requests: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	PlayerState.profile_directory = "user://item_use_identity_%d" % Time.get_ticks_usec()
	PlayerState.consumable_requested.connect(func(entity_id: String) -> void: requests.append(entity_id))
	PlayerState.scroll_requested.connect(func(entity_id: String) -> void: scroll_requests.append(entity_id))
	var game := Root.new()
	game.player = PlayerCharacter.new()
	game.player.max_hp = 1000
	game.player.max_mp = 1000
	game.player.current_hp = 500
	game.player.current_mp = 500
	game._player_input_enabled = true
	PlayerState.consumable_requested.connect(game._on_consumable_used)
	var potion := GameData.get_entity_record("hc.item.920014")
	check(potion.get("useEffect") == "restore_both" and int(potion.get("restoreHealth", -1)) > 0,
		"the real solar potion fixture uses its actual primary restoration rule")
	PlayerState.inventory = [{"item_id": 920014, "name": "其他显示文字", "count": 1}]
	var result: Dictionary = PlayerState.use_inventory_index_result(0)
	check(result.get("success", false) and requests == ["hc.item.920014"],
		"actual committed consumable requests publish the canonical item ID once")
	check(game.player.current_hp == 500 + int(potion.get("restoreHealth", 0))
		and game.player.current_mp == 500 + int(potion.get("restoreMana", 0)),
		"the actual signal consumer applies the same primary health and mana amounts")
	var hp := game.player.current_hp
	var mp := game.player.current_mp
	for invalid: String in ["太阳水", "金创药(小量)", "hc.item.920014.5", "hc.skill.wizard.fireball", "hc.item.999999"]:
		game.player.current_hp = hp
		game.player.current_mp = mp
		game.player._pending_potion_health = 0
		game.player._pending_potion_mana = 0
		game._on_consumable_used(invalid)
		check(game.player.current_hp == hp and game.player.current_mp == mp
			and game.player._pending_potion_health == 0 and game.player._pending_potion_mana == 0,
			"a presentation or invalid event cannot execute a gameplay effect: " + invalid)
	game.player.current_hp = hp
	game.player.current_mp = mp
	game.player._pending_potion_health = 0
	game.player._pending_potion_mana = 0
	var small := GameData.get_entity_record("hc.service_item.000658")
	var small_id := GameData.item_entity_id(small)
	check(not small_id.is_empty() and small.get("useEffect") == "delayed_restore", "the delayed fixture has an existing declared canonical identity")
	game._on_consumable_used(small_id)
	check(game.player.current_hp == hp and game.player._pending_potion_health == int(small.restoreHealth),
		"formal delayed potions preserve queued recovery rather than becoming immediate")
	game.player._pending_potion_health = 0
	game._on_consumable_used("hc.service_item.000123")
	check(game.player.current_hp == hp + 30 and game.player.current_mp == mp + 30
		and game.player.defense_buff == 2 and is_equal_approx(game.player.defense_buff_time, 60.0),
		"the existing divine-water compatibility effect retains its exact amounts and duration through its registered service ID")
	var town := GameData.get_entity_record("hc.service_item.000719")
	var town_id := GameData.item_entity_id(town)
	PlayerState.inventory = [{"service_index": 719, "name": "改过的卷轴显示", "count": 1}]
	result = PlayerState.use_inventory_index_result(0)
	check(result.get("success", false) and scroll_requests == [town_id] and PlayerState.item_count(town_id) == 0,
		"actual scroll consumption publishes the declared canonical ID once")
	PlayerState.inventory = [{"item_id": 920014, "name": "同样的显示", "count": 1}]
	var inventory_before: Array = PlayerState.inventory.duplicate(true)
	var request_count := requests.size()
	PlayerState._test_force_atomic_write_failure = true
	result = PlayerState.use_inventory_index_result(0)
	PlayerState._test_force_atomic_write_failure = false
	check(not result.get("success", false) and PlayerState.inventory == inventory_before and requests.size() == request_count,
		"the actual writer rejection cannot dispatch a consumable effect or lose the item")
	var weapon := GameData.get_entity_record(Ids.from_legacy("item", 81))
	check(weapon.get("kind") == "equipment", "the luck fixture uses the existing registered weapon source")
	PlayerState.equipment["hc.slot.weapon"] = PlayerState._make_item_instance(str(weapon.name), weapon)
	PlayerState.equipment["hc.slot.weapon"]["weapon_luck"] = 0
	PlayerState.equipment["hc.slot.weapon"]["weapon_curse"] = 0
	PlayerState.inventory = [{"item_id": 920033, "name": "可修改的油显示", "count": 1}]
	result = PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 0)
	check(result.get("ok", false) and PlayerState.item_count("hc.item.920033") == 0
		and int(PlayerState.equipment["hc.slot.weapon"].get("weapon_luck", -1)) == 1,
		"the actual deterministic oil transaction identifies a renamed oil by ID and preserves its outcome")
	var rng := RandomNumberGenerator.new()
	rng.seed = 176
	PlayerState.inventory = [{"item_id": 920014, "name": "祝福油", "count": 1}]
	inventory_before = PlayerState.inventory.duplicate(true)
	var equipment_before: Dictionary = PlayerState.equipment.duplicate(true)
	var rng_before := rng.state
	result = PlayerState.use_blessing_oil_inventory_index(0, rng)
	check(not result.get("ok", false) and result.get("reason") == "invalid_oil"
		and PlayerState.inventory == inventory_before and PlayerState.equipment == equipment_before and rng.state == rng_before,
		"a different typed item forged with the oil display is rejected before any real RNG draw or mutation")
	PlayerState.inventory = [{"service_index": 709, "name": "服务油显示改变", "count": 1}]
	result = PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 1)
	check(result.get("ok", false), "the declared service alias enters the same real blessing transaction")
	PlayerState.inventory = [{"item_id": 920033, "name": "再次改名", "count": 1}]
	inventory_before = PlayerState.inventory.duplicate(true)
	equipment_before = PlayerState.equipment.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	result = PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 0)
	PlayerState._test_force_atomic_write_failure = false
	check(not result.get("ok", false) and result.get("reason") == "save_failed"
		and PlayerState.inventory == inventory_before and PlayerState.equipment == equipment_before,
		"real oil writer failure restores the exact typed oil and weapon luck state")
	PlayerState.configure_blessing_oil_rng(rng)
	result = PlayerState.use_inventory_index_result(0)
	check(result.get("success", false) and scroll_requests.back() == "hc.item.920033",
		"the actual oil inventory entrance publishes its formal scroll event after commit")
	var covered := {}
	var compatible_fallbacks := {}
	for item: Dictionary in GameData.item_catalog:
		if item.get("kind") != "consumable" or not item.get("usable", true): continue
		var effect := str(item.get("useEffect", ""))
		if (effect == "delayed_restore" or effect == "restore_both") and (int(item.get("restoreHealth", 0)) > 0 or int(item.get("restoreMana", 0)) > 0): continue
		if effect == "temporary_buff": continue
		var name := str(item.get("name", ""))
		if "金创药" in name or "魔法药" in name or "太阳水" in name or name in ["疗伤药", "万年雪霜"] or "神水" in name:
			var entity_id := GameData.item_entity_id(item)
			if effect == "temporary_stat_buff": covered[entity_id] = true
			else: compatible_fallbacks[entity_id] = effect
	check(covered.size() == 6 and compatible_fallbacks == {"hc.service_item.000123": "unlock_curse"},
		"actual runtime catalog audit bounds the former display fallback to the one preserved registered compatibility item")
	PlayerState.consumable_requested.disconnect(game._on_consumable_used)
	game.player.free()
	game.free()
	proof.write_receipt("item_use_action_identity_test", proof.records.size(), failures.size())
	print("ITEM_USE_ACTION_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
