extends Node

const Codec := preload("res://scripts/items/item_extension_codec.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const Rune := preload("res://scripts/items/rune_item_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var profile_path := ""
var profile_bytes := ""
var shared_bytes := ""
var base: Dictionary = {}
var wire: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func put(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned file opens " + path.get_file())
	if file != null:
		file.store_string(value)
		file.close()

func json_equal(actual: Variant, expected: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(actual)) == JSON.parse_string(JSON.stringify(expected))

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var directory := "user://framework_future_owner_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "future-owner"
	PlayerState.character_name = "未来版本归属验收"
	PlayerState._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,
		"fixture owns a fresh profile and account directory")
	base = DropRules.create_instance(GameData.get_item_record({"item_id": 80}), "future-owner:original")
	var created := Codec.with_extensions(base, {"hc.socketing": {"schema_version": 1, "sockets": []}})
	check(created.status == Codec.KNOWN_VALID, "fixture uses a real registered drop and supported extension")
	if created.status != Codec.KNOWN_VALID:
		_finish()
		return
	wire = Codec.encode_runtime(created.item).item
	PlayerState.inventory = [base]
	PlayerState.test_mode = false
	check(PlayerState.save_game(false, false, false), "real writer produces the known profile and shared owner")
	profile_path = PlayerState._profile_path(PlayerState.active_profile_id)
	profile_bytes = FileAccess.get_file_as_string(profile_path)
	shared_bytes = FileAccess.get_file_as_string(PlayerState.shared_warehouse_path)
	check(not profile_bytes.is_empty() and not shared_bytes.is_empty(), "known backup bytes exist on disk")
	if profile_bytes.is_empty() or shared_bytes.is_empty():
		_finish()
		return
	var known_profile: Dictionary = JSON.parse_string(profile_bytes)
	var known_shared: Dictionary = JSON.parse_string(shared_bytes)
	check(bool(PlayerState._validate_profile_document_status(known_profile, PlayerState.active_profile_id, false).valid),
		"known profile backup passes the real aggregate validator")
	check(bool(PlayerState._validate_shared_warehouse_document_status(known_shared).valid),
		"known shared backup passes the real aggregate validator")
	var large: Array = []
	large.resize(5000)
	large.fill(1)
	var deep: Dictionary = {"leaf": "future-owned bytes"}
	for depth in range(24):
		deep = {"child": deep}
	var future_large := wire.duplicate(true)
	future_large.format_version = Codec.VERSION + 1
	future_large["opaque_body"] = large
	var future_deep := wire.duplicate(true)
	future_deep.format_version = Codec.VERSION + 1
	future_deep["opaque_body"] = deep
	var future_namespace := wire.duplicate(true)
	future_namespace.extensions = {"hc.future": {"schema_version": 1, "opaque_body": large}}
	var future_socket := wire.duplicate(true)
	future_socket.extensions["hc.socketing"] = {"schema_version": 2, "opaque_body": large}
	var future_contract := wire.duplicate(true)
	future_contract.contract_id = "hardcore.item.container.v3"
	future_contract["opaque_body"] = deep
	# A recognized future envelope owns even a field reserved by today's codec.
	var future_private := future_large.duplicate(true)
	future_private[Codec.RUNTIME_EXTENSION] = "a future format owns this field"
	var future_contract_version := future_contract.duplicate(true)
	future_contract_version.format_version = "a future contract owns its version encoding"
	var future_version_contract := future_large.duplicate(true)
	future_version_contract.erase("contract_id")
	var candidates: Array[Dictionary] = [future_large, future_deep, future_namespace,
		future_socket, future_contract, future_private, future_contract_version, future_version_contract]
	var rune:=Rune.create_instance("future-owner:rune",true)
	var rune_created:=Codec.with_extensions(base,{"hc.runes":{"schema_version":1,"runes":[{"rune_slot_id":Codec.RUNE_ID,"item":rune}]}})
	check(rune_created.status==Codec.KNOWN_VALID,"new rune cases begin with a real registered uniquely owned supported asset")
	if rune_created.status!=Codec.KNOWN_VALID: _finish(); return
	var rune_wire: Dictionary=Codec.encode_runtime(rune_created.item).item
	var future_rune_namespace:=rune_wire.duplicate(true)
	future_rune_namespace.extensions["hc.runes"]={"schema_version":2,"opaque_body":large}
	future_rune_namespace.base["corrupt_known_base"]=1
	var future_rune_contract:=rune_wire.duplicate(true)
	future_rune_contract.extensions["hc.runes"].runes[0].item.rune_instance_contract_id="hc.runes.fixture.rune.v2"
	future_rune_contract.base["corrupt_known_base"]=1
	var unknown_rune:=rune_wire.duplicate(true)
	unknown_rune.extensions["hc.runes"].runes[0].item.item_id=990999
	unknown_rune.base["corrupt_known_base"]=1
	var unknown_plain_rune:=rune.duplicate(true); unknown_plain_rune.item_id=990999
	candidates.append_array([future_rune_namespace,future_rune_contract,unknown_rune,unknown_plain_rune])
	for index in candidates.size():
		var candidate := candidates[index]
		check(Codec.decode_wire(candidate).status == Codec.OPAQUE_UNSUPPORTED,
			"unsupported owner precedes current graph or private-field rules " + str(index))
		_verify_profile(candidate, index)
		_verify_shared_item(candidate, known_shared, index)
	var known_large := wire.duplicate(true)
	known_large.extensions["hc.socketing"]["opaque_body"] = large
	var known_deep := wire.duplicate(true)
	known_deep.extensions["hc.socketing"]["opaque_body"] = deep
	check(Codec.decode_wire(known_large).status == Codec.INVALID
		and Codec.decode_wire(known_large).reason == "item_extension_graph_capacity_or_type",
		"known version still enforces its exact graph capacity")
	check(Codec.decode_wire(known_deep).status == Codec.INVALID
		and Codec.decode_wire(known_deep).reason == "item_extension_graph_capacity_or_type",
		"known version still enforces its exact depth capacity")
	var corrupt := wire.duplicate(true)
	corrupt.entity_id = 123
	check(Codec.decode_wire(corrupt).status == Codec.INVALID,
		"known malformed typed identity remains invalid")
	var future_warehouse := known_shared.duplicate(true)
	future_warehouse.schema_version = PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION + 1
	future_warehouse.warehouse_inventory = [corrupt]
	_verify_shared(future_warehouse, "future warehouse with corrupt known item")
	future_warehouse.schema_version = 1e20
	_verify_shared(future_warehouse, "future warehouse version outside int64 with corrupt known item")
	var mixed := known_shared.duplicate(true)
	mixed.schema_version = "malformed known sibling"
	mixed.warehouse_inventory = [corrupt, future_namespace]
	_verify_shared(mixed, "future item still owns aggregate with malformed warehouse schema")
	_verify_known_recovery(known_profile, known_shared, corrupt)
	_verify_legacy_equipment_clock_import(known_profile)
	PlayerState.test_mode = true
	_finish()

func _restore_known_profile() -> void:
	put(PlayerState.shared_warehouse_path, shared_bytes)
	put(profile_path, profile_bytes)
	put(profile_path + ".bak", profile_bytes)
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)),
		"independent case begins with real supported profile load")

