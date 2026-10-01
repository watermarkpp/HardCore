extends Node

const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(PlayerState.has_method("quote_item_transaction") and PlayerState.has_method("commit_item_transaction"),
		"production player exposes the common quote and commit port")
	if not failures.is_empty():
		_finish()
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	var directory := "user://framework_socket_transaction_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "socket-transaction"
	PlayerState.character_name = "镶嵌事务验收"
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	var base := Drop.create_instance(GameData.get_item_record({"item_id": 80}), "socket:target")
	var gem := Gem.create_instance("socket:gem", true)
	PlayerState.inventory = [base, gem, {"item_id": 88, "name": GameData.get_item_record({"item_id": 88}).name, "count": 5}]
	PlayerState.gold = 500
	PlayerState.test_mode = false
	check(PlayerState.save_game(false, false), "real isolated profile persists the unmodified inputs")
	var request := {"operation_id": "socket:insert:1", "action": "hc.socketing.insert",
		"target_instance_id": base.instance_id, "gem_instance_id": gem.instance_id}
	check(not bool(PlayerState.call("quote_item_transaction", request).get("success", false)),
		"registered fixture remains default off at the production transaction gate")
	check(ContentLayers.set_feature_module_enabled(Gem.MODULE, true), "fixture activates through the existing compiled module gate")
	var quote: Dictionary = PlayerState.call("quote_item_transaction", request)
	check(bool(quote.get("success", false)) and PlayerState.inventory == [base, gem, PlayerState.inventory[2]],
		"quote is read only and identifies original target and gem")
	if not bool(quote.get("success", false)):
		_finish()
		return
	# A UI index is not a permanent identity. Reordering unrelated to the quote
	# must preserve which exact two original instances get committed.
	PlayerState.inventory = [PlayerState.inventory[2], gem, base]
	var pending: Dictionary = PlayerState.call("commit_item_transaction", quote)
	check(bool(pending.get("pending", false)) and not bool(pending.get("durable", false)), "new precious result is pending until its actual durable receipt")
	check(PlayerState.inventory[1] == gem and Codec.extensions(PlayerState.inventory[2]).is_empty(),
		"accepting a command does not expose or consume inputs ahead of durability")
	var repeated: Dictionary = PlayerState.call("commit_item_transaction", quote)
	check(repeated.get("job") == pending.get("job") and PlayerState._json_persistence.pending_count() == 1,
		"double click returns the same accepted operation and sole writer job")
	check(not bool(PlayerState.place_workbench_item("forge", 0, 1, true).get("success", false)),
		"a pending gem cannot move into the live background workbench")
	check(PlayerState._consume_inventory_index(0, 1, true), "unrelated potion consumption stays immediate during the pending operation")
	PlayerState.gold += 17
	check(PlayerState.experience_to_next_level() > 1, "reward preservation fixture stays below the authoritative level-up threshold")
	var kills := [{"monster_name": "socket:combat-fixture", "experience": 1}]
	var deferred_battle: Dictionary = PlayerState.prepare_death_settlement(kills, {})
	check(bool(deferred_battle.get("pending", false)) and PlayerState.experience == 0,
		"real death settlement preserves its pending work while the same ordered writer owns the socket operation")
	var receipt := await _wait(pending.get("job"))
	check(bool(receipt.get("success", false)), "existing ordered worker returns a real successful socket receipt")
	check(PlayerState.gold == 517 and PlayerState.experience == 0 and PlayerState.inventory[0].count == 4,
		"receipt applies only related item ownership and preserves intervening potion and gold state")
	var battle: Dictionary = PlayerState.prepare_death_settlement(kills, {})
	var battle_receipt := await _wait(battle.get("writer").job if battle.has("writer") else null)
	check(battle.has("writer") and bool(battle_receipt.get("success", false)) \
		and PlayerState.experience == 1 and bool(PlayerState.finish_prepared_death_settlement(battle).get("success", false)),
		"real death journal commits its original reward once after the item operation without erasing either ownership result")
	check(PlayerState.inventory[1].is_empty() and Codec.ownership_ids(PlayerState.inventory[2]) == [base.instance_id, gem.instance_id],
		"one exact gem moves into one exact gear instance regardless of old index")
	check(PlayerState._validate_extended_item_ownership({"inventory": PlayerState.inventory}), "accepted runtime aggregate has unique embedded ownership")
	check(bool(PlayerState.call("commit_item_transaction", quote).get("durable", false)),
		"retrying the original accepted quote after completion returns its stored outcome")
	var owned_before := PlayerState.inventory.duplicate(true)
	check(not bool(PlayerState.destroy_inventory_indices([2]).get("success", false)) and PlayerState.inventory == owned_before,
		"actual destruction rejects embedded ownership without discarding either item")
	var sell_quote: Dictionary = PlayerState._shop_sell_quote({"inventory_index": 2})
	check(not bool(sell_quote.get("sellable", false)) and str(sell_quote.reason).contains("镶嵌"),
		"actual sell quote requires removing the uniquely owned embedded item first")
	check(Detail.format_item(GameData.get_item_record(PlayerState.inventory[2]), PlayerState.inventory[2]).contains("镶嵌：测试宝石"),
		"actual detail presenter reads the registered embedded item name from the same catalog")
	check(not bool(PlayerState._build_receive_result_for_record(PlayerState.inventory[2], PlayerState.inventory, true).get("success", false)),
		"external pickup rejects an already owned extended gear instance")
	var another_base := Drop.create_instance(GameData.get_item_record({"item_id": 81}), "socket:another-owner")
	var duplicate_gem := Codec.with_extensions(another_base, Codec.extensions(PlayerState.inventory[2]))
	check(duplicate_gem.status == Codec.KNOWN_VALID and not bool(PlayerState._build_receive_result_for_record(duplicate_gem.item, PlayerState.inventory, true).get("success", false)),
		"a new external gear identity cannot duplicate a gem already embedded in another owned gear")
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	var path := PlayerState._profile_path(PlayerState.active_profile_id)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(disk.gold == 517 and disk.experience == 1 and disk.inventory[0].count == 4,
		"next ordinary save includes intervening state without erasing the accepted operation")
	PlayerState.inventory = []
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.success) and Codec.ownership_ids(PlayerState.inventory[2]) == [base.instance_id, gem.instance_id],
		"actual restart restores embedded ownership and the durable transaction journal")
	var replay: Dictionary = PlayerState.call("quote_item_transaction", request)
	var replayed: Dictionary = PlayerState.call("commit_item_transaction", replay)
	check(bool(replayed.get("durable", false)) and not bool(replayed.get("pending", false)) and PlayerState._json_persistence.pending_count() == 0,
		"same operation after restart returns original outcome without another consume or write")
	var remove_request := {"operation_id": "socket:remove:1", "action": "hc.socketing.remove",
		"target_instance_id": base.instance_id, "gem_instance_id": ""}
	var remove_quote: Dictionary = PlayerState.call("quote_item_transaction", remove_request)
	var remove_pending: Dictionary = PlayerState.call("commit_item_transaction", remove_quote)
	check(bool(remove_pending.get("pending", false)), "remove enters the same reserved ordered transaction port")
	var removed := await _wait(remove_pending.get("job"))
	check(bool(removed.get("success", false)) and Codec.extensions(PlayerState.inventory[2])[Codec.SOCKET_NAMESPACE].sockets.is_empty(),
		"remove empties only the chosen socket after the durable receipt")
	check(PlayerState.inventory[1].instance_id == gem.instance_id and Gem.valid_instance(PlayerState.inventory[1]),
		"remove returns the original uniquely identified gem to its reserved inventory vacancy")
	check(PlayerState._validate_extended_item_ownership({"inventory": PlayerState.inventory}), "removed gem remains singly owned")
	# Existing profile saves must never publish the wire wrapper back into the
	# live inventory when they acknowledge an unchanged extended item.
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	check(PlayerState.inventory[2].has(Codec.RUNTIME_EXTENSION) and not PlayerState.inventory[2].has("base"),
		"ordinary background save acknowledges an extension without replacing live runtime items with wire containers")
	var conflict := request.duplicate(true)
	conflict.target_instance_id = "socket:another-target"
	check(not bool(PlayerState.call("quote_item_transaction", conflict).get("success", false)),
		"a reused operation ID with different inputs is rejected after restart")
	var journal_document := {"profile_id": PlayerState.active_profile_id,
		Journal.FIELD: PlayerState._item_transaction_journal.duplicate(true)}
	var unknown := journal_document.duplicate(true)
	unknown[Journal.FIELD].schema_version = 2
	check(bool(Journal.validate_document(unknown).terminal), "future journal versions forbid recovery over economic history")
	var bad := journal_document.duplicate(true)
	bad[Journal.FIELD].entries.append(bad[Journal.FIELD].entries[0].duplicate(true))
	check(not bool(Journal.validate_document(bad).valid), "duplicate operation IDs invalidate the whole economic journal")
	# Reinsert and equip using real existing consumers; the gem contributes
	# through the common compiler and disappears independently on removal.
	request.operation_id = "socket:insert:2"
	var insert_again: Dictionary = PlayerState.call("commit_item_transaction", PlayerState.call("quote_item_transaction", request))
	check(bool((await _wait(insert_again.get("job"))).get("success", false)), "a new explicitly identified operation can reinsert the original gem")
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	var accuracy_before := int(PlayerState.computed_stats.accuracy)
	var equip_result: Dictionary = PlayerState.equip_inventory_index_result(2, "hc.slot.weapon", base.instance_id)
	check(bool(equip_result.get("success", false)) and int(PlayerState.computed_stats.accuracy) == accuracy_before + 1,
		"real equipped gem contributes one fixture accuracy through the existing loadout compiler")
	var sources: Dictionary = PlayerState.feature_bundle().get("sources", {})
	var gem_sources := 0
	for source: Dictionary in sources.values():
		if source.instance_id == gem.instance_id and source.get("extension_id", "").contains(base.instance_id): gem_sources += 1
	check(gem_sources == 1, "compiled gem provenance preserves its own instance and exact gear/socket owner")
	remove_request.operation_id = "socket:remove:2"
	var equipped_remove: Dictionary = PlayerState.call("commit_item_transaction", PlayerState.call("quote_item_transaction", remove_request))
	check(bool((await _wait(equipped_remove.get("job"))).get("success", false)) and int(PlayerState.computed_stats.accuracy) == accuracy_before,
		"removing from real equipped gear withdraws only that gem contribution")
	await _verify_boundaries(request, path)
	ContentLayers.set_feature_module_enabled(Gem.MODULE, false)
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	_finish()

