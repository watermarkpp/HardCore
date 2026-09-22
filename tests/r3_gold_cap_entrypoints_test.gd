extends Node

const TEST_ROOT_PREFIX := "user://r3_gold_cap_entrypoints"
const TEST_PROFILE_ID := "r3_gold_cap"
const QUEST_ID := "bich_beginner_gear"
const EQUIPMENT_ITEM_ID := 80

var _game: Node
var _storage_root := ""
var _saved_player_state: Dictionary = {}
var _saved_quest: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "formal catalog load failed")
	_capture_player_state()
	_configure_isolated_player_state()
	_game = await _boot_formal_game()
	await _test_formal_gold_pickup(_game)
	# Keep the remaining checks on the authoritative PlayerState entry points;
	# the world fixture is disabled only after the real GameRoot pickup path ran.
	_game.set_process(false)
	_game.set_physics_process(false)
	var manager: Node = _game.get("_loot_pickup_runtime_manager")
	if is_instance_valid(manager):
		manager.set_process(false)
	_test_sale_entrypoints()
	_test_quest_entrypoint()
	_test_add_gold_contract()
	_restore_quest()
	_game.queue_free()
	await get_tree().process_frame
	_game = null
	_restore_player_state()
	_cleanup_isolated_storage()
	print("R3_GOLD_CAP_ENTRYPOINTS_PASS: formal pickup, single/batch sale, quest claim, add_gold contract")
	get_tree().quit(0)


func _capture_player_state() -> void:
	_saved_player_state = {
		"level": PlayerState.level,
		"profession": PlayerState.profession,
		"gender": PlayerState.gender,
		"later_content_enabled": PlayerState.later_content_enabled,
		"game_mode_id": PlayerState.game_mode_id,
		"experience": PlayerState.experience,
		"gold": PlayerState.gold,
		"gold_overflow_records": PlayerState.gold_overflow_records.duplicate(true),
		"inventory": PlayerState.inventory.duplicate(true),
		"warehouse_inventory": PlayerState.warehouse_inventory.duplicate(true),
		"equipment": PlayerState.equipment.duplicate(true),
		"learned_skills": PlayerState.learned_skills.duplicate(true),
		"quick_slots": PlayerState.quick_slots.duplicate(true),
		"quick_item_slots": PlayerState.quick_item_slots.duplicate(true),
		"equip_cycle_cursor": PlayerState.equip_cycle_cursor.duplicate(true),
		"equipment_transaction_revision": PlayerState.equipment_transaction_revision,
		"last_equipment_transaction_result": PlayerState._last_equipment_transaction_result.duplicate(true),
		"attack_skill_slots": PlayerState.attack_skill_slots.duplicate(true),
		"attack_ring_slots": PlayerState.attack_ring_slots.duplicate(true),
		"warrior_runtime_state": PlayerState.warrior_runtime_state.duplicate(true),
		"taoist_main_pet_runtime_states": PlayerState.taoist_main_pet_runtime_states.duplicate(true),
		"quest_states": PlayerState.quest_states.duplicate(true),
		"world_monster_respawn_state": PlayerState.world_monster_respawn_state.duplicate(true),
		"saved_map_id": PlayerState.saved_map_id,
		"saved_position": PlayerState.saved_position,
		"saved_ground_position_gu": PlayerState.saved_ground_position_gu,
		"saved_ground_position_gu_valid": PlayerState.saved_ground_position_gu_valid,
		"computed_stats": PlayerState.computed_stats.duplicate(true),
		"computed_special_effects": PlayerState.computed_special_effects.duplicate(true),
		"durability_event_commit_count": PlayerState.durability_event_commit_count,
		"temporary_item_buffs": PlayerState.temporary_item_buffs.duplicate(true),
		"temporary_item_buff_revision": PlayerState.temporary_item_buff_revision,
		"active_profile_id": PlayerState.active_profile_id,
		"character_name": PlayerState.character_name,
		"profile_index_path": PlayerState.profile_index_path,
		"profile_directory": PlayerState.profile_directory,
		"shared_warehouse_path": PlayerState.shared_warehouse_path,
		"shared_warehouse_transaction_log_path": PlayerState.shared_warehouse_transaction_log_path,
		"test_mode": PlayerState.test_mode,
		"shared_warehouse_initialized": PlayerState._shared_warehouse_initialized,
		"active_profile_legacy_warehouse_pending": PlayerState._active_profile_legacy_warehouse_pending,
		"warehouse_transaction_locked": PlayerState._warehouse_transaction_locked,
		"persistence_transaction_in_progress": PlayerState._persistence_transaction_in_progress,
		"test_fail_shared_write": PlayerState._test_fail_shared_write,
		"test_fail_profile_write": PlayerState._test_fail_profile_write,
		"test_fail_warehouse_rollback_write": PlayerState._test_fail_warehouse_rollback_write,
		"test_force_atomic_write_failure": PlayerState._test_force_atomic_write_failure,
		"save_blocked_profile_id": PlayerState._save_blocked_profile_id,
		"save_blocked_reason": PlayerState._save_blocked_reason,
		"consumed_shop_sell_quote_ids": PlayerState._consumed_shop_sell_quote_ids.duplicate(true),
		"consumed_shop_buy_quote_ids": PlayerState._consumed_shop_buy_quote_ids.duplicate(true),
		"shop_buy_quote_serial": PlayerState._shop_buy_quote_serial,
		"shop_pricing_session_nonce": PlayerState._shop_pricing_session_nonce,
		"item_instance_serial": PlayerState._item_instance_serial,
		"autosave_elapsed": PlayerState._autosave_elapsed,
		"last_save_result": PlayerState.last_save_result.duplicate(true),
		"last_load_result": PlayerState.last_load_result.duplicate(true),
		"skill_progression": PlayerState._skill_progression.snapshot(),
	}


