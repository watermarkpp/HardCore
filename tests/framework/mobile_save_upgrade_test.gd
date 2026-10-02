extends Node

const State := preload("res://scripts/player_state.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const ClockLedger := preload("res://scripts/world_monster_clock_ledger.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func put(path: String, value: Variant) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK, "fixture directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture file")
	if file != null:
		file.store_string(value if value is String else JSON.stringify(value, "\t") + "\n")
		file.close()

func owner(root: String) -> Node:
	var state := State.new()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("character_profiles.json")
	state.shared_warehouse_path = root.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	state.begin_startup_save_upgrade()
	add_child(state)
	check(not state.test_mode, "upgrade uses real persistence, test_mode=false")
	return state

func root_for(label: String) -> String:
	return "user://mobile_upgrade_%s_%d" % [label, Time.get_ticks_usec()]

func legacy_profile(id: String) -> Dictionary:
	var gear := DropRules.create_instance(GameData.get_item_record({"item_id": 80}), id + ":original-weapon")
	gear["weapon_luck"] = 3
	return {"save_version": 7, "profile_id": id, "character_name": "升级验证",
		"profession": "战士", "gender": "男", "level": 25, "experience": 1234, "gold": 456789,
		"inventory": [], "equipment": {"武器": gear}, "learned_skills": {"基本剑术": 2},
		"quick_slots": ["", "", "", ""], "quest_states": {}, "warehouse_inventory": []}

func install_profile(root: String, id: String, document: Dictionary) -> String:
	var path := root.path_join("characters").path_join(id + ".json")
	put(path, document)
	return path

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not PlayerState.has_method("begin_startup_save_upgrade") or not PlayerState.has_method("finish_startup_save_upgrade"):
		check(false, "phone startup must expose a closed write gate and automatic upgrade")
		_finish()
		return
	_gate_backup_and_repeat()
	_future_aggregate_blocks_every_profile(11)
	_future_aggregate_blocks_every_profile(1.0e20)
	for kind: String in ["snapshot", "world_state", "world_schema", "death_event"]:
		_future_clock_blocks_upgrade(kind)
	_single_save_string_equipment()
	_archive_damage_stays_closed()
	_write_failure_can_resume()
	_empty_install()
	_real_v90_archive()
	_finish()

func _gate_backup_and_repeat() -> void:
	var root := root_for("two_profiles")
	var a := install_profile(root, "A", legacy_profile("A"))
	var b := install_profile(root, "B", legacy_profile("B"))
	put(root.path_join("character_profiles.json"), {"version": 1, "profiles": [{"id":"A"}, {"id":"B"}]})
	put(root.path_join("audio_preferences_v2.cfg"), "[audio]\nmaster=0.75\n")
	var before := {a:FileAccess.get_sha256(a), b:FileAccess.get_sha256(b)}
	var state := owner(root)
	check(not FileAccess.file_exists(state.shared_warehouse_path), "_ready cannot create warehouse before original backup")
	check(not state.select_character("A"), "profile selection blocked while upgrade pending")
	state._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(FileAccess.get_sha256(a) == before[a] and FileAccess.get_sha256(b) == before[b], "background notification preserves both primary bytes")
	check(state.finish_startup_save_upgrade(), "real multi-profile startup upgrade succeeds: " + str(state.startup_save_upgrade_result))
	var archive := root.path_join("save_upgrades/framework_identity_v1")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(archive.path_join("manifest.json"))) if FileAccess.file_exists(archive.path_join("manifest.json")) else {}
	check(manifest is Dictionary and manifest.get("files", {}).size() >= 4, "original aggregate manifest committed")
	for path: String in [a, b]:
		var rel := path.trim_prefix(root + "/")
		check(FileAccess.get_sha256(archive.path_join("original").path_join(rel)) == before[path], "immutable original SHA " + rel)
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(document.get("save_version") == 10 and document.get("character_identity", {}).get("profession_id") == "hc.profession.warrior", "profile and profession upgraded " + rel)
		check(document.get("skill_progression", {}).get("contract_id") == "skills.progression.hardcore.v3", "skill progression upgraded " + rel)
		check(document.get("skill_progression", {}).get("skills", {}).get("hc.skill.warrior.basic_swordsmanship", {}).get("base_rank") == 2, "learned skill rank retained " + rel)
		var gear: Dictionary = document.get("equipment", {}).get("hc.slot.weapon", {})
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(archive.path_join("original").path_join(rel)))
		check(gear.get("instance_id") == old.equipment["武器"].instance_id and gear.get("weapon_luck") == 3, "gear identity and luck retained " + rel)
		check(document.get("gold") == 456789 and document.get("experience") == 1234, "economic and progress values retained " + rel)
	check(FileAccess.file_exists(archive.path_join("completed.json")), "completion receipt durable before game admission")
	var shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.shared_warehouse_path))
	check(shared.get("item_identity", {}).get("contract_id") == "hardcore.item.identity.v1", "shared warehouse emitted through formal identity encoder")
	check(state.active_profile_id.is_empty(), "startup does not choose a player")
	var after := {a:FileAccess.get_sha256(a), b:FileAccess.get_sha256(b)}
	var archive_hash := FileAccess.get_sha256(archive.path_join("manifest.json"))
	state.begin_startup_save_upgrade()
	check(state.finish_startup_save_upgrade(), "completed upgrade reopens without repeating conversion")
	check(FileAccess.get_sha256(a) == after[a] and FileAccess.get_sha256(b) == after[b], "repeat startup changes no profile bytes")
	check(FileAccess.get_sha256(archive.path_join("manifest.json")) == archive_hash, "repeat never replaces original manifest")
	check(state.select_character("B") and state.gold == 456789, "normal selection and load after upgrade")
	var restart := {"root":root, "gold":456789, "experience":1234, "profiles":["A","B"], "manifest_sha256":archive_hash}
	put("user://mobile_upgrade_restart_case.json", restart)
	state.active_profile_id = ""
	state.queue_free()

