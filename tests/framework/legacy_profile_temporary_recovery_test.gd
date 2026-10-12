extends Node

const State := preload("res://scripts/player_state.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const Diagnostic := preload("res://scripts/save_upgrade_diagnostic.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
const SKILLS := {"A":"hc.skill.warrior.basic_swordsmanship", "B":"hc.skill.wizard.fireball", "C":"hc.skill.taoist.healing"}
const WEAPON_SLOT := "hc.slot.weapon"

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value: failures.append(label)

func put(path: String, value: Variant) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK, "owned fixture directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned fixture file")
	if file == null: return
	file.store_string(value if value is String else JSON.stringify(value, "\t"))
	file.close()

func owner(root: String) -> Node:
	var state := State.new()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("character_profiles.json")
	state.shared_warehouse_path = root.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	state.begin_startup_save_upgrade()
	add_child(state)
	return state

func gear(identity: String, luck: int) -> Dictionary:
	var result := DropRules.create_instance(GameData.get_item_record({"item_id":80}), identity)
	result["weapon_luck"] = luck
	return result

func check_item(retained: Dictionary, original: Dictionary, label: String) -> void:
	# JSON has one number type. Compare both detached records after the same
	# production round trip, including every modifier, instead of contrasting
	# fixture ints with parsed floats inside nested Dictionary equality.
	var original_json: Dictionary = JSON.parse_string(JSON.stringify(original))
	var retained_json: Dictionary = JSON.parse_string(JSON.stringify(retained))
	var changed: Array[String] = []
	for key: String in original_json:
		if retained_json.get(key) != original_json[key]: changed.append(key)
	check(changed.is_empty(), label + ": original equipment fields retained " + str(changed))