func _configure_isolated_player_state() -> void:
	_storage_root = "%s_%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec()]
	PlayerState.profile_directory = _storage_root.path_join("characters")
	PlayerState.profile_index_path = _storage_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = _storage_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = _storage_root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState._test_fail_shared_write = false
	PlayerState._test_fail_profile_write = false
	PlayerState._test_fail_warehouse_rollback_write = false
	PlayerState._test_force_atomic_write_failure = false
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""
	PlayerState.active_profile_id = TEST_PROFILE_ID
	PlayerState.character_name = "金币上限入口回归"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	# Exercise the real profile/shared bootstrap once, then use test_mode only
	# for deterministic atomic-save failure injection in the entry-point cases.
	PlayerState.test_mode = false
	assert(PlayerState.save_game(false), "isolated profile bootstrap save failed")
	PlayerState.test_mode = true


func _boot_formal_game() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 50000
	while (
		not is_instance_valid(game.get("player"))
		or int(game.get("current_map_id")) < 0
		or bool(game.get("_world_bootstrap_in_progress"))
		or bool(game.get("_map_transition_in_progress"))
	):
		assert(Time.get_ticks_msec() < deadline, "formal GameRoot bootstrap did not reach READY")
		await get_tree().process_frame
	assert(is_instance_valid(game.get("player")), "formal GameRoot player missing")
	assert(game.gameplay_input_is_enabled(), "formal GameRoot input gate remained closed")
	return game