func _single_save_string_equipment() -> void:
	var root := root_for("single_save")
	var old := legacy_profile("unused")
	old.erase("profile_id")
	old.equipment = {"武器":"木剑"}
	var path := root.path_join("player_save_v02.json")
	put(path, old)
	var original := FileAccess.get_sha256(path)
	var state := owner(root)
	check(state.finish_startup_save_upgrade(), "pre-profile old single save migrates automatically: " + str(state.startup_save_upgrade_result))
	check(state.list_characters().size() == 1 and state.select_character("legacy_01"), "single save becomes one real selectable profile")
	check(state.equipment.get("hc.slot.weapon", {}).get("item_id") == 80 and not state.equipment.get("hc.slot.weapon", {}).get("instance_id", "").is_empty(), "old string equipment uses exact registered owner and existing importer")
	check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/player_save_v02.json")) == original and FileAccess.get_sha256(path) == original, "legacy root and immutable backup retained")
	state.active_profile_id = ""
	state.queue_free()

func _archive_damage_stays_closed() -> void:
	var root := root_for("archive_damage")
	var path := install_profile(root, "A", legacy_profile("A"))
	put(root.path_join("character_profiles.json"), {"version":1, "profiles":[{"id":"A"}]})
	var state := owner(root)
	check(state.finish_startup_save_upgrade(), "archive damage control first completes")
	var current := FileAccess.get_sha256(path)
	put(root.path_join("save_upgrades/framework_identity_v1/original/characters/A.json"), "corrupted owned archive")
	state.begin_startup_save_upgrade()
	check(not state.finish_startup_save_upgrade() and state.startup_save_upgrade_result.get("reason") == "upgrade_backup_hash_mismatch", "damaged original backup fails closed even with completion receipt")
	check(FileAccess.get_sha256(path) == current and not state.select_character("A"), "damaged archive causes no profile writes or gameplay")
	state.queue_free()

func _future_aggregate_blocks_every_profile(version: Variant) -> void:
	var root := root_for("future")
	var a := install_profile(root, "A", legacy_profile("A"))
	var known := legacy_profile("B")
	var future := known.duplicate(true)
	future.save_version = version
	future.inventory = ["known malformed sibling"]
	var b := install_profile(root, "B", future)
	put(b + ".bak", known)
	put(root.path_join("character_profiles.json"), {"version":1, "profiles":[{"id":"A"},{"id":"B"}]})
	var ah := FileAccess.get_sha256(a)
	var bh := FileAccess.get_sha256(b)
	var state := owner(root)
	check(not state.finish_startup_save_upgrade(), "one future profile blocks whole account")
	check(FileAccess.get_sha256(a) == ah and FileAccess.get_sha256(b) == bh, "no partial migration or old-backup recovery on future owner")
	check(not FileAccess.file_exists(state.shared_warehouse_path), "future failure creates no account authority")
	check(not state.select_character("A"), "valid sibling still blocked")
	check(not FileAccess.file_exists(root.path_join("save_upgrades/framework_identity_v1/completed.json")), "future failure cannot claim completion")
	state.queue_free()

