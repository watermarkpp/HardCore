extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Slots := preload("res://scripts/identity/equipment_identity_codec.gd")
const Items := preload("res://scripts/items/item_extension_codec.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
const Loadouts := preload("res://scripts/equipment_test_loadout_catalog.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	proof.record(value, message)
	checks += 1
	if not value: failures.append(message)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.set_process(false)
	PlayerState.reset_progress(false)
	check(PlayerState.EQUIPMENT_SLOTS == Slots.SLOTS and PlayerState.equipment.size() == 10,
		"actual equipment owner has exactly the existing ten registered slots in original order")
	for slot: String in Slots.SLOTS:
		check(PlayerState.equipment.has(slot) and not PlayerState.equipment.has(Registry.legacy(slot, "slot")),
			"actual owner has one canonical slot and no Chinese-key shadow: " + slot)
	check(PlayerState.equip_cycle_cursor == Slots.default_cycles(), "two-slot cursor is owned by registered slot IDs")
	var old := {"equipment": {"武器": {"name": "木剑", "count": 1, "item_id": 80},
		"手镯": {"name": "铁手镯", "count": 1, "item_id": 174}},
		"equip_cycle_cursor": {"戒指": "右戒指", "手镯": "左手镯"}}
	var imported := Items.decode_document(old)
	check(imported.status == Items.KNOWN_VALID and imported.document.equipment.has("hc.slot.weapon")
		and imported.document.equipment.has("hc.slot.bracelet_left"), "legacy exact/generic slots migrate once at the document boundary")
	check(old.equipment.has("武器") and not old.equipment.has("hc.slot.weapon"), "legacy slot import preserves original caller evidence")
	check(imported.document.equip_cycle_cursor == {"hc.slot.ring_left": "hc.slot.ring_right", "hc.slot.bracelet_left": "hc.slot.bracelet_left"},
		"legacy cursor import preserves its next physical slot exactly")
	var encoded := Items.encode_document(imported.document)
	check(encoded.status == Items.KNOWN_VALID and encoded.document.get(Slots.FIELD) == Slots.HEADER,
		"real aggregate encoder emits the formal equipment identity contract")
	var restored := Items.decode_document(encoded.document)
	check(restored.status == Items.KNOWN_VALID and restored.document.equipment == imported.document.equipment,
		"formal equipment slots retain item bytes without a second equipment owner")
	var bad: Dictionary = encoded.document.duplicate(true)
	bad.equipment["武器"] = bad.equipment["hc.slot.weapon"]
	bad.equipment.erase("hc.slot.weapon")
	check(Items.decode_document(bad).status == Items.OPAQUE_UNSUPPORTED, "formal slot contract cannot reenter Chinese legacy mapping")
	bad = encoded.document.duplicate(true)
	bad.equipment["hc.slot.skill"] = {}
	check(Items.decode_document(bad).status == Items.OPAQUE_UNSUPPORTED, "registered contribution pseudo-slot cannot become a physical equipment owner")
	bad = old.duplicate(true)
	bad.equipment["hc.slot.weapon"] = old.equipment["武器"]
	check(Items.decode_document(bad).status == Items.OPAQUE_UNSUPPORTED, "two occupied aliases fail the entire migration even when item bytes match")
	bad = old.duplicate(true)
	bad.equipment["左手镯"] = {}
	check(Items.decode_document(bad).status == Items.KNOWN_VALID, "legacy empty left hole does not discard its occupied generic bracelet")
	bad = encoded.document.duplicate(true)
	bad.equip_cycle_cursor["hc.slot.ring_left"] = "hc.slot.weapon"
	check(Items.decode_document(bad).status == Items.OPAQUE_UNSUPPORTED, "a cycle cannot select a slot from another equipment group")
	bad = encoded.document.duplicate(true)
	bad[Slots.FIELD].schema_version = 999
	bad.equipment["hc.slot.weapon"].count = -1
	check(Items.decode_document(bad).status == Items.OPAQUE_UNSUPPORTED, "future slot identity precedes corrupt known item fields")
	var catalog := Loadouts.load_catalog()
	check(catalog.supportedSlots == Loadouts.REQUIRED_SLOTS and catalog.loadouts.size() == 9,
		"all actual nine authoring loadouts translate their supported slots at one ingress")
	for loadout: Dictionary in catalog.loadouts:
		check(loadout.equipment.keys().size() == 8 and loadout.equipment.has("hc.slot.weapon"),
			"actual source loadout preserves its eight item records behind formal slot keys: " + str(loadout.loadoutId))
	var directory := "user://equipment_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = "equipment-identity"
	PlayerState.character_name = "装备身份验收"
	PlayerState.inventory = []
	PlayerState.receive("hc.item.000080", 1, false)
	check(PlayerState.equip_inventory_index(0, "hc.slot.weapon").begins_with("已装备"), "actual equip command writes the canonical slot owner")
	var weapon: Dictionary = PlayerState.equipment["hc.slot.weapon"].duplicate(true)
	check(not weapon.is_empty() and not PlayerState.equipment.has("武器"), "actual equip has no name-key mirror")
	PlayerState.test_mode = false
	check(PlayerState.save_game(false, false), "actual character writer saves equipment identity")
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var raw := FileAccess.get_file_as_string(path)
	var disk: Dictionary = JSON.parse_string(raw)
	check(disk.get(Slots.FIELD) == JSON.parse_string(JSON.stringify(Slots.HEADER)) and disk.equipment.has("hc.slot.weapon"),
		"disk document contains only formal equipment ownership and explicit version")
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.load_save()
	check(PlayerState.last_load_result.get("success", false) and PlayerState.equipment["hc.slot.weapon"].instance_id == weapon.instance_id,
		"actual reload preserves equipped instance identity")
	# A real old-slot document is validated before live ownership changes.
	var legacy_disk: Dictionary = disk.duplicate(true)
	legacy_disk.erase(Slots.FIELD)
	var legacy_slots := {}
	for slot: String in legacy_disk.equipment:
		legacy_slots[Registry.legacy(slot, "slot")] = legacy_disk.equipment[slot]
	legacy_disk.equipment = legacy_slots
	legacy_disk.equip_cycle_cursor = {"戒指": "右戒指", "手镯": "左手镯"}
	var archive_source: Dictionary = legacy_disk.duplicate(true)
	archive_source.erase("death_event_sequence")
	archive_source.erase("world_clock_generation")
	var archive_path: String = PlayerState._archive_legacy_world_clock_profile(archive_source)
	check(not archive_path.is_empty(), "actual migration archive accepts supported old slot ownership")
	if not archive_path.is_empty():
		var archived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(archive_path))
		check(PlayerState._shared_digest(archived) == PlayerState._shared_digest(archive_source),
			"migration before-image retains exact identity shape and source digest")
		check(PlayerState._archive_legacy_world_clock_profile(archive_source) == archive_path,
			"a repeated legacy migration finds its same verified original archive")
	_write(path, JSON.stringify(legacy_disk))
	PlayerState.load_save()
	check(PlayerState.last_load_result.get("success", false) and PlayerState.equipment["hc.slot.weapon"].instance_id == weapon.instance_id
		and PlayerState.equip_cycle_cursor["hc.slot.ring_left"] == "hc.slot.ring_right", "actual old disk slots and next-cycle selection import without losing gear")
	check(PlayerState.save_game(false, false), "first legitimate save persists the imported formal slots")
	var valid_raw := FileAccess.get_file_as_string(path)
	var future: Dictionary = JSON.parse_string(valid_raw)
	future[Slots.FIELD].schema_version = 999
	var future_raw := JSON.stringify(future, "  ") + "\n"
	_write(path, future_raw)
	_write(path + ".bak", valid_raw)
	var before: Dictionary = PlayerState.equipment.duplicate(true)
	PlayerState.load_save()
	check(not PlayerState.last_load_result.get("success", false) and PlayerState.equipment == before,
		"actual future slot identity preserves live equipment even with a good backup")
	check(FileAccess.get_file_as_string(path) == future_raw and FileAccess.get_file_as_string(path + ".bak") == valid_raw,
		"unsupported slot identity preserves both original file bytes")
	check(PlayerState._prepare_character_save_payload(false).is_empty(), "future equipment identity blocks subsequent character writes")
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	proof.write_receipt("equipment_identity_test", checks, failures.size())
	print("EQUIPMENT_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()
