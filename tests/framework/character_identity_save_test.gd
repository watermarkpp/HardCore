extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CONTRACT := "hardcore.character.identity.v1"
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: errors.append(label)
func identity(id: String) -> Dictionary:
	return {"contract_id": CONTRACT, "schema_version": 1, "profession_id": id}
func validate(document: Dictionary) -> Dictionary:
	return PlayerState._validate_profile_document_status(document, PlayerState.active_profile_id, false)
func put(path: String, bytes: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned isolated file opens " + path.get_file())
	if file != null:
		file.store_string(bytes)
		file.close()
func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var root := "user://framework_character_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.active_profile_id = "character-identity-save"
	PlayerState.character_name = "身份验收"
	PlayerState.set_profession_identity("hc.profession.wizard")
	var saved: Dictionary = PlayerState._prepare_character_save_payload(false).duplicate(true)
	check(not saved.is_empty(), "actual character writer produces a complete candidate")
	check(saved.get("character_identity", {}) == identity("hc.profession.wizard"), "actual writer stores formal versioned profession identity")
	check(bool(validate(saved).valid), "current complete candidate validates through the production validator")
	var legacy := saved.duplicate(true)
	legacy.erase("character_identity")
	for name: String in ["战士", "法师", "道士"]:
		legacy.profession = name
		check(bool(validate(legacy).valid), "exact legacy profession remains importable " + name)
	legacy.profession = "法师"
	var formal := legacy.duplicate(true)
	formal.character_identity = identity("hc.profession.wizard")
	check(bool(validate(formal).valid), "formal registered identity and matching display projection validate")
	var invalid: Array[Dictionary] = []
	var unknown_legacy := legacy.duplicate(true)
	unknown_legacy.profession = "未登记职业"
	invalid.append(unknown_legacy)
	for id: String in ["hc.profession.unknown", "hc.skill.wizard.lightning", "法师"]:
		var candidate := formal.duplicate(true)
		candidate.character_identity = identity(id)
		invalid.append(candidate)
	var conflict := formal.duplicate(true)
	conflict.profession = "战士"
	invalid.append(conflict)
	var future := formal.duplicate(true)
	future.character_identity.schema_version = 2
	invalid.append(future)
	var unexpected := formal.duplicate(true)
	unexpected.character_identity.name_fallback = "法师"
	invalid.append(unexpected)
	var malformed := formal.duplicate(true)
	malformed.character_identity.schema_version = "1"
	invalid.append(malformed)
	var bad_projection := formal.duplicate(true)
	bad_projection.profession = 123
	invalid.append(bad_projection)
	var unsupported_with_corruption := future.duplicate(true)
	unsupported_with_corruption.inventory = "malformed"
	invalid.append(unsupported_with_corruption)
	var wrong_contract := formal.duplicate(true)
	wrong_contract.character_identity.contract_id = "hardcore.character.identity.future"
	invalid.append(wrong_contract)
	var bad_contract_type := formal.duplicate(true)
	bad_contract_type.character_identity.contract_id = 123
	invalid.append(bad_contract_type)
	for index: int in range(invalid.size()):
		var result := validate(invalid[index])
		check(not bool(result.valid) and bool(result.terminal), "invalid identity is terminal before aggregate mutation %d" % index)
	check(not bool(PlayerState._validate_device_lab_save_document(conflict).ok), "device import refuses conflicting identity before writing")
	# A valid backup cannot authorize overwriting a newer unknown primary.
	# Drive the real loader, preserve exact raw bytes and the whole live state.
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var raw := JSON.stringify(unknown_legacy, "  ") + "\n"
	var backup := JSON.stringify(formal, "\t") + "\n"
	put(path, raw)
	put(path + ".bak", backup)
	PlayerState.level = 47
	PlayerState.gold = 1234
	PlayerState.quest_states = {"identity_guard_probe": {"state": "active"}}
	var inventory_before := PlayerState.inventory.duplicate(true)
	var equipment_before := PlayerState.equipment.duplicate(true)
	var quests_before := PlayerState.quest_states.duplicate(true)
	PlayerState.test_mode = false
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)), "real loader refuses unknown identity even with a valid backup")
	check(PlayerState.profession_id == "hc.profession.wizard" and PlayerState.level == 47 and PlayerState.gold == 1234 \
		and PlayerState.inventory == inventory_before and PlayerState.equipment == equipment_before and PlayerState.quest_states == quests_before,
		"failed identity load preserves the entire prior role aggregate")
	check(FileAccess.get_file_as_string(path) == raw and FileAccess.get_file_as_string(path + ".bak") == backup,
		"unknown primary and valid backup retain exact original bytes")
	check(PlayerState._prepare_character_save_payload(false).is_empty() and PlayerState.last_save_result.reason == "profile_save_blocked_after_invalid_load",
		"invalid aggregate is write locked rather than rewritten from live fallback state")
	check(FileAccess.get_file_as_string(path) == raw, "blocked save cannot replace unknown identity bytes")
	# A separately supplied valid aggregate can recover the owner. Old names
	# migrate once; new writes carry IDs without changing unrelated saved data.
	put(path, JSON.stringify(legacy))
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and PlayerState.profession_id == "hc.profession.wizard",
		"real legacy load imports exact known profession into its formal owner")
	check(PlayerState._prepare_character_save_payload(false).get("character_identity", {}) == identity("hc.profession.wizard"),
		"next actual save migrates the legacy role to formal identity")
	put(path, JSON.stringify(formal))
	PlayerState.set_profession_identity("hc.profession.warrior")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and PlayerState.profession_id == "hc.profession.wizard",
		"real formal load restores the ID owner without a name lookup")
	var snapshot: Dictionary = PlayerState._creation_runtime_snapshot()
	check(snapshot.character_identity == identity("hc.profession.wizard"), "rollback snapshot carries the same formal identity")
	var invalid_snapshot := snapshot.duplicate(true)
	invalid_snapshot.character_identity = identity("hc.profession.unknown")
	invalid_snapshot.gold = 98765
	PlayerState._restore_creation_runtime(invalid_snapshot)
	check(PlayerState.profession_id == "hc.profession.wizard" and PlayerState.gold == int(snapshot.gold),
		"invalid rollback identity cannot partially restore other fields")
	PlayerState.test_mode = true
	if not proof.write_receipt("character_identity_save_test", checks, errors.size()): errors.append("receipt")
	print("CHARACTER_IDENTITY_SAVE_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL", checks, str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