func _future_clock_blocks_upgrade(kind: String) -> void:
	var root := root_for("future_clock_" + kind)
	var document := legacy_profile("A")
	document["death_event_sequence"] = 0
	var path := install_profile(root, "A", document)
	put(root.path_join("character_profiles.json"), {"version":1, "profiles":[{"id":"A"}]})
	var state := owner(root)
	var clock_path: String = state._world_clock_path("A")
	var known := ClockLedger.snapshot_document("A", 0, WorldState.empty_snapshot())
	var future := known.duplicate(true)
	if kind == "snapshot": future.contract_id = "monster.world_clock.snapshot.v2"
	if kind == "world_state": future.world_state.contract_id = "monster.world_respawn_state.absolute_unix.v2"
	if kind == "world_schema": future.world_state.schema_version = 1.0e20
	if kind == "death_event":
		put(clock_path, known)
		clock_path = state._death_event_path("A", 1)
		known = ClockLedger.death_event_document("A", 1, 25, 1234, {}, WorldState.empty_snapshot())
		future = known.duplicate(true)
		future.contract_id = "monster.world_clock.death_event.v3"
	put(clock_path, future)
	put(clock_path + ".bak", known)
	var original_hash := FileAccess.get_sha256(clock_path)
	var profile_hash := FileAccess.get_sha256(path)
	check(not state.finish_startup_save_upgrade(), "future clock owner blocks upgrade " + kind)
	check(FileAccess.get_sha256(clock_path) == original_hash and FileAccess.get_sha256(path) == profile_hash, "future clock cannot recover old backup or partially rewrite profile " + kind)
	check(not state.select_character("A") and not FileAccess.file_exists(root.path_join("save_upgrades/framework_identity_v1/completed.json")), "future clock keeps admission and completion closed " + kind)
	state.queue_free()

func _write_failure_can_resume() -> void:
	var root := root_for("write_failure")
	var path := install_profile(root, "A", legacy_profile("A"))
	put(root.path_join("character_profiles.json"), {"version":1, "profiles":[{"id":"A"}]})
	var original_hash := FileAccess.get_sha256(path)
	var state := owner(root)
	# An owned directory occupying the writer's temp file makes actual I/O fail.
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK, "real write fault at profile promotion")
	check(not state.finish_startup_save_upgrade(), "actual storage failure blocks admission")
	var original := root.path_join("save_upgrades/framework_identity_v1/original/characters/A.json")
	check(FileAccess.get_sha256(original) == original_hash, "storage failure retains immutable old profile")
	check(not state.select_character("A"), "storage failure keeps gate closed")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp")) == OK, "remove precise owned fault directory")
	check(state.finish_startup_save_upgrade(), "retry resumes original upgrade after storage restored: " + str(state.startup_save_upgrade_result))
	check(FileAccess.get_sha256(original) == original_hash, "retry never replaces original archive")
	state.queue_free()

func _empty_install() -> void:
	var root := root_for("empty")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)) == OK, "empty root")
	var state := owner(root)
	check(state.finish_startup_save_upgrade(), "fresh install opens without a legacy profile")
	check(state.list_characters().is_empty(), "fresh install does not invent a character or reward")
	state.queue_free()