func _verify_boundaries(request: Dictionary, path: String) -> void:
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	var snapshot: Dictionary = PlayerState._creation_runtime_snapshot()
	var journal_before: Dictionary = PlayerState._item_transaction_journal.duplicate(true)
	PlayerState.gold += 11
	PlayerState._restore_creation_runtime(snapshot)
	check(PlayerState.gold == int(snapshot.gold) and PlayerState._item_transaction_journal == journal_before,
		"actual character-creation rollback restores the original journal without a second economic authority")
	request.operation_id = "socket:wear:1"
	var quote: Dictionary = PlayerState.call("quote_item_transaction", request)
	var pending: Dictionary = PlayerState.call("commit_item_transaction", quote)
	check(bool(pending.get("pending", false)), "equipped insertion accepts a new exact operation before combat wear")
	if not bool(pending.get("pending", false)): return
	var until := Time.get_ticks_msec() + 5000
	while PlayerState._json_persistence._queue[0].phase != "PROMOTING" and Time.get_ticks_msec() < until:
		PlayerState._json_persistence.pump()
		await get_tree().process_frame
	check(PlayerState._json_persistence._queue[0].phase == "PROMOTING", "late-event fixture reaches actual irreversible file promotion")
	var durability_before := int(PlayerState.equipment["hc.slot.weapon"].durability_raw)
	var wear: Dictionary = PlayerState.apply_durability_event(PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "weapon_roll": 4, "weapon_strong": 0, "damage": 1})
	check(bool(wear.applied), "actual physical-hit authority applies combat wear during socket promotion")
	ContentLayers.set_feature_module_enabled(Gem.MODULE, false)
	var receipt := await _wait(pending.get("job"))
	check(bool(receipt.get("success", false)) and int(PlayerState.equipment["hc.slot.weapon"].durability_raw) == durability_before - int(wear.raw_loss),
		"durable ownership receipt preserves newer wear and survives module disable after the irreversible boundary")
	if not bool(receipt.get("success", false)): return
	check(Codec.ownership_ids(PlayerState.equipment["hc.slot.weapon"]) == [request.target_instance_id, request.gem_instance_id],
		"irreversible accepted insertion publishes exactly one original gem even after deactivation")
	ContentLayers.set_feature_module_enabled(Gem.MODULE, true)
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	var remove_request := {"operation_id": "socket:wear:remove", "action": "hc.socketing.remove",
		"target_instance_id": request.target_instance_id, "gem_instance_id": ""}
	var removed: Dictionary = PlayerState.call("commit_item_transaction", PlayerState.call("quote_item_transaction", remove_request))
	check(bool((await _wait(removed.get("job"))).get("success", false)), "original gem remains removable after wear and late deactivation")
	PlayerState._start_item_save()
	PlayerState._json_persistence.drain()
	request.operation_id = "socket:prepromotion:cancel"
	quote = PlayerState.call("quote_item_transaction", request)
	pending = PlayerState.call("commit_item_transaction", quote)
	var owned_before := PlayerState.inventory.duplicate(true)
	var equipment_before := PlayerState.equipment.duplicate(true)
	var bytes_before := FileAccess.get_file_as_bytes(path)
	ContentLayers.set_feature_module_enabled(Gem.MODULE, false)
	receipt = await _wait(pending.get("job"))
	check(not bool(receipt.get("success", false)) and PlayerState.inventory == owned_before and PlayerState.equipment == equipment_before \
		and FileAccess.get_file_as_bytes(path) == bytes_before,
		"deactivation before promotion rejects without consuming inputs or replacing durable bytes")
	ContentLayers.set_feature_module_enabled(Gem.MODULE, true)
	var full := journal_before.duplicate(true)
	while full.entries.size() < Journal.LIMIT:
		var entry: Dictionary = full.entries[0].duplicate(true)
		entry.operation_id = "socket:full:%d" % full.entries.size()
		full.entries.append(entry)
	check(Journal.validate_document({"profile_id": PlayerState.active_profile_id, Journal.FIELD: full}).valid \
		and Journal.appended(full, PlayerState.active_profile_id, full.entries[0]).is_empty() and full.entries.size() == Journal.LIMIT,
		"bounded journal refuses new operations without evicting any exact-once outcome")
	var known_bytes := FileAccess.get_file_as_bytes(path)
	var future: Dictionary = JSON.parse_string(known_bytes.get_string_from_utf8())
	var mixed := future.duplicate(true)
	mixed.inventory = [{"contract_id": Codec.CONTRACT, "format_version": 2, "entity_id": 123,
		"base": {}, "extensions": {}}]
	mixed.character_identity.contract_id = "hardcore.character.identity.v2"
	check(bool(PlayerState._validate_profile_document_status(mixed, PlayerState.active_profile_id, false).terminal),
		"future character identity remains terminal even with a malformed known item sibling")
	mixed.character_identity = future.character_identity.duplicate(true)
	mixed.save_version = PlayerState.SAVE_VERSION + 1
	check(bool(PlayerState._validate_profile_document_status(mixed, PlayerState.active_profile_id, false).terminal),
		"future outer profile remains terminal even with a malformed known item sibling")
	future[Journal.FIELD].schema_version = 2
	var future_bytes := (JSON.stringify(future, "\t") + "\n").to_utf8_buffer()
	for pair: Array in [[path + ".bak", known_bytes], [path, future_bytes]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		file.store_buffer(pair[1])
		file.close()
	var live_before := PlayerState.inventory.duplicate(true)
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.success) and PlayerState.inventory == live_before,
		"actual reload refuses a future economic journal despite an older valid backup")
	check(not PlayerState.save_game(false, false, false) and FileAccess.get_file_as_bytes(path) == future_bytes \
		and FileAccess.get_file_as_bytes(path + ".bak") == known_bytes,
		"future transaction aggregate retains exact primary and backup bytes under the real save lock")

func _wait(job: Variant) -> Dictionary:
	if job == null: return {"success": false}
	var until := Time.get_ticks_msec() + 5000
	while not bool(job.response.get("finished", false)) and Time.get_ticks_msec() < until:
		PlayerState._json_persistence.pump()
		await get_tree().process_frame
	return job.response

func _finish() -> void:
	if not proof.write_receipt("socket_transaction_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_SOCKET_TRANSACTION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