func _verify_profile(candidate: Dictionary, index: int) -> void:
	_restore_known_profile()
	var document: Dictionary = JSON.parse_string(profile_bytes)
	document.inventory = [candidate]
	document.level = "corrupt known sibling"
	var raw := JSON.stringify(document, "\t") + "\n"
	put(profile_path, raw)
	PlayerState.gold = 4321
	var inventory_before := PlayerState.inventory.duplicate(true)
	var status: Dictionary = PlayerState._validate_profile_document_status(document, PlayerState.active_profile_id, false)
	check(not bool(status.valid) and bool(status.terminal),
		"future item locks whole profile before corrupt sibling " + str(index))
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)),
		"real loader rejects future profile with a valid old backup " + str(index))
	check(PlayerState.gold == 4321 and json_equal(PlayerState.inventory, inventory_before),
		"future profile never publishes backup or partial live state " + str(index))
	check(not PlayerState.save_game(false, false, false),
		"future profile prevents real writer after failed load " + str(index))
	check(FileAccess.get_file_as_string(profile_path) == raw
		and FileAccess.get_file_as_string(profile_path + ".bak") == profile_bytes,
		"future profile primary and backup remain byte identical " + str(index))

func _verify_shared_item(candidate: Dictionary, known_shared: Dictionary, index: int) -> void:
	var document := known_shared.duplicate(true)
	document.warehouse_inventory = [candidate]
	_verify_shared(document, "future shared item " + str(index))

func _verify_shared(document: Dictionary, label: String) -> void:
	var raw := JSON.stringify(document, "\t") + "\n"
	put(PlayerState.shared_warehouse_path, raw)
	put(PlayerState.shared_warehouse_path + ".bak", shared_bytes)
	# The live owner deliberately differs from the empty known backup.
	PlayerState.warehouse_inventory = [base.duplicate(true)]
	var inventory_before := PlayerState.warehouse_inventory.duplicate(true)
	PlayerState._shared_warehouse_initialized = false
	var status: Dictionary = PlayerState._validate_shared_warehouse_document_status(document)
	check(not bool(status.valid) and bool(status.terminal), label + " is terminal")
	check(not PlayerState._initialize_shared_warehouse(), label + " cannot initialize from old backup")
	check(json_equal(PlayerState.warehouse_inventory, inventory_before)
		and not PlayerState._shared_warehouse_initialized, label + " never publishes or initializes another owner")
	check(not PlayerState._write_shared_warehouse([]), label + " blocks the actual shared writer")
	check(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path) == raw
		and FileAccess.get_file_as_string(PlayerState.shared_warehouse_path + ".bak") == shared_bytes,
		label + " primary and backup remain byte identical")