func profile(id: String, profession: String, skill: String) -> Dictionary:
	return {"save_version":7, "profile_id":id, "character_name":"旧档" + id,
		"profession":profession, "gender":"男", "level":32, "experience":4321, "gold":876543,
		"inventory":[gear(id + ":bag", 2)], "equipment":{"武器":gear(id + ":equipped", 3)},
		"warehouse_inventory":[gear(id + ":warehouse", 4)], "learned_skills":{skill:2}, "quest_states":{}, "death_event_sequence":0}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	check(GameData.ensure_loaded(), "formal data authority ready")
	if OS.get_environment("HARDCORE_SAVE_RECOVERY_COLD_ONLY") == "1":
		_cold_preservation_case()
	else:
		_legacy_sidecar_case()
		_noncore_standardization_case()
		_skill_cache_standardization_case()
		_unknown_metadata_owner_case()
		_nested_pet_owner_case()
		_shared_warehouse_preservation_case()
		_writer_failure_detail_case()
	if not proof.write_receipt("legacy_profile_temporary_recovery_test", checks, failures.size()): failures.append("receipt")
	print("LEGACY_PROFILE_TEMPORARY_RECOVERY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _legacy_sidecar_case() -> void:
	var root := "user://legacy_tmp_%d" % Time.get_ticks_usec()
	var docs := {"A":profile("A", "战士", "基本剑术"), "B":profile("B", "法师", "火球术"), "C":profile("C", "道士", "治愈术")}
	for id: String in docs:
		put(root.path_join("characters/%s.json" % id), docs[id])
	put(root.path_join("character_profiles.json"), {"version":1,"profiles":[{"id":"A"},{"id":"B"},{"id":"C"}]})
	var stale_file := root.path_join("characters/B.json.tmp")
	put(stale_file, "unapproved interrupted old write; must remain preserved")
	var stale_directory_file := root.path_join("characters/C.json.tmp/interrupted.txt")
	put(stale_directory_file, "unapproved old temporary directory; must remain preserved")
	var stale_sha := FileAccess.get_sha256(stale_file)
	var directory_sha := FileAccess.get_sha256(stale_directory_file)
	var state := owner(root)
	var completed: bool = state.finish_startup_save_upgrade()
	check(completed, "legacy .json.tmp file and directory must not block conversion of three healthy roles: " + str(state.startup_save_upgrade_result))
	check(FileAccess.get_sha256(stale_file) == stale_sha and FileAccess.get_sha256(stale_directory_file) == directory_sha, "foreign temporary artifacts are never overwritten or deleted")
	var archive := root.path_join("save_upgrades/framework_identity_v1/original")
	check(FileAccess.get_sha256(archive.path_join("characters/B.json.tmp")) == stale_sha, "immutable before-image includes the interrupted file")
	check(FileAccess.get_sha256(archive.path_join("characters/C.json.tmp/interrupted.txt")) == directory_sha, "immutable before-image includes interrupted directory contents")
	if completed:
		for id: String in docs:
			check(state.select_character(id), "converted role loads " + id)
			check(state.level == 32 and state.experience == 4321 and state.gold == 876543, "level experience gold retained " + id)
			check(int(state.learned_skills.get(SKILLS[id], 0)) == 2, "learned skill level retained under registered stable ID " + id)
			check(state.inventory.size() > 0 and int(state.inventory[0].get("weapon_luck", -1)) == 2, "bag equipment attributes retained " + id)
			check(int(state.equipment.get(WEAPON_SLOT, {}).get("weapon_luck", -1)) == 3, "equipped attributes retained under registered stable slot " + id)
			check_item(state.inventory[0], docs[id].inventory[0], id + " bag")
			check_item(state.equipment.get(WEAPON_SLOT, {}), docs[id].equipment["武器"], id + " equipped")
			check(state.save_game(true, true, true), "subsequent real save still succeeds " + id)
		var warehouse_ids: Array[String] = []
		for record: Dictionary in state.warehouse_inventory:
			if int(record.get("item_id", -1)) == 80 and int(record.get("weapon_luck", -1)) == 4:
				warehouse_ids.append(str(record.get("instance_id", "")))
		check(warehouse_ids.size() == 3, "all three private warehouse equipment records migrate to shared warehouse")
		for id: String in docs:
			var original: Dictionary = docs[id].warehouse_inventory[0]
			var retained: Dictionary = {}
			for record: Dictionary in state.warehouse_inventory:
				if record.get("instance_id") == original.instance_id: retained = record
			check_item(retained, original, id + " warehouse")
		check(state.finish_startup_save_upgrade(), "completed standardization remains idempotent")
		put("res://outputs/test_logs/framework/legacy_standardization_cold_pointer.json", {
			"root":ProjectSettings.globalize_path(root), "originals":docs,
			"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"source_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	state.queue_free()

func _noncore_standardization_case() -> void:
	var root := "user://legacy_standardize_%d" % Time.get_ticks_usec()
	var latest := profile("D", "战士", "基本剑术")
	latest.quest_states = ["broken old quest cache"]
	latest.warrior_runtime_state = "broken derived toggle cache"
	var path := root.path_join("characters/D.json")
	put(path, latest)
	var older := profile("D", "战士", "基本剑术")
	older.level = 12
	older.gold = 100
	put(path + ".bak", older)
	put(root.path_join("character_profiles.json"), {"version":1,"profiles":[{"id":"D"}]})
	var original_sha := FileAccess.get_sha256(path)
	var state := owner(root)
	var completed: bool = state.finish_startup_save_upgrade()
	check(completed, "known malformed noncore caches standardize without falling back to older progress")
	check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/characters/D.json")) == original_sha, "full latest original survives standardization")
	if completed:
		check(state.select_character("D") and state.level == 32 and state.gold == 876543, "latest level and money win over older valid backup")
		check(state.quest_states is Dictionary and state.warrior_runtime_state is Dictionary, "noncore data uses registered current defaults")
		check(state.inventory.size() > 0 and state.warehouse_inventory.size() > 0 and not state.equipment.get(WEAPON_SLOT, {}).is_empty(), "bag warehouse and equipped items survive noncore standardization")
		check_item(state.inventory[0], latest.inventory[0], "standardized bag")
		check_item(state.equipment.get(WEAPON_SLOT, {}), latest.equipment["武器"], "standardized equipped")
		check_item(state.warehouse_inventory[0], latest.warehouse_inventory[0], "standardized warehouse")
		check(int(state.learned_skills.get(SKILLS.A, 0)) == 2, "noncore repair does not reset learned skills")
	state.queue_free()

func _writer_failure_detail_case() -> void:
	var projected := Diagnostic.build({"reason":"atomic_profile_write_failed", "phase":"migration", "source_backup_verified":true,
		"write_failure_reason":"candidate_business_invalid", "validation_reason":"invalid_level"})
	check(projected.get("reason_code") == "invalid_level", "public upgrade diagnostic identifies the actual candidate validation failure")
	var root := "user://legacy_atomic_reject_%d" % Time.get_ticks_usec()
	var state := owner(root)
	state._startup_save_upgrade_pending = false
	var path := root.path_join("characters/E.json")
	var healthy := profile("E", "战士", "基本剑术")
	put(path, healthy)
	var before := FileAccess.get_sha256(path)
	var invalid := healthy.duplicate(true)
	invalid.level = 0
	check(not state._write_json_atomic(path, invalid), "real writer rejects invalid candidate")
	var detail: Variant = state.get("_last_atomic_write_failure")
	check(detail is Dictionary and detail.get("reason", "") == "candidate_business_invalid" and detail.get("validation_reason", "") == "invalid_level", "formal writer failure is retained for the migration diagnostic")
	check(FileAccess.get_sha256(path) == before, "failed standardization cannot overwrite primary")
	state.queue_free()

func _skill_cache_standardization_case() -> void:
	for broken: Variant in ["broken progression", {"contract_id":"skills.progression.hardcore.v3", "skills":["broken derived entries"]}]:
		var root := "user://legacy_skill_cache_%d" % Time.get_ticks_usec()
		var latest := profile("F", "法师", "火球术")
		latest.skill_progression = broken
		var path := root.path_join("characters/F.json")
		put(path, latest)
		put(root.path_join("character_profiles.json"), {"version":1,"profiles":[{"id":"F"}]})
		var original_sha := FileAccess.get_sha256(path)
		var state := owner(root)
		var completed: bool = state.finish_startup_save_upgrade()
		check(completed, "known broken progression rebuilds from intact learned skills " + str(broken))
		check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/characters/F.json")) == original_sha, "broken skill cache keeps the complete original")
		if completed:
			check(state.select_character("F") and int(state.learned_skills.get(SKILLS.B, 0)) == 2, "rebuilt progression preserves wizard skill rank")
			check(state.level == 32 and state.experience == 4321 and state.gold == 876543, "rebuilt skill cache preserves core progress")
			check_item(state.inventory[0], latest.inventory[0], "skill repair bag")
			check_item(state.equipment.get(WEAPON_SLOT, {}), latest.equipment["武器"], "skill repair equipped")
			check_item(state.warehouse_inventory[0], latest.warehouse_inventory[0], "skill repair warehouse")
			check(state.save_game(true, true, true), "repaired wizard can save through the real writer")
		state.queue_free()

func _nested_pet_owner_case() -> void:
	var state := owner("user://legacy_nested_owner_%d" % Time.get_ticks_usec())
	for containers: Dictionary in [
		{"groups":{"skeleton":[{"contract_id":"future.pet.v999"}]}},
		{"slots":{"divine_beast":{"contract_id":"future.pet.v999"}}}]:
		var latest := profile("H", "道士", "治愈术")
		latest.taoist_main_pet_runtime_states = containers.duplicate(true)
		latest.taoist_main_pet_runtime_states.contract_id = State.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID
		var status: Dictionary = state._validate_profile_document_status(latest, "H", false)
		check(not status.valid and status.get("terminal", false) and status.reason == "unsupported_taoist_main_pet_runtime_states_contract", "unknown nested pet owner is rejected before normalization " + str(containers))
	state.queue_free()

func _shared_warehouse_preservation_case() -> void:
	var root := "user://legacy_existing_shared_%d" % Time.get_ticks_usec()
	var latest := profile("I", "战士", "基本剑术")
	latest.quest_states = "broken noncore"
	# A completed shared ledger already retired the private warehouse field.
	# The separate three-role case covers the actual pre-merge legacy format.
	latest.erase("warehouse_inventory")
	put(root.path_join("characters/I.json"), latest)
	put(root.path_join("character_profiles.json"), {"version":1,"profiles":[{"id":"I"}]})
	var warehouse: Array = []
	for slot in 120: warehouse.append({})
	var existing := gear("existing:shared:119", 7)
	warehouse[119] = existing
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	var broken_badge := RelicRules.roll_instance(950202, "法师", rng)
	broken_badge.instance_id = "shared:broken:badge"
	broken_badge.modifiers = []
	warehouse[6] = broken_badge
	put(root.path_join("shared_warehouse.json"), {"schema_version":1, "contract_id":State.SHARED_WAREHOUSE_CONTRACT_ID,
		"warehouse_inventory":warehouse, "legacy_migration":{"contract_id":State.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "completed":true, "sources":{}}})
	var state := owner(root)
	var completed: bool = state.finish_startup_save_upgrade()
	check(completed, "standardization accepts an existing shared warehouse: " + str(state.startup_save_upgrade_result))
	if completed:
		check(state.select_character("I") and state.warehouse_inventory.size() >= 120, "shared warehouse page and slot positions survive")
		check_item(state.warehouse_inventory[119], existing, "existing shared warehouse slot 119")
		check(state.warehouse_inventory[6].is_empty(), "known bad shared badge is removed after profile cache repair")
		check_item(state.inventory[0], latest.inventory[0], "existing shared account backpack")
		check_item(state.equipment.get(WEAPON_SLOT, {}), latest.equipment["武器"], "existing shared account equipped")
	state.queue_free()

func _cold_preservation_case() -> void:
	var pointer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/legacy_standardization_cold_pointer.json"))
	check(pointer is Dictionary and pointer.get("source_sha256") == OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "cold process uses the identical tested source")
	if not pointer is Dictionary: return
	var producer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/legacy_profile_temporary_recovery_test.result.json"))
	check(producer is Dictionary and producer.get("status") == "PASS" and producer.get("run_id") == pointer.producer_run_id, "cold data links to a passing producer process")
	var state := owner(str(pointer.root))
	check(state.finish_startup_save_upgrade(), "separate native process accepts the completed account")
	for id: String in pointer.originals:
		var original: Dictionary = pointer.originals[id]
		check(state.select_character(id) and state.level == 32 and state.gold == 876543 and state.experience == 4321, "cold core progress retained " + id)
		check(int(state.learned_skills.get(SKILLS[id], 0)) == 2, "cold skill rank retained " + id)
		check_item(state.inventory[0], original.inventory[0], "cold bag " + id)
		check_item(state.equipment.get(WEAPON_SLOT, {}), original.equipment["武器"], "cold equipped " + id)
		var found := false
		for record: Dictionary in state.warehouse_inventory:
			if record.get("instance_id") == original.warehouse_inventory[0].instance_id:
				check_item(record, original.warehouse_inventory[0], "cold warehouse " + id)
				found = true
		check(found, "cold warehouse identity retained " + id)
		check(state.save_game(true, true, true), "cold role remains writable " + id)
	state.queue_free()

func _unknown_metadata_owner_case() -> void:
	for field: String in ["skill_progression", "warrior_runtime_state", "taoist_main_pet_runtime_state", "taoist_main_pet_runtime_states"]:
		var root := "user://legacy_unknown_metadata_%d" % Time.get_ticks_usec()
		var latest := profile("G", "战士", "基本剑术")
		latest[field] = {"contract_id":"unknown.future.metadata.v999", "payload":{"do_not_discard":true}}
		var path := root.path_join("characters/G.json")
		put(path, latest)
		put(root.path_join("character_profiles.json"), {"version":1,"profiles":[{"id":"G"}]})
		var before := FileAccess.get_sha256(path)
		var state := owner(root)
		check(not state.finish_startup_save_upgrade(), "unknown explicit metadata owner is blocked " + field)
		check(FileAccess.get_sha256(path) == before, "unknown metadata never rewrites primary " + field)
		state.queue_free()
