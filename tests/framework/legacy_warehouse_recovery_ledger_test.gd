extends Node

const State := preload("res://scripts/player_state.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const SaveUpgradeBackup := preload("res://scripts/save_upgrade_backup.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

const SCENE_ID := "legacy_warehouse_recovery_ledger_test"
const WEAPON_SLOT := "hc.slot.weapon"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:

	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func put(path: String, value: Variant) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK, "fixture directory exists")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture file opens")
	if file == null:
		return
	file.store_string(value if value is String else JSON.stringify(value, "\t"))
	file.close()

func gear(instance_id: String, luck: int) -> Dictionary:
	var item := DropRules.create_instance(GameData.get_item_record({"item_id": 80}), instance_id)
	item["weapon_luck"] = luck
	return item

func check_item(retained: Dictionary, original: Dictionary, label: String) -> void:
	var expected_value: Variant = JSON.parse_string(JSON.stringify(original))
	var actual_value: Variant = JSON.parse_string(JSON.stringify(retained))
	var expected: Dictionary = expected_value if expected_value is Dictionary else {}
	var actual: Dictionary = actual_value if actual_value is Dictionary else {}
	var changed: Array[String] = []
	for key: String in expected:
		if actual.get(key) != expected[key]:
			changed.append(key)
	check(changed.is_empty(), label + " changed=" + str(changed))

