extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	var potion_id := GameData.item_entity_id("太阳水")
	var gear_id := GameData.item_entity_id("木剑")
	check(not potion_id.is_empty() and not gear_id.is_empty(), "existing authoring sources provide actual registered identities")
	var aliases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/identity/entity_registry_source.json"))
	for alias: Dictionary in aliases.aliases:
		var actual := GameData.get_entity_record(alias.alias_id)
		var direct := GameData.get_entity_record(alias.canonical_id)
		var expected := actual.duplicate(true)
		expected["itemId"] = int(alias.canonical_id.get_slice(".", 2))
		expected["identityBridge"] = "dpv2.direct_item_identity.v2"
		check(actual.size() > 0 and expected == direct, "explicit service/direct link retains every actual rule and art field " + alias.alias_id)
		check(GameData.get_item_price_record(alias.alias_id) == GameData.get_item_price_record(alias.canonical_id),
			"declared aliases retain the existing sole price source " + alias.canonical_id)
	check(bool(PlayerState.receive(potion_id, 2, false).get("success", false)), "typed receive uses existing inventory authority")
	check(PlayerState.inventory.size() == 1 and PlayerState.inventory[0].has("item_id"), "new ordinary records persist their numeric identity")
	check(PlayerState.inventory.size() == 1 and PlayerState.inventory[0].name == "太阳水", "typed identity is never used as player-visible name")
	PlayerState.inventory = [{"item_id": 920001, "name": "仅显示文字", "count": 2}]
	check(PlayerState.item_count("hc.item.920001") == 2, "count resolves a registered identity independently of display")
	var received: Dictionary = PlayerState.receive("hc.item.920001", 1, false)
	check(bool(received.get("success", false)) and PlayerState.inventory.size() == 1 and PlayerState.inventory[0].count == 3, "same ID with changed display stacks into the existing record")
	check(GameData.get_item_record({"item_id": "wrong", "name": "太阳水"}).is_empty(), "invalid explicit numeric identity cannot fall through to name")
	check(GameData.get_item_record(85.5).is_empty(), "numeric reference cannot truncate into another registered item")
	check(GameData.get_item_record({"item_id": 88, "service_index": 999999, "name": "太阳水"}).is_empty(), "conflicting explicit identity does not select either side")
	check(GameData.get_item_price_record("hc.item.000088") == GameData.get_item_price_record({"item_id": 88}), "pricing accepts the same formal identity as rules")
	PlayerState.inventory = []
	PlayerState.receive(gear_id, 1, false)
	check(PlayerState.inventory.size() == 1 and PlayerState.inventory[0].has("item_id"), "new non-drop equipment also has an actual identity")
	PlayerState.inventory = [{"service_index": 123, "name": "显示可变化", "count": 2}]
	var service_id := "hc.service_item.000123"
	check(GameData.get_entity_record(service_id).size() > 0 and PlayerState.item_count(service_id) == 2, "service-only catalog items keep their separate typed namespace")
	var before := PlayerState.inventory.duplicate(true)
	check(not bool(PlayerState.receive("hc.monster.000019", 1, false).get("success", false)) and PlayerState.inventory == before, "cross-kind receive is rejected atomically")
	var Codec := preload("res://scripts/items/item_extension_codec.gd")
	var Header := preload("res://scripts/identity/item_identity_codec.gd")
	var legacy := {"inventory": [{"name": "太阳水", "count": 2}], "equipment": {"武器": {"name": "木剑", "count": 1}}}
	var imported := Codec.decode_document(legacy)
	check(imported.status == Codec.KNOWN_VALID and imported.document.inventory[0].item_id == 920014 \
		and imported.document.equipment["hc.slot.weapon"].item_id == 80, "legacy name-only save imports exact identities at the codec boundary")
	check(not legacy.inventory[0].has("item_id"), "legacy import preserves the caller and original historical evidence")
	var wire := Codec.encode_document(imported.document)
	check(wire.status == Codec.KNOWN_VALID and wire.document.get(Header.FIELD) == Header.HEADER, "actual item writer emits the formal identity sub-contract")
	var decoded := Codec.decode_document(wire.document)
	check(decoded.status == Codec.KNOWN_VALID and decoded.document.inventory[0].item_id == 920014, "formal item identity survives JSON ownership decoding")
	var malformed: Dictionary = wire.document.duplicate(true)
	malformed.inventory[0].erase("item_id")
	check(Codec.decode_document(malformed).status == Codec.OPAQUE_UNSUPPORTED, "formal record cannot re-enter legacy name import")
	malformed = wire.document.duplicate(true)
	malformed.inventory[0].item_id = 999999
	check(Codec.decode_document(malformed).status == Codec.OPAQUE_UNSUPPORTED, "unknown formal item identity stops aggregate recovery")
	malformed = wire.document.duplicate(true)
	malformed[Header.FIELD].schema_version = 999
	malformed.inventory[0].count = -1
	check(Codec.decode_document(malformed).status == Codec.OPAQUE_UNSUPPORTED, "future item identity takes priority over a corrupt known sibling")
	var alias_record := Codec.decode_document({"inventory": [{"service_index": 670, "name": "改显示", "count": 2}]})
	check(alias_record.status == Codec.KNOWN_VALID and alias_record.document.inventory[0].item_id == 920014 \
		and not alias_record.document.inventory[0].has("service_index"), "declared old service alias imports one canonical item ownership")
	check(PlayerState.item_count_by_entity_id("hc.service_item.000123") == 2, "unmapped service namespace retains its actual independent identity")
	var actual_potion := GameData.get_entity_record("hc.item.920014")
	var saved_name_index: Dictionary = GameData._catalog_by_name
	GameData._catalog_by_name = {}
	check(GameData.get_entity_record("hc.item.920014") == actual_potion \
		and GameData.get_item_art_path("hc.item.920014") == actual_potion.art.inventoryIcon.path,
		"actual typed rule and art consumers remain independent of the entire display-name index")
	GameData._catalog_by_name = saved_name_index
	check(GameData.get_item_price_record({"item_id": 999999, "name": "太阳水"}).is_empty(),
		"unknown explicit identity cannot price a different named object")
	var directory := "user://ordinary_item_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "ordinary-item-identity"
	PlayerState.character_name = "物品身份验收"
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.inventory = imported.document.inventory.duplicate(true)
	PlayerState.test_mode = false
	check(PlayerState.save_game(false, false), "actual isolated character writer saves canonical item identities")
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var valid_raw := FileAccess.get_file_as_string(path)
	var actual_save: Dictionary = JSON.parse_string(valid_raw)
	check(actual_save.get(Header.FIELD) == JSON.parse_string(JSON.stringify(Header.HEADER)) and int(actual_save.inventory[0].item_id) == 920014,
		"actual disk record carries the same formal item identity contract")
	PlayerState.inventory = []
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and PlayerState.item_count("hc.item.920014") == 2,
		"real loader restores the formal item without name identity")
	actual_save[Header.FIELD].schema_version = 999
	var future_raw := JSON.stringify(actual_save, "  ") + "\n"
	var main_file := FileAccess.open(path, FileAccess.WRITE)
	main_file.store_string(future_raw)
	main_file.close()
	var backup_file := FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup_file.store_string(valid_raw)
	backup_file.close()
	var prior_inventory := PlayerState.inventory.duplicate(true)
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)) and PlayerState.inventory == prior_inventory,
		"actual future item identity load preserves the current owner despite a good backup")
	check(FileAccess.get_file_as_string(path) == future_raw and FileAccess.get_file_as_string(path + ".bak") == valid_raw,
		"unsupported item identity preserves primary and backup bytes")
	check(PlayerState._prepare_character_save_payload(false).is_empty(), "unsupported item identity locks further character writes")
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	proof.write_receipt("ordinary_item_identity_test", checks, failures.size())
	print("ORDINARY_ITEM_IDENTITY_%s checks=%d errors=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