func _real_v90_archive() -> void:
	var source := "res://outputs/framework_v2/mobile_v90_reference"
	var fingerprint: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/framework_v2/mobile_v90_reference.json"))
	check(fingerprint is Dictionary and fingerprint.get("archive_sha256") == "18989f8b6d0f672b653cb0237ebeb33913f46885a508b716fe8c2b1ae5ffd7de", "real v90 device archive exact source identity")
	if not fingerprint is Dictionary: return
	var root := root_for("real_v90")
	for relative: String in fingerprint.files:
		var original := source.path_join(relative)
		check(FileAccess.get_sha256(original) == fingerprint.files[relative], "v90 source immutable " + relative)
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join(relative).get_base_dir())) == OK, "device fixture target")
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(original), ProjectSettings.globalize_path(root.path_join(relative))) == OK, "copy device archive into isolated user data")
	var state := owner(root)
	var diagnostic: Array = []
	for relative: String in fingerprint.files:
		if relative.begins_with("characters/") and relative.ends_with(".json"):
			var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(relative)))
			diagnostic.append({"path":relative, "validator":state._validate_profile_document_status(document, str(document.profile_id), false)})
			var records: Array = document.get("inventory", []).duplicate(true)
			for record: Variant in document.get("equipment", {}).values():
				if record is Dictionary: records.append(record)
			for record: Dictionary in records:
				if not record.is_empty() and GameData.item_entity_id(record).is_empty():
					diagnostic.append({"path":relative,"item_id":record.get("item_id"),"name":record.get("name"),"instance_id":record.get("instance_id"),"service_index":record.get("service_index")})
	var shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.shared_warehouse_path))
	diagnostic.append({"path":"shared_warehouse.json", "validator":state._validate_shared_warehouse_document_status(shared), "records_valid":state._validate_saved_item_records(shared.warehouse_inventory, 500)})
	for index in shared.warehouse_inventory.size():
		var record: Dictionary = shared.warehouse_inventory[index]
		if state._validated_persisted_instance_id(record) == "#invalid":
			diagnostic.append({"slot":index, "instance_id":record.get("instance_id"), "item_id":record.get("item_id"), "keys":record.keys()})
	print("MOBILE_V90_PREFLIGHT_DIAGNOSTIC " + JSON.stringify(diagnostic))
	check(state.finish_startup_save_upgrade(), "actual three-character v90 archive upgrades: " + str(state.startup_save_upgrade_result))
	check(state.list_characters().size() == 3, "real device three characters retained")
	var upgraded_shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.shared_warehouse_path))
	check(upgraded_shared.get("item_identity", {}).get("contract_id") == "hardcore.item.identity.v1", "existing v90 warehouse upgraded to formal identity")
	check(upgraded_shared.get("bank_gold") == shared.get("bank_gold") and upgraded_shared.get("bank_transaction_high_water") == shared.get("bank_transaction_high_water") and upgraded_shared.get("revision") == shared.get("revision"), "upgrade preserves bank balance, idempotency high-water and warehouse revision")
	check(upgraded_shared.get("bank_transactions") == shared.get("bank_transactions") and upgraded_shared.get("legacy_migration") == shared.get("legacy_migration"), "existing bank and warehouse migration journals preserved")
	check(_item_signature(upgraded_shared.warehouse_inventory) == _item_signature(shared.warehouse_inventory), "all real warehouse quantities, positions, instances and enhancements preserved")
	for relative: String in fingerprint.files:
		var archived := root.path_join("save_upgrades/framework_identity_v1/original").path_join(relative)
		check(FileAccess.get_sha256(archived) == fingerprint.files[relative], "real device original retained " + relative)
		if relative.begins_with("characters/") and relative.ends_with(".json"):
			var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(relative)))
			var migrated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(relative)))
			check(migrated.get("gold") == old.get("gold") and migrated.get("experience") == old.get("experience") and migrated.get("level") == old.get("level"), "device player progress retained")
			check(_item_signature(migrated.inventory) == _item_signature(old.inventory), "all real player inventory quantities, positions, instances and enhancements preserved")
			check(state.select_character(str(old.profile_id)), "device profile still loads after automatic conversion")
	state.active_profile_id = ""
	state.queue_free()

func _item_signature(records: Array) -> Dictionary:
	var signature := {}
	for index in records.size():
		var record: Variant = records[index]
		if record is Dictionary and not record.is_empty():
			var item := {"entity_id":GameData.item_entity_id(record), "instance_id":record.get("instance_id", ""), "count":record.get("count", 1)}
			for field: String in ["durability_raw", "max_durability_raw", "weapon_luck", "modifiers", "drop_affix", "enhancement"]:
				item[field] = record.get(field)
			signature[index] = item
	return signature

func _finish() -> void:
	if not proof.write_receipt("mobile_save_upgrade_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_MOBILE_SAVE_UPGRADE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