func bad_badge(instance_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	var item := RelicRules.roll_instance(950202, "法师", rng)
	item["instance_id"] = instance_id
	item["modifiers"] = []
	return item

func profile() -> Dictionary:
	return {
		"save_version": 7, "profile_id": "A", "character_name": "旧法师",
		"profession": "法师", "gender": "男", "level": 42,
		"experience": 9876, "gold": 765432, "inventory": [gear("bag:A", 2)],
		"equipment": {WEAPON_SLOT: gear("equipped:A", 3)},
		"warehouse_inventory": [gear("private:gear", 4), bad_badge("private:badge")],
		"learned_skills": {"hc.skill.wizard.fireball": 2}, "quest_states": {},
		"death_event_sequence": 0,
	}

func owner(root: String) -> State:
	var state := State.new()
	state.test_mode = true
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("character_profiles.json")
	state.shared_warehouse_path = root.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	state.begin_startup_save_upgrade()
	add_child(state)
	return state

func shared_document(state: State, private_records: Array) -> Dictionary:
	var warehouse: Array = []
	for index in 120:
		warehouse.append({})
	warehouse[6] = (private_records[1] as Dictionary).duplicate(true)
	warehouse[119] = (private_records[0] as Dictionary).duplicate(true)
	warehouse[118] = gear("shared:extra", 7)
	return {
		"schema_version": 1, "contract_id": State.SHARED_WAREHOUSE_CONTRACT_ID,
		"warehouse_inventory": warehouse,
		"legacy_migration": {
			"contract_id": State.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
			"completed": true,
			"sources": {"A": {"digest": state._shared_digest(state._occupied_records(private_records)),
				"occupied_count": 2, "complete": true,
				"contract_id": State.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID}},
		},
	}

func seed_account(root: String, with_digest_mismatch := false, future_ledger := false) -> Dictionary:
	var latest := profile()
	var private_records: Array = latest.warehouse_inventory
	put(root.path_join("characters/A.json"), latest)
	put(root.path_join("character_profiles.json"), {"version": 1, "profiles": [{"id": "A"}]})
	var state := owner(root)
	var shared := shared_document(state, private_records)
	if with_digest_mismatch:
		shared.legacy_migration.sources.A.digest = "mismatch"
	if future_ledger:
		shared.legacy_migration.contract_id = "shared.future.v999"
	put(root.path_join("shared_warehouse.json"), shared)
	return {"state": state, "latest": latest, "private_sha": FileAccess.get_sha256(root.path_join("characters/A.json")),
		"shared_sha": FileAccess.get_sha256(root.path_join("shared_warehouse.json"))}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(GameData.ensure_loaded(), "formal data authority ready")
	_recovery_case()
	_partial_profile_restart_case()
	_reject_case(true, false, "legacy ledger digest mismatch rejects without write")
	_reject_case(false, true, "future legacy ledger owner rejects without write")
	if not proof.write_receipt(SCENE_ID, checks, failures.size()):
		failures.append("receipt")
	print("LEGACY_WAREHOUSE_RECOVERY_LEDGER_%s checks=%d failures=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _recovery_case() -> void:
	var root := "user://legacy_warehouse_recovery_%d" % Time.get_ticks_usec()
	var seeded := seed_account(root)
	var state: State = seeded.state as State
	var backup := SaveUpgradeBackup.new()
	check(backup.prepare(root, state._startup_upgrade_sources()),
		"joint recovery creates immutable custody before candidate preflight")
	var preflight: Dictionary = state._startup_upgrade_preflight()
	var candidate_profile: Dictionary = {}
	for recovery: Dictionary in preflight.get("relic_recoveries", []):
		if str(recovery.get("profile_id", "")) == "A":
			var candidate_value: Variant = recovery.get("data", {})
			candidate_profile = candidate_value if candidate_value is Dictionary else {}
	var candidate_private: Array = candidate_profile.get("warehouse_inventory", [])
	check(candidate_private.size() == 2 and candidate_private[1].is_empty(),
		"preflight profile candidate clears only the damaged private badge slot")
	var completed: bool = state.finish_startup_save_upgrade()
	check(completed, "profile and shared warehouse recovery promotes as one startup upgrade: " + str(state.startup_save_upgrade_result))
	var profile_path := root.path_join("characters/A.json")
	var shared_path := root.path_join("shared_warehouse.json")
	var archive_root := root.path_join("save_upgrades/framework_identity_v1/original")
	check(FileAccess.get_sha256(archive_root.path_join("characters/A.json")) == seeded.private_sha,
		"immutable archive retains the complete private warehouse before-image")
	check(FileAccess.get_sha256(archive_root.path_join("shared_warehouse.json")) == seeded.shared_sha,
		"immutable archive retains the complete shared warehouse before-image")
	if completed:
		check(state.select_character("A") and state.level == 42 and state.gold == 765432,
			"level and gold survive private warehouse recovery")
		check(int(state.learned_skills.get("hc.skill.wizard.fireball", 0)) == 2,
			"learned skill survives private warehouse recovery")
		check(int(state.equipment.get(WEAPON_SLOT, {}).get("weapon_luck", -1)) == 3,
			"equipped item attributes survive private warehouse recovery")
		var repaired_shared_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(shared_path))
		var repaired_shared: Dictionary = repaired_shared_value if repaired_shared_value is Dictionary else {}
		var shared_records: Array = repaired_shared.get("warehouse_inventory", [])
		check(shared_records.size() == 120 and shared_records[6].is_empty()
			and int(shared_records[119].get("weapon_luck", -1)) == 4
			and int(shared_records[118].get("weapon_luck", -1)) == 7,
			"only the damaged shared badge is cleared and slots 119/118 retain complete gear")
		var occupied := state._occupied_records(candidate_private)
		check(repaired_shared.legacy_migration.sources.A.digest == state._shared_digest(occupied)
			and int(repaired_shared.legacy_migration.sources.A.occupied_count) == occupied.size(),
			"legacy private warehouse ledger digest and count follow the repaired profile")
	else:
		check(FileAccess.get_sha256(profile_path) == seeded.private_sha and FileAccess.get_sha256(shared_path) == seeded.shared_sha,
			"failed red candidate preserves both primaries")
	state.queue_free()

func _reject_case(digest_mismatch: bool, future_ledger: bool, label: String) -> void:
	var root := "user://legacy_warehouse_reject_%d" % Time.get_ticks_usec()
	var seeded := seed_account(root, digest_mismatch, future_ledger)
	var state: State = seeded.state as State
	var completed: bool = state.finish_startup_save_upgrade()
	check(not completed, label)
	check(FileAccess.get_sha256(root.path_join("characters/A.json")) == seeded.private_sha
		and FileAccess.get_sha256(root.path_join("shared_warehouse.json")) == seeded.shared_sha,
		label + ": no primary is rewritten")
	state.queue_free()

func _partial_profile_restart_case() -> void:
	var root := "user://legacy_warehouse_recovery_restart_%d" % Time.get_ticks_usec()
	var seeded := seed_account(root)
	var state: State = seeded.state as State
	var latest_value: Variant = seeded.get("latest", {})
	var latest: Dictionary = latest_value if latest_value is Dictionary else {}
	var backup := SaveUpgradeBackup.new()
	check(backup.prepare(root, state._startup_upgrade_sources()),
		"partial recovery creates the immutable account before-image")
	var preflight: Dictionary = state._startup_upgrade_preflight()
	var recoveries: Array = preflight.get("relic_recoveries", [])
	var profile_recoveries: Array = []
	for recovery: Dictionary in recoveries:
		if str(recovery.get("profile_id", "")) == "A":
			profile_recoveries.append(recovery)
	check(profile_recoveries.size() == 1 and recoveries.size() == 2
		and str(recoveries[recoveries.size() - 1].get("profile_id", "")) == "",
		"preflight orders profile recovery before shared recovery")
	if profile_recoveries.size() == 1:
		state._startup_save_upgrade_in_progress = true
		state._startup_source_backup_verified = true
		var partial: Dictionary = state._startup_apply_relic_recoveries(profile_recoveries, backup)
		check(bool(partial.success), "profile-only recovery can be formally promoted at the checkpoint")
	else:
		check(false, "profile-only recovery candidate exists at the checkpoint")
	var profile_path := root.path_join("characters/A.json")
	var shared_path := root.path_join("shared_warehouse.json")
	var profile_after_partial := FileAccess.get_sha256(profile_path)
	var shared_before_restart := FileAccess.get_sha256(shared_path)
	var current_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	var current: Dictionary = current_value if current_value is Dictionary else {}
	current["level"] = 43
	current["gold"] = 765999
	state._startup_save_upgrade_in_progress = true
	check(state._write_json_atomic(profile_path, current, true),
		"checkpoint keeps a formally written newer level and gold on the repaired profile")
	state.queue_free()
	var restarted: State = owner(root) as State
	var completed: bool = restarted.finish_startup_save_upgrade()
	check(completed, "new startup resumes from immutable archive after profile-only promotion")
	check(FileAccess.get_sha256(profile_path) != profile_after_partial
		and FileAccess.get_sha256(shared_path) != shared_before_restart,
		"restart keeps the newer repaired profile and promotes the ledger-linked shared candidate")
	if completed:
		check(restarted.select_character("A") and restarted.level == 43 and restarted.gold == 765999,
			"restart preserves the newer level and gold instead of reverting to the archive")
		check(int(restarted.learned_skills.get("hc.skill.wizard.fireball", 0)) == 2,
			"restart preserves the original learned skill rank")
		check_item(restarted.inventory[0], latest.inventory[0], "restart preserves complete bag item")
		check_item(restarted.equipment.get(WEAPON_SLOT, {}), latest.equipment[WEAPON_SLOT],
			"restart preserves complete worn item")
		var final_shared_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(shared_path))
		var original_shared_value: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(root.path_join("save_upgrades/framework_identity_v1/original/shared_warehouse.json")))
		var final_shared: Dictionary = final_shared_value if final_shared_value is Dictionary else {}
		var original_shared: Dictionary = original_shared_value if original_shared_value is Dictionary else {}
		var final_records: Array = final_shared.get("warehouse_inventory", [])
		var original_records: Array = original_shared.get("warehouse_inventory", [])
		check_item(final_records[119], original_records[119], "restart preserves complete shared slot 119 item")
		check_item(final_records[118], original_records[118], "restart preserves complete independent shared slot 118 item")
	check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/characters/A.json")) == seeded.private_sha
		and FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/shared_warehouse.json")) == seeded.shared_sha,
		"restart retains both immutable original before-image hashes")
	restarted.queue_free()