func _test_formal_gold_pickup(game: Node) -> void:
	var player: PlayerCharacter = game.get("player")
	var manager: Node = game.get("_loot_pickup_runtime_manager")
	assert(is_instance_valid(player) and is_instance_valid(manager), "formal loot services missing")
	var ground: Vector2 = game._resolve_loot_ground_position(player.global_position, player.global_position)
	assert(ground.is_finite(), "formal player footpoint did not resolve to legal ground")
	assert(game._loot_ground_point_clear(ground), "formal resolved loot ground is blocked")
	game._set_player_world_position(ground)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.set_process(false)
	game.set_physics_process(false)
	player.set_process(false)
	player.set_physics_process(false)
	manager.set_process(false)

	var cap := PlayerState.PLAYER_GOLD_CAP
	PlayerState.inventory = []
	PlayerState.gold = cap
	var before_ids := _gold_pickup_ids()
	assert(game._spawn_gold_loot(1, ground, ground), "formal gold spawn at legal ground failed")
	var cap_pickup: LootPickup = _new_gold_pickup(before_ids, 1)
	assert(is_instance_valid(cap_pickup), "cap gold pickup was not registered")
	manager.player_position_changed(player.global_position)
	assert(game._pending_loot_collections.size() == 1, "formal manager did not queue cap pickup")
	var cap_result: Dictionary = game._flush_loot_collections()
	assert(int(cap_result.get("success_count", -1)) == 0, "cap pickup was credited")
	assert(int(cap_result.get("outcomes_count", -1)) == 1, "cap pickup did not reach authority")
	assert(PlayerState.gold == cap, "cap rejection changed gold")
	assert(is_instance_valid(cap_pickup) and not cap_pickup.is_queued_for_deletion(), "cap pickup was destroyed")
	assert(not cap_pickup.collection_pending(), "cap rejection left pickup pending")

	# Make exactly one coin of room and retry through the same registered pickup
	# manager. The rejected source stays on the ground while the new source is
	# credited once and then confirmed/freed.
	PlayerState.gold = cap - 1
	before_ids = _gold_pickup_ids()
	assert(game._spawn_gold_loot(1, ground, ground), "formal retry gold spawn failed")
	var retry_pickup: LootPickup = _new_gold_pickup(before_ids, 1)
	assert(is_instance_valid(retry_pickup), "retry gold pickup was not registered")
	manager.player_position_changed(player.global_position)
	assert(game._pending_loot_collections.size() == 1, "formal manager did not queue retry pickup")
	var retry_result: Dictionary = game._flush_loot_collections()
	assert(int(retry_result.get("success_count", -1)) == 1, "exact-capacity retry was not credited")
	assert(PlayerState.gold == cap, "exact-capacity retry credited the wrong amount")
	await get_tree().process_frame
	assert(not is_instance_valid(retry_pickup), "confirmed retry pickup remained in the world")
	assert(is_instance_valid(cap_pickup), "rejected cap pickup was incorrectly removed")
	# A second manager pass cannot credit the confirmed pickup a second time.
	manager.player_position_changed(player.global_position)
	var repeat_result: Dictionary = game._flush_loot_collections()
	assert(int(repeat_result.get("success_count", 0)) == 0 and PlayerState.gold == cap,
		"confirmed gold pickup was credited twice")