func _verify_known_recovery(known_profile: Dictionary, known_shared: Dictionary, corrupt: Dictionary) -> void:
	_restore_known_profile()
	var document := known_profile.duplicate(true)
	document.inventory = [corrupt]
	var status: Dictionary = PlayerState._validate_profile_document_status(document, PlayerState.active_profile_id, false)
	check(not bool(status.valid) and not bool(status.terminal), "known profile corruption remains recoverable")
	put(profile_path, JSON.stringify(document))
	put(profile_path + ".bak", profile_bytes)
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false))
		and PlayerState.last_load_result.get("reason") == "recovered_from_backup",
		"known corrupt profile still uses actual backup recovery")
	check(json_equal(PlayerState.inventory, known_profile.inventory),
		"known profile recovery publishes the validated backup exactly")
	var shared := known_shared.duplicate(true)
	shared.warehouse_inventory = [corrupt]
	status = PlayerState._validate_shared_warehouse_document_status(shared)
	check(not bool(status.valid) and not bool(status.terminal), "known warehouse corruption remains recoverable")
	put(PlayerState.shared_warehouse_path, JSON.stringify(shared))
	put(PlayerState.shared_warehouse_path + ".bak", shared_bytes)
	PlayerState._shared_warehouse_initialized = false
	var recovered: Dictionary = PlayerState._read_json_with_status(PlayerState.shared_warehouse_path)
	check(bool(recovered.get("success", false)) and recovered.get("reason") == "recovered_from_backup",
		"known corrupt warehouse still uses actual backup recovery")
	check(PlayerState._initialize_shared_warehouse() and PlayerState.warehouse_inventory.is_empty(),
		"known warehouse recovery publishes the validated backup exactly")

func _verify_legacy_equipment_clock_import(known_profile: Dictionary) -> void:
	_restore_known_profile()
	var legacy := known_profile.duplicate(true)
	legacy.save_version = 7
	for field: String in ["item_identity", "equipment_identity", "death_event_sequence",
		"world_clock_generation", "world_clock_import_source"]:
		legacy.erase(field)
	legacy.equipment = {"武器": "木剑", "手镯": {"name": "铁手镯", "durability": 2, "max_durability": 4},
		"戒指": {"name": "古铜戒指", "durability": 3, "max_durability": 5}}
	var source := JSON.stringify(legacy, "\t") + "\n"
	put(profile_path, source)
	put(profile_path + ".bak", source)
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)),
		"actual world clock import accepts known legacy string equipment before formal runtime save")
	var archive_path := str(PlayerState.last_load_result.get("world_clock_migration_archive", ""))
	check(not archive_path.is_empty() and json_equal(
		JSON.parse_string(FileAccess.get_file_as_string(archive_path)), legacy),
		"world clock migration archive preserves all original legacy identity and equipment fields")
	check(not PlayerState.equipment["hc.slot.weapon"].is_empty()
		and PlayerState.equipment["hc.slot.weapon"].item_id == 80,
		"known legacy weapon receives its actual typed identity at the existing runtime import")
	check(PlayerState.equipment["hc.slot.bracelet_left"].get("durability_raw") == 2000
		and PlayerState.equipment["hc.slot.ring_left"].get("durability_raw") == 3000,
		"known legacy import retains exact worn durability and paired slot placement")
	check(PlayerState.save_game(false, false, false), "legitimate post-import save emits the formal item and slot owners")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	check(saved.has("item_identity") and saved.has("equipment_identity")
		and saved.equipment["hc.slot.weapon"] is Dictionary
		and saved.equipment["hc.slot.weapon"].item_id == 80,
		"formal disk writer never stores a name-only equipment owner")
	_restore_known_profile()
	var unknown := known_profile.duplicate(true)
	unknown.erase("item_identity")
	unknown.erase("equipment_identity")
	unknown.equipment = {"武器": "未登记的旧装备"}
	var raw := JSON.stringify(unknown, "\t") + "\n"
	put(profile_path, raw)
	var before := PlayerState.equipment.duplicate(true)
	var status: Dictionary = PlayerState._validate_profile_document_status(unknown, PlayerState.active_profile_id, false)
	check(not bool(status.valid) and bool(status.terminal), "unknown legacy string identity locks the entire aggregate")
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)) and PlayerState.equipment == before,
		"unknown legacy string publishes neither a guessed item nor the old backup")
	check(not PlayerState.save_game(false, false, false), "unknown legacy equipment locks the real profile writer")
	check(FileAccess.get_file_as_string(profile_path) == raw
		and FileAccess.get_file_as_string(profile_path + ".bak") == profile_bytes,
		"unknown legacy string preserves exact primary and backup bytes")

func _finish() -> void:
	if not proof.write_receipt("future_item_ownership_terminal_test", checks, failures.size()):
		failures.append("receipt")
	print("FRAMEWORK_FUTURE_ITEM_OWNERSHIP_%s checks=%d failures=%s" %
		["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