func _test_sale_entrypoints() -> void:
	var context: Dictionary = GameData.merchant_context("starter_gear")
	assert(not context.is_empty(), "formal starter merchant context missing")
	var merchant_id := str(context.get("merchant_id", ""))
	assert(not merchant_id.is_empty(), "formal starter merchant id missing")
	var cap := PlayerState.PLAYER_GOLD_CAP

	var single_before := _install_full_equipment_instances(1, "single")
	var single_base := _sell_request(0, context)
	var single_quote := _quote_for_request(single_base)
	var single_request := _request_with_quote(single_base, single_quote)
	PlayerState.gold = cap
	var cap_rejected: Dictionary = PlayerState.sell_inventory_item(single_request)
	assert(not bool(cap_rejected.get("success", false)), "single sale at gold cap succeeded")
	assert(PlayerState.inventory == single_before and PlayerState.gold == cap,
		"single cap rejection lost the full source instance")
	assert(not PlayerState._consumed_shop_sell_quote_ids.has(single_request.get("quote_id", "")),
		"single cap rejection consumed its quote")

	var single_price := int(single_quote.get("unit_price", 0))
	assert(single_price > 0 and single_price <= cap, "single sale quote had no usable price")
	PlayerState.gold = cap - single_price
	var single_failure_before := PlayerState.inventory.duplicate(true)
	var single_failure_gold := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	var save_failed: Dictionary = PlayerState.sell_inventory_item(single_request)
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(save_failed.get("success", false)), "single save failure unexpectedly succeeded")
	assert(PlayerState.inventory == single_failure_before and PlayerState.gold == single_failure_gold,
		"single save failure did not retain the full source instance")
	var single_retry: Dictionary = PlayerState.sell_inventory_item(single_request)
	assert(bool(single_retry.get("success", false)), "single sale did not succeed after save recovery")
	assert(PlayerState.inventory.is_empty() and PlayerState.gold == cap,
		"single retry did not settle exactly once")

	var batch_before := _install_full_equipment_instances(2, "batch")
	var batch_bases: Array = []
	for index in range(2):
		batch_bases.append(_sell_request(index, context))
	var quotes: Dictionary = PlayerState.shop_sell_quotes(batch_bases)
	var batch_requests: Array = []
	var batch_total := 0
	for base: Dictionary in batch_bases:
		var key := str(base.get("quote_key", ""))
		var quote: Dictionary = quotes.get(key, {})
		assert(bool(quote.get("sellable", false)), "full instance batch quote was rejected")
		batch_total += int(quote.get("unit_price", 0))
		batch_requests.append(_request_with_quote(base, quote))
	assert(batch_total > 0 and batch_total <= cap, "batch sale quote total was unusable")

	PlayerState.gold = cap
	var batch_cap_rejected: Dictionary = PlayerState.sell_inventory_items(batch_requests)
	assert(not bool(batch_cap_rejected.get("success", false)), "batch sale at gold cap succeeded")
	assert(PlayerState.inventory == batch_before and PlayerState.gold == cap,
		"batch cap rejection lost a full source instance")
	for request: Dictionary in batch_requests:
		assert(not PlayerState._consumed_shop_sell_quote_ids.has(request.get("quote_id", "")),
			"batch cap rejection consumed a quote")

	PlayerState.gold = cap - batch_total
	var batch_failure_before := PlayerState.inventory.duplicate(true)
	var batch_failure_gold := PlayerState.gold
	var consumed_before := PlayerState._consumed_shop_sell_quote_ids.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	var batch_save_failed: Dictionary = PlayerState.sell_inventory_items(batch_requests)
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(batch_save_failed.get("success", false)), "batch save failure unexpectedly succeeded")
	assert(PlayerState.inventory == batch_failure_before and PlayerState.gold == batch_failure_gold,
		"batch save failure did not retain full source instances")
	assert(PlayerState._consumed_shop_sell_quote_ids == consumed_before,
		"batch save failure consumed a quote")
	var batch_retry: Dictionary = PlayerState.sell_inventory_items(batch_requests)
	assert(bool(batch_retry.get("success", false)), "batch sale did not succeed after save recovery")
	assert(PlayerState.inventory.is_empty() and PlayerState.gold == cap,
		"batch retry did not settle exactly once")


func _test_quest_entrypoint() -> void:
	_saved_quest = GameData.get_bich_quest(QUEST_ID).duplicate(true)
	assert(not _saved_quest.is_empty(), "formal quest fixture missing")
	var augmented := _saved_quest.duplicate(true)
	var rewards: Dictionary = augmented.get("rewards", {}).duplicate(true)
	var reward_items: Array = rewards.get("items", []).duplicate(true)
	reward_items.append({"name": "金币", "count": 1})
	rewards["items"] = reward_items
	augmented["rewards"] = rewards
	GameData._bich_quests_by_id[QUEST_ID] = augmented
	var currency_record: Dictionary = GameData.get_item_record("金币")
	assert(str(currency_record.get("kind", "")) == "currency", "formal currency catalog record missing")
	PlayerState.gold = 0
	var preview: Dictionary = PlayerState._build_receive_batch_result(reward_items, [])
	var currency_delta := int(currency_record.get("currencyAmount", 0))
	assert(bool(preview.get("success", false)) and int(preview.get("gold_delta", 0)) == currency_delta,
		"quest reward_items did not expose authoritative gold_delta")

	PlayerState.level = 6
	PlayerState.recalculate_stats()
	var quest_gold := int(rewards.get("gold", 0))
	var combined_gold := quest_gold + currency_delta
	var ready_state := _ready_quest_state(_saved_quest)
	PlayerState.inventory = []
	PlayerState.quest_states = {QUEST_ID: ready_state}
	PlayerState.gold = PlayerState.PLAYER_GOLD_CAP - quest_gold
	var cap_inventory_before := PlayerState.inventory.duplicate(true)
	var cap_state_before := PlayerState.quest_states.duplicate(true)
	var cap_result := PlayerState.claim_quest(QUEST_ID)
	assert(cap_result == "金币已达上限，任务奖励未领取。", "quest combined gold cap was not rejected")
	assert(PlayerState.inventory == cap_inventory_before and PlayerState.quest_states == cap_state_before,
		"quest cap rejection changed inventory or claimed state")
	assert(PlayerState.gold == PlayerState.PLAYER_GOLD_CAP - quest_gold,
		"quest cap rejection changed gold")

	PlayerState.gold = PlayerState.PLAYER_GOLD_CAP - combined_gold
	PlayerState.quest_states = {QUEST_ID: _ready_quest_state(_saved_quest)}
	var failure_inventory_before := PlayerState.inventory.duplicate(true)
	var failure_state_before := PlayerState.quest_states.duplicate(true)
	var failure_gold_before := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	var save_failed := PlayerState.claim_quest(QUEST_ID)
	PlayerState._test_force_atomic_write_failure = false
	assert(save_failed == "任务奖励存档失败，奖励未发放。", "quest save failure was not reported")
	assert(PlayerState.inventory == failure_inventory_before and PlayerState.quest_states == failure_state_before,
		"quest save failure lost inventory or ready state")
	assert(PlayerState.gold == failure_gold_before, "quest save failure changed gold")

	var claimed := PlayerState.claim_quest(QUEST_ID)
	assert(claimed.begins_with("已领取："), "quest retry did not claim rewards")
	assert(str(PlayerState.quest_states[QUEST_ID].get("status", "")) == "claimed",
		"quest success did not persist claimed status")
	assert(PlayerState.gold == PlayerState.PLAYER_GOLD_CAP, "quest retry did not merge both gold rewards")
	assert(PlayerState.item_count("布衣(男)") == 1 and PlayerState.item_count("金创药(小量)") == 3,
		"quest retry did not retain formal item rewards")
	assert(PlayerState.item_count("金币") == 0, "currency reward entered inventory instead of gold")
	var claimed_inventory := PlayerState.inventory.duplicate(true)
	var claimed_gold := PlayerState.gold
	assert(PlayerState.claim_quest(QUEST_ID) == "奖励已经领取", "quest duplicate claim was accepted")
	assert(PlayerState.inventory == claimed_inventory and PlayerState.gold == claimed_gold,
		"quest duplicate claim changed reward state")


func _test_add_gold_contract() -> void:
	PlayerState.gold = 0
	var inventory_before := PlayerState.inventory.duplicate(true)
	for invalid_amount: Variant in [-1, PlayerState.PLAYER_GOLD_CAP * 2, 0.5]:
		assert(not PlayerState.add_gold(invalid_amount), "invalid add_gold amount was accepted: %s" % invalid_amount)
		assert(PlayerState.gold == 0 and PlayerState.inventory == inventory_before,
			"invalid add_gold changed player state: %s" % invalid_amount)


func _install_full_equipment_instances(count: int, stable_prefix: String) -> Array:
	var catalog: Dictionary = GameData.get_item_record({"item_id": EQUIPMENT_ITEM_ID})
	assert(int(catalog.get("itemId", -1)) == EQUIPMENT_ITEM_ID, "formal equipment catalog item 80 missing")
	assert(str(catalog.get("kind", "")) == "equipment", "formal equipment fixture is not equipment")
	var identity := _identity_record(catalog)
	var candidates: Array = []
	for index in range(count):
		var record: Dictionary = PlayerState.create_drop_item_instance(
			identity,
			"r3:%s:%d" % [stable_prefix, index],
		)
		assert(str(record.get("identity_status", "")) == "resolved" and record.has("item_instance"),
			"formal full instance generation failed")
		var candidate := record.duplicate(true)
		candidate["item_name"] = str(catalog.get("name", ""))
		candidates.append(candidate)
	PlayerState.inventory = []
	PlayerState._consumed_shop_sell_quote_ids.clear()
	var received: Dictionary = PlayerState.receive_loot_batch_partial(candidates)
	assert(bool(received.get("success", false)) and int(received.get("success_count", 0)) == count,
		"formal full instance could not enter inventory: %s" % received)
	assert(PlayerState.inventory.size() == count, "formal full instance count changed on receipt")
	for raw_record: Variant in PlayerState.inventory:
		assert(raw_record is Dictionary and (raw_record as Dictionary).has("drop_instance_contract_id"),
			"sale fixture lost drop instance contract")
		assert(not str((raw_record as Dictionary).get("instance_id", "")).is_empty(),
			"sale fixture lost stable instance id")
	return PlayerState.inventory.duplicate(true)


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {
		"item_id": item_id,
		"canonical_item_id": item_id,
		"canonical_name": item_name,
		"source_item_id": item_id,
		"source_canonical_item_id": item_id,
		"source_canonical_name": item_name,
		"item_name": item_name,
		"name": item_name,
		"output_item_id": item_id,
		"output_record": catalog.duplicate(true),
		"identity_status": "resolved",
	}


func _sell_request(index: int, context: Dictionary) -> Dictionary:
	assert(index >= 0 and index < PlayerState.inventory.size(), "sale fixture index out of range")
	var record: Dictionary = PlayerState.inventory[index]
	var instance_id := str(record.get("instance_id", ""))
	var quote_key := "instance:%s" % instance_id if not instance_id.is_empty() else "inventory:%d" % index
	return {
		"quote_key": quote_key,
		"inventory_index": index,
		"instance_id": instance_id,
		"item_name": str(record.get("name", "")),
		"count": int(record.get("count", 1)),
		"merchant_id": str(context.get("merchant_id", "")),
		"merchant_stock_key": str(context.get("stock_key", "")),
	}


func _quote_for_request(request: Dictionary) -> Dictionary:
	var quotes: Dictionary = PlayerState.shop_sell_quotes([request])
	var quote: Dictionary = quotes.get(str(request.get("quote_key", "")), {})
	assert(bool(quote.get("sellable", false)), "formal full instance sale quote rejected: %s" % quote)
	return quote


func _request_with_quote(request: Dictionary, quote: Dictionary) -> Dictionary:
	var result := request.duplicate(true)
	result["quote_id"] = str(quote.get("quote_id", ""))
	result["amount"] = 1
	assert(not str(result.get("quote_id", "")).is_empty(), "formal sale quote id missing")
	return result


func _ready_quest_state(quest: Dictionary) -> Dictionary:
	var progress: Dictionary = {}
	var kills: Dictionary = quest.get("objectives", {}).get("kills", {})
	for objective_name: String in kills.keys():
		progress[objective_name] = int(kills[objective_name])
	return {"status": "ready", "progress": progress}


func _restore_quest() -> void:
	if not _saved_quest.is_empty():
		GameData._bich_quests_by_id[QUEST_ID] = _saved_quest.duplicate(true)


func _gold_pickup_ids() -> Dictionary:
	var result: Dictionary = {}
	for raw_node: Node in get_tree().get_nodes_in_group("loot_pickups"):
		if raw_node is LootPickup and is_instance_valid(raw_node) and int((raw_node as LootPickup).gold_amount) > 0:
			result[raw_node.get_instance_id()] = true
	return result


func _new_gold_pickup(previous_ids: Dictionary, amount: int) -> LootPickup:
	for raw_node: Node in get_tree().get_nodes_in_group("loot_pickups"):
		if (
			raw_node is LootPickup
			and is_instance_valid(raw_node)
			and not previous_ids.has(raw_node.get_instance_id())
			and int((raw_node as LootPickup).gold_amount) == amount
		):
			return raw_node as LootPickup
	return null


func _restore_player_state() -> void:
	if _saved_player_state.is_empty():
		return
	PlayerState.level = int(_saved_player_state.get("level", PlayerState.level))
	PlayerState.profession = str(_saved_player_state.get("profession", PlayerState.profession))
	PlayerState.gender = str(_saved_player_state.get("gender", PlayerState.gender))
	PlayerState.later_content_enabled = bool(_saved_player_state.get("later_content_enabled", false))
	PlayerState.game_mode_id = str(_saved_player_state.get("game_mode_id", PlayerState.game_mode_id))
	PlayerState.experience = int(_saved_player_state.get("experience", 0))
	PlayerState.gold = int(_saved_player_state.get("gold", 0))
	PlayerState.gold_overflow_records = _saved_player_state.get("gold_overflow_records", []).duplicate(true)
	PlayerState.inventory = _saved_player_state.get("inventory", []).duplicate(true)
	PlayerState.warehouse_inventory = _saved_player_state.get("warehouse_inventory", []).duplicate(true)
	PlayerState.equipment = _saved_player_state.get("equipment", {}).duplicate(true)
	PlayerState.learned_skills = _saved_player_state.get("learned_skills", {}).duplicate(true)
	PlayerState.quick_slots = _saved_player_state.get("quick_slots", []).duplicate(true)
	PlayerState.quick_item_slots = _saved_player_state.get("quick_item_slots", []).duplicate(true)
	PlayerState.equip_cycle_cursor = _saved_player_state.get("equip_cycle_cursor", {}).duplicate(true)
	PlayerState.equipment_transaction_revision = int(_saved_player_state.get("equipment_transaction_revision", 0))
	PlayerState._last_equipment_transaction_result = _saved_player_state.get("last_equipment_transaction_result", {}).duplicate(true)
	PlayerState.attack_skill_slots = _saved_player_state.get("attack_skill_slots", []).duplicate(true)
	PlayerState.attack_ring_slots = _saved_player_state.get("attack_ring_slots", []).duplicate(true)
	PlayerState.warrior_runtime_state = _saved_player_state.get("warrior_runtime_state", {}).duplicate(true)
	PlayerState.taoist_main_pet_runtime_states = _saved_player_state.get("taoist_main_pet_runtime_states", {}).duplicate(true)
	PlayerState.quest_states = _saved_player_state.get("quest_states", {}).duplicate(true)
	PlayerState.world_monster_respawn_state = _saved_player_state.get("world_monster_respawn_state", {}).duplicate(true)
	PlayerState.saved_map_id = int(_saved_player_state.get("saved_map_id", 910001))
	PlayerState.saved_position = _saved_player_state.get("saved_position", Vector2.ZERO)
	PlayerState.saved_ground_position_gu = _saved_player_state.get("saved_ground_position_gu", Vector2.ZERO)
	PlayerState.saved_ground_position_gu_valid = bool(_saved_player_state.get("saved_ground_position_gu_valid", false))
	PlayerState.computed_stats = _saved_player_state.get("computed_stats", {}).duplicate(true)
	PlayerState.computed_special_effects = _saved_player_state.get("computed_special_effects", {}).duplicate(true)
	PlayerState.durability_event_commit_count = int(_saved_player_state.get("durability_event_commit_count", 0))
	PlayerState.temporary_item_buffs = _saved_player_state.get("temporary_item_buffs", {}).duplicate(true)
	PlayerState.temporary_item_buff_revision = int(_saved_player_state.get("temporary_item_buff_revision", 0))
	PlayerState.active_profile_id = str(_saved_player_state.get("active_profile_id", ""))
	PlayerState.character_name = str(_saved_player_state.get("character_name", ""))
	PlayerState.profile_index_path = str(_saved_player_state.get("profile_index_path", PlayerState.PROFILE_INDEX_PATH))
	PlayerState.profile_directory = str(_saved_player_state.get("profile_directory", PlayerState.PROFILE_DIRECTORY))
	PlayerState.shared_warehouse_path = str(_saved_player_state.get("shared_warehouse_path", PlayerState.SHARED_WAREHOUSE_DEFAULT_PATH))
	PlayerState.shared_warehouse_transaction_log_path = str(_saved_player_state.get("shared_warehouse_transaction_log_path", PlayerState.SHARED_WAREHOUSE_TRANSACTION_LOG_PATH))
	PlayerState.test_mode = bool(_saved_player_state.get("test_mode", false))
	PlayerState._shared_warehouse_initialized = bool(_saved_player_state.get("shared_warehouse_initialized", false))
	PlayerState._active_profile_legacy_warehouse_pending = bool(_saved_player_state.get("active_profile_legacy_warehouse_pending", false))
	PlayerState._warehouse_transaction_locked = bool(_saved_player_state.get("warehouse_transaction_locked", false))
	PlayerState._persistence_transaction_in_progress = bool(_saved_player_state.get("persistence_transaction_in_progress", false))
	PlayerState._test_fail_shared_write = bool(_saved_player_state.get("test_fail_shared_write", false))
	PlayerState._test_fail_profile_write = bool(_saved_player_state.get("test_fail_profile_write", false))
	PlayerState._test_fail_warehouse_rollback_write = bool(_saved_player_state.get("test_fail_warehouse_rollback_write", false))
	PlayerState._test_force_atomic_write_failure = bool(_saved_player_state.get("test_force_atomic_write_failure", false))
	PlayerState._save_blocked_profile_id = str(_saved_player_state.get("save_blocked_profile_id", ""))
	PlayerState._save_blocked_reason = str(_saved_player_state.get("save_blocked_reason", ""))
	PlayerState._consumed_shop_sell_quote_ids = _saved_player_state.get("consumed_shop_sell_quote_ids", {}).duplicate(true)
	PlayerState._consumed_shop_buy_quote_ids = _saved_player_state.get("consumed_shop_buy_quote_ids", {}).duplicate(true)
	PlayerState._shop_buy_quote_serial = int(_saved_player_state.get("shop_buy_quote_serial", 0))
	PlayerState._shop_pricing_session_nonce = str(_saved_player_state.get("shop_pricing_session_nonce", ""))
	PlayerState._item_instance_serial = int(_saved_player_state.get("item_instance_serial", 0))
	PlayerState._autosave_elapsed = float(_saved_player_state.get("autosave_elapsed", 0.0))
	PlayerState.last_save_result = _saved_player_state.get("last_save_result", {}).duplicate(true)
	PlayerState.last_load_result = _saved_player_state.get("last_load_result", {}).duplicate(true)
	PlayerState._skill_progression.load_snapshot(_saved_player_state.get("skill_progression", {}))


func _cleanup_isolated_storage() -> void:
	if _storage_root.is_empty():
		return
	var known_paths := [
		_storage_root.path_join("profiles.json"),
		_storage_root.path_join("shared.json"),
		_storage_root.path_join("shared.transaction.json"),
		_storage_root.path_join("characters").path_join("%s.json" % TEST_PROFILE_ID),
	]
	for base_path: String in known_paths:
		for suffix: String in ["", ".bak", ".tmp", ".corrupt.tmp"]:
			var path := base_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for directory: String in [_storage_root.path_join("characters"), _storage_root]:
		var absolute := ProjectSettings.globalize_path(directory)
		if DirAccess.dir_exists_absolute(absolute):
			DirAccess.remove_absolute(absolute)
