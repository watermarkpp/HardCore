extends Node

## Real profile admission failure. All authorities use the runner's independent
## user root. A directory at the exact clock TMP rejects the formal writer.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
const ItemCodec := preload("res://scripts/items/item_extension_codec.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const SCENE_ID := "profile_load_admission_20261010_test"
const EVIDENCE_ROOT := "res://outputs/b08_profile_admission_test_20261010/runs"
const QUEST_ID := "bich_beginner_gear"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var trace: Dictionary = {}
var owned_root := ""
var blocker_path := ""
var blocker_marker := ""
var blocker_owned := false
var signals_connected := false
var signal_counts := {"database": 0, "expansion": 0, "profile": 0}
var started_usec := 0


func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	print("PROFILE_ADMISSION_CHECK %d %s %s elapsed_usec=%d" % [
		checks, "PASS" if value else "FAIL", label, Time.get_ticks_usec() - started_usec])
	if not value:
		failures.append(label)


func _ready() -> void:
	started_usec = Time.get_ticks_usec()
	_run.call_deferred()


func _owned(path: String) -> bool:
	if owned_root.is_empty():
		return false
	var root := ProjectSettings.globalize_path(owned_root).replace("\\", "/").simplify_path().to_lower()
	var target := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower()
	return target.begins_with(root + "/")


func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func _wire_equal(left: Variant, right: Variant) -> bool:
	# JSON numbers share the float wire domain after reading. Compare complete
	# quest values there; never drop fields or relax the expected progress.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _catalog_references() -> Dictionary:
	var result := {}
	for field: String in GameData.DATABASE_STATE_FIELDS:
		result[field] = GameData.get(field)
	return result


func _catalog_differences(before: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for field: String in before:
		var current: Variant = GameData.get(field)
		var previous: Variant = before[field]
		var unchanged := is_same(current, previous) if previous is Dictionary or previous is Array else current == previous
		if not unchanged:
			result.append(field)
	return result


func _state_differences(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key: String in before:
		if not after.has(key) or before[key] != after[key]:
			result[key] = {"expected": before[key], "recovered": after.get(key)}
	return result


func _files(paths: Array[String]) -> Dictionary:
	var result := {}
	for path: String in paths:
		result[path] = {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}
	return result


func _file_hashes(snapshot: Dictionary) -> Dictionary:
	var result := {}
	for path: String in snapshot:
		var bytes: PackedByteArray = snapshot[path].bytes
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(bytes)
		result[path] = {"exists": snapshot[path].exists, "size": bytes.size(), "sha256": context.finish().hex_encode()}
	return result


func _writer_identity_negatives(a_id: String) -> void:
	var clock_path: String = PlayerState._world_clock_path(a_id, "")
	var wrong_path := clock_path + ".wrong-target"
	var document := _read(clock_path)
	check(_owned(clock_path) and _owned(wrong_path) and PlayerState._world_clock_generation.is_empty()
		and not PlayerState._startup_save_upgrade_pending
		and ItemCodec.decode_document(document).status == ItemCodec.KNOWN_VALID
		and Ledger.valid_snapshot(document, a_id, ""),
		"writer identity negatives retain a real valid owned A empty-generation snapshot")
	if not failures.is_empty():
		return
	var paths: Array[String] = [clock_path, clock_path + ".bak", clock_path + ".tmp", wrong_path, wrong_path + ".tmp"]
	var original := _files(paths)
	var world_completed: int = PlayerState._world_json_persistence.completed_count
	var profile_completed: int = PlayerState._json_persistence.completed_count
	var cases := [
		{"label": "missing generation plus extra key", "path": clock_path, "identity": {"profile_id": a_id, "extra": true}},
		{"label": "more than two identity keys", "path": clock_path, "identity": {"profile_id": a_id, "generation": "", "extra": true}},
		{"label": "non-String generation", "path": clock_path, "identity": {"profile_id": a_id, "generation": 0}},
		{"label": "wrong target path", "path": wrong_path, "identity": {"profile_id": a_id, "generation": ""}},
	]
	var outcomes: Array[Dictionary] = []
	for entry: Dictionary in cases:
		var result: bool = PlayerState._write_json_atomic(entry.path, document, true, entry.identity)
		var unchanged := _files(paths) == original
		var world_after: int = PlayerState._world_json_persistence.completed_count
		var profile_after: int = PlayerState._json_persistence.completed_count
		check(not result and world_after == world_completed and profile_after == profile_completed
			and PlayerState._world_json_persistence.pending_count() == 0
			and PlayerState._json_persistence.pending_count() == 0 and unchanged,
			"formal writer rejects %s before submission and preserves A snapshot bytes" % entry.label)
		outcomes.append({"case": entry.label, "result": result, "world_completed": world_after,
			"profile_completed": profile_after, "bytes_unchanged": unchanged})
	trace["writer_identity_negatives"] = {"cases": outcomes,
		"world_completed_before": world_completed, "profile_completed_before": profile_completed,
		"bytes_before": _file_hashes(original), "bytes_after": _file_hashes(_files(paths))}


func _player_snapshot() -> Dictionary:
	return {
		"id": PlayerState.active_profile_id, "name": PlayerState.character_name,
		"level": PlayerState.level, "profession_id": PlayerState.profession_id,
		"gender": PlayerState.gender, "experience": PlayerState.experience,
		"gold": PlayerState.gold, "overflow": PlayerState.gold_overflow_records.duplicate(true),
		"mode": PlayerState.game_mode_id, "later": PlayerState.later_content_enabled,
		"inventory": PlayerState.inventory.duplicate(true), "equipment": PlayerState.equipment.duplicate(true),
		"warehouse": PlayerState.warehouse_inventory.duplicate(true),
		"forge": PlayerState.forge_tray.duplicate(true), "synthesis": PlayerState.synthesis_tray.duplicate(true),
		"skills": PlayerState.skill_progression_snapshot(), "learned": PlayerState.learned_skills.duplicate(true),
		"skill_buttons": PlayerState.skill_button_assignments_snapshot(), "item_slots": PlayerState.quick_item_slots.duplicate(),
		"quests": PlayerState.quest_states.duplicate(true), "pets": PlayerState.taoist_main_pet_runtime_states.duplicate(true),
		"world": PlayerState.world_monster_respawn_state.duplicate(true),
		"sequence": PlayerState._death_event_sequence, "generation": PlayerState._world_clock_generation,
		"world_snapshot": PlayerState._world_clock_snapshot_sequence, "world_backup": PlayerState._world_clock_backup_sequence,
		"profile_snapshot": PlayerState._profile_saved_death_event_sequence, "profile_backup": PlayerState._profile_backup_death_event_sequence,
		"world_dirty": PlayerState._world_clock_dirty, "world_changes": PlayerState._world_clock_changes.duplicate(true),
		"base_stats": PlayerState.base_stats.duplicate(true), "stats": PlayerState.computed_stats.duplicate(true),
		"durability_pending": PlayerState._durability_save_pending, "durability_elapsed": PlayerState._durability_save_elapsed,
		"durability_visual": PlayerState._durability_visual_pending, "durability_visual_elapsed": PlayerState._durability_visual_elapsed,
		"legacy_warehouse_pending": PlayerState._active_profile_legacy_warehouse_pending,
	}


func _on_database() -> void:
	signal_counts.database += 1


func _on_expansion(_id: String, _enabled: bool) -> void:
	signal_counts.expansion += 1


func _on_profile() -> void:
	signal_counts.profile += 1


func _run() -> void:
	var run_id := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	var invocation_id := OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	trace = {"run_id": run_id, "invocation_id": invocation_id,
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"user_data_directory": OS.get_user_data_dir(), "native_process_id": OS.get_process_id(),
		"scope": "formal test_mode=false profile admission; real ledger watermark and exact clock TMP directory fault"}
	check(user_root.contains("/.godot/runtime_appdata/") and not run_id.is_empty() and not invocation_id.is_empty()
		and run_id.is_valid_filename() and invocation_id.is_valid_filename(),
		"runner isolates the complete real account before process launch")
	if not failures.is_empty():
		_finish()
		return
	owned_root = "user://profile_load_admission_20261010_" + run_id + "_" + invocation_id + "_" + str(OS.get_process_id())
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(owned_root)) and not FileAccess.file_exists(owned_root),
		"this run's account root is absent before claiming ownership")
	if not failures.is_empty():
		owned_root = ""
		_finish()
		return
	check(ContentLayers.ensure_loaded() and GameData.ensure_loaded() and GameModes.ensure_initial_mode(),
		"formal content, database and initial mode finish their readiness gates")
	if not failures.is_empty():
		_finish()
		return
	PlayerState._before_state_transaction(true)
	PlayerState.set_process(false)
	PlayerState.test_mode = false
	PlayerState.profile_directory = owned_root.path_join("characters")
	PlayerState.profile_index_path = owned_root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = owned_root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = owned_root.path_join("shared_warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = ""
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""
	PlayerState._validated_profile_path = ""
	PlayerState._validated_profile_bytes = PackedByteArray()
	check(PlayerState._shared_warehouse_test_isolation_enabled() and not PlayerState.test_mode,
		"profile, account warehouse and transaction log all use the owned real persistence root")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,
		"owned account profile directory is created")
	check(GameModes.apply_mode("classic_176", false), "A baseline uses the formal classic mode owner")
	check(PlayerState.create_character("AdmissionA", "hc.profession.warrior", "男").is_empty(),
		"formal owner creates real character A")
	if not failures.is_empty():
		_finish()
		return
	var a_id: String = PlayerState.active_profile_id
	trace["a_id"] = a_id
	PlayerState.level = 9
	PlayerState.experience = 1
	PlayerState.gold = 1234
	check(bool(PlayerState.add_item("基本剑术", 1).get("success", false)), "A acquires a real registered skill book")
	check(PlayerState.learn_skill("基本剑术").begins_with("已学会"), "A learns through the sole skill and book consumption owner")
	check(PlayerState.save_game(true, true, true), "formal writer persists complete A and its checkpoint")
	check(PlayerState.create_character("AdmissionB", "hc.profession.wizard", "女").is_empty(),
		"formal owner creates real character B")
	if not failures.is_empty():
		_finish()
		return
	var b_id: String = PlayerState.active_profile_id
	trace["b_id"] = b_id
	var b_path: String = PlayerState._profile_path(b_id)
	# Represent one supported old clock header, then use the existing importer
	# to obtain a real fresh generation; no second clock or profile writer.
	var legacy := _read(b_path)
	legacy.erase("death_event_sequence")
	legacy.erase("world_clock_generation")
	legacy["world_monster_respawn_state"] = WorldState.empty_snapshot()
	check(PlayerState._write_json_atomic(b_path, legacy, true), "sole writer stages the owned supported legacy clock input")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and not PlayerState._world_clock_generation.is_empty(),
		"formal clock importer creates B's isolated generation")
	if not failures.is_empty():
		_finish()
		return
	PlayerState.level = 11
	PlayerState.experience = 2
	PlayerState.gold = 5678
	check(bool(PlayerState.add_item("火球术", 1).get("success", false)), "B acquires its own real registered skill book")
	check(PlayerState.learn_skill("火球术").begins_with("已学会"), "B learns a different skill through the same formal owner")
	check(PlayerState.accept_quest(QUEST_ID).begins_with("已接受任务"), "B accepts the actual prerequisite-free registered quest")
	var settlement: Dictionary = PlayerState.record_kill_and_experience("稻草人", 1)
	check(bool(settlement.get("success", false)) and int(settlement.get("save_count", 0)) == 1,
		"real ledger settlement records one kill and one durable death event")
	# These fixture fields describe the target saved configuration. Admission
	# itself must prepare it through GameModes; fixture setup never publishes it.
	PlayerState.game_mode_id = "enhanced_loot"
	PlayerState.later_content_enabled = true
	check(PlayerState.save_game(true, true, true), "sole writer saves B with plural pets, quest, target mode and sequence-one clock")
	if not failures.is_empty():
		_finish()
		return
	PlayerState._before_state_transaction(true)
	var b_document := _read(b_path)
	var generation := str(b_document.get("world_clock_generation", ""))
	trace["generation"] = generation
	var clock_path: String = PlayerState._world_clock_path(b_id, generation)
	var primary_clock := _read(clock_path)
	var backup_clock := _read(clock_path + ".bak")
	var expected_quest: Dictionary = {"status": "active", "progress": {"稻草人": 1}}
	check(not generation.is_empty() and not b_document.has("world_clock_import_source"),
		"ordinary B save completes import before testing admission")
	check(bool(PlayerState._validate_profile_document_status(b_document, b_id, false).get("valid", false)),
		"aggregate validator accepts the persisted B document")
	check(Ledger.valid_snapshot(primary_clock, b_id, generation) and Ledger.valid_snapshot(backup_clock, b_id, generation)
		and int(primary_clock.get("sequence", -1)) == 1 and int(backup_clock.get("sequence", -1)) == 0,
		"real B checkpoint has valid sequence-one primary and preserved sequence-zero backup")
	check(_wire_equal(b_document.get("quest_states", {}).get(QUEST_ID, {}), expected_quest)
		and b_document.get("taoist_main_pet_runtime_states", {}).get("contract_id", "") == PlayerState.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"plural-pet formal profile persists the independent expected active quest progress")
	var replay_before: Dictionary = PlayerState._read_world_clock_replay(b_document)
	check(bool(replay_before.get("ok", false)) and bool(replay_before.get("snapshot_present", false))
		and int(replay_before.get("latest_sequence", -1)) == 1
		and int(replay_before.get("source_world_sequence", -1)) == 1
		and int(replay_before.get("world_backup_sequence", -1)) == 0,
		"actual replay accepts B and proves backup zero is behind source one, requiring a checkpoint")
	if not failures.is_empty():
		_finish()
		return
	check(PlayerState.select_character(a_id), "formal selection restores real A before the B failure probe")
	PlayerState._before_state_transaction(true)
	check(PlayerState.active_profile_id == a_id and PlayerState.is_skill_learned("基本剑术")
		and not PlayerState.is_skill_learned("火球术") and PlayerState.quest_states.is_empty(),
		"A is distinguishable from B by real identity, skills and empty quests")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,
		"accepted writer callbacks drain before capturing A and creating the fault")
	if not failures.is_empty():
		_finish()
		return
	_writer_identity_negatives(a_id)
	if not failures.is_empty():
		_finish()
		return
	blocker_path = clock_path + ".tmp"
	blocker_marker = blocker_path.path_join("owned_by_profile_admission_test.json")
	trace["fault_path"] = ProjectSettings.globalize_path(blocker_path)
	check(_owned(blocker_path) and _owned(blocker_marker) and not FileAccess.file_exists(blocker_path)
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(blocker_path)),
		"only the exact absent B clock TMP inside this account is claimed for the directory fault")
	if not failures.is_empty():
		_finish()
		return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocker_path)) == OK,
		"owned directory occupies the exact formal clock temporary-file path")
	blocker_owned = failures.is_empty()
	var marker := FileAccess.open(blocker_marker, FileAccess.WRITE)
	check(marker != null, "fault ownership marker opens inside the exact TMP directory")
	if marker != null:
		marker.store_string(JSON.stringify({"run_id": run_id, "invocation_id": invocation_id, "profile_id": b_id, "generation": generation}))
		marker.close()
	var replay_blocked: Dictionary = PlayerState._read_world_clock_replay(b_document)
	check(replay_blocked == replay_before and bool(replay_blocked.get("ok", false)),
		"directory at TMP preserves the accepted real replay and its required checkpoint watermarks")
	if not failures.is_empty():
		_finish()
		return
	var a_before := _player_snapshot()
	var a_progression: RefCounted = PlayerState._skill_progression
	var a_loadout: RefCounted = PlayerState._feature_loadout
	var loadout_compiles: int = a_loadout.compile_count
	var flags_before: Dictionary = ContentLayers.enabled_expansions.duplicate(true)
	var data_revision: int = GameData.database_revision
	var catalog_before := _catalog_references()
	var content_revision: int = ContentLayers.configuration_revision
	var mode_before: String = GameModes.active_mode
	var files: Array[String] = [PlayerState._profile_path(a_id), PlayerState._profile_path(a_id) + ".bak",
		b_path, b_path + ".bak", PlayerState.profile_index_path, PlayerState.shared_warehouse_path,
		PlayerState.shared_warehouse_path + ".bak", clock_path, clock_path + ".bak"]
	var bytes_before := _files(files)
	var world_jobs_before: int = PlayerState._world_json_persistence.completed_count
	GameData.database_reloaded.connect(_on_database)
	ContentLayers.expansion_state_changed.connect(_on_expansion)
	PlayerState.profile_changed.connect(_on_profile)
	signals_connected = true
	var admitted: bool = PlayerState.select_character(b_id)
	trace["failure"] = {"admitted": admitted, "last_load_result": PlayerState.last_load_result.duplicate(true),
		"save_blocked_id": PlayerState._save_blocked_profile_id, "save_blocked_reason": PlayerState._save_blocked_reason,
		"signals": signal_counts.duplicate(true), "replay": replay_blocked, "world_jobs_before": world_jobs_before,
		"world_jobs_after": PlayerState._world_json_persistence.completed_count, "files_before": _file_hashes(bytes_before),
		"files_after_failure": _file_hashes(_files(files)),
		"catalog_reference_or_scalar_differences": _catalog_differences(catalog_before),
		"player_state_differences": _state_differences(a_before, _player_snapshot())}
	check(not admitted and not bool(PlayerState.last_load_result.get("success", true))
		and PlayerState.last_load_result.get("reason", "") == "world_clock_checkpoint_failed"
		and PlayerState.last_load_result.get("path", "") == b_path,
		"real B selection reaches the necessary checkpoint and fails with its exact load diagnostic")
	check(PlayerState._world_json_persistence.completed_count == world_jobs_before + 1
		and PlayerState._world_json_persistence.pending_count() == 0,
		"the same world persistence owner completes exactly one failed request, proving actual IO admission")
	check(_player_snapshot() == a_before and is_same(PlayerState._skill_progression, a_progression),
		"checkpoint rejection preserves A identity, basic fields, complete skill owner and world watermarks")
	check(is_same(PlayerState._feature_loadout, a_loadout) and a_loadout.compile_count == loadout_compiles,
		"checkpoint rejection preserves A effective feature object and compilation generation")
	check(GameData.is_loaded() and GameData.database_revision == data_revision
		and _catalog_differences(catalog_before).is_empty()
		and ContentLayers.configuration_revision == content_revision and ContentLayers.enabled_expansions == flags_before
		and GameModes.active_mode == mode_before and signal_counts == {"database": 0, "expansion": 0, "profile": 0},
		"checkpoint rejection preserves catalog revisions, mode and expansion flags without publication signals")
	check(PlayerState._save_blocked_profile_id == b_id and PlayerState._save_blocked_reason == "world_clock_checkpoint_failed",
		"failed target B retains its save block while valid old A remains active")
	check(_files(files) == bytes_before and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(blocker_path)),
		"failed admission leaves every captured profile, account, index and clock byte unchanged and keeps the owned blocker")
	# Exercise the real save gate against the failed target; it must reject
	# before checkpointing or serializing A's fields under B's identity.
	PlayerState.active_profile_id = b_id
	var blocked_save: bool = PlayerState.save_game(false, false, false)
	PlayerState.active_profile_id = a_id
	check(not blocked_save and PlayerState.last_save_result.get("reason", "") == "profile_save_blocked_after_invalid_load"
		and _files(files) == bytes_before and PlayerState.last_load_result.get("reason", "") == "world_clock_checkpoint_failed",
		"formal failed-B save gate rejects stale A fields before any profile or shared warehouse overwrite")
	if not failures.is_empty():
		_finish()
		return
	check(_remove_blocker(), "remove only this run's ownership marker and empty exact TMP directory")
	if not failures.is_empty():
		_finish()
		return
	var recovered: bool = PlayerState.select_character(b_id)
	trace["recovery"] = {"admitted": recovered, "last_load_result": PlayerState.last_load_result.duplicate(true),
		"signals": signal_counts.duplicate(true), "world_jobs_after": PlayerState._world_json_persistence.completed_count,
		"snapshot_sequence": PlayerState._world_clock_snapshot_sequence, "backup_sequence": PlayerState._world_clock_backup_sequence,
		"quests": PlayerState.quest_states.duplicate(true), "files_after": _file_hashes(_files(files))}
	check(recovered and bool(PlayerState.last_load_result.get("success", false)) and PlayerState.active_profile_id == b_id,
		"same formal B selection succeeds immediately after removing only the owned TMP fault")
	check(PlayerState._save_blocked_profile_id.is_empty() and PlayerState._save_blocked_reason.is_empty(),
		"successful B admission clears its previous load failure save guard")
	check(PlayerState.character_name == "AdmissionB" and PlayerState.level == 11 and PlayerState.gold == 5678
		and PlayerState.profession_id == "hc.profession.wizard" and PlayerState.gender == "女"
		and PlayerState.is_skill_learned("火球术") and not PlayerState.is_skill_learned("基本剑术"),
		"recovered B adopts its own stored fields and sole skill progression")
	check(_wire_equal(PlayerState.quest_states.get(QUEST_ID, {}), expected_quest)
		and PlayerState.taoist_main_pet_runtime_states.get("contract_id", "") == PlayerState.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"plural-pet formal profile restores B's independently expected quest progress outside the legacy singular branch")
	check(PlayerState._world_clock_snapshot_sequence == 1 and PlayerState._world_clock_backup_sequence == 1
		and not PlayerState._world_clock_dirty and PlayerState._world_json_persistence.completed_count == world_jobs_before + 2,
		"recovery performs one required checkpoint and adopts primary and backup watermarks without duplicate world IO")
	var requested: Dictionary = flags_before.duplicate(true)
	for package_id: String in requested:
		requested[package_id] = package_id in GameModes.modes["enhanced_loot"].get("enabledPackages", [])
	requested["later_176_content"] = true
	var changed := 0
	for package_id: String in requested:
		changed += 1 if requested[package_id] != flags_before[package_id] else 0
	check(GameModes.active_mode == "enhanced_loot" and PlayerState.game_mode_id == "enhanced_loot"
		and PlayerState.later_content_enabled and ContentLayers.enabled_expansions == requested
		and GameData.database_revision == data_revision + 1 and ContentLayers.configuration_revision == content_revision + 1
		and signal_counts.database == 1 and signal_counts.expansion == changed,
		"recovered B publishes its composed saved configuration exactly once through the formal owners")
	check(_files([PlayerState._profile_path(a_id), PlayerState._profile_path(a_id) + ".bak", b_path, b_path + ".bak",
		PlayerState.profile_index_path, PlayerState.shared_warehouse_path, PlayerState.shared_warehouse_path + ".bak"])
		== _files_subset(bytes_before, [PlayerState._profile_path(a_id), PlayerState._profile_path(a_id) + ".bak", b_path, b_path + ".bak",
		PlayerState.profile_index_path, PlayerState.shared_warehouse_path, PlayerState.shared_warehouse_path + ".bak"]),
		"ordinary recovery changes only the necessary world checkpoint and never rewrites character or shared account files")
	trace["owned_root"] = ProjectSettings.globalize_path(owned_root)
	trace["fault_path"] = ProjectSettings.globalize_path(blocker_path)
	trace["a_id"] = a_id
	trace["b_id"] = b_id
	trace["generation"] = generation
	_finish()


func _files_subset(snapshot: Dictionary, paths: Array[String]) -> Dictionary:
	var result := {}
	for path: String in paths:
		result[path] = snapshot[path]
	return result


func _remove_blocker() -> bool:
	if not blocker_owned:
		return true
	if not _owned(blocker_path) or not _owned(blocker_marker):
		return false
	if FileAccess.file_exists(blocker_marker) and DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker_marker)) != OK:
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker_path)) != OK:
		return false
	blocker_owned = false
	return true


func _finish() -> void:
	if signals_connected:
		GameData.database_reloaded.disconnect(_on_database)
		ContentLayers.expansion_state_changed.disconnect(_on_expansion)
		PlayerState.profile_changed.disconnect(_on_profile)
		signals_connected = false
	if blocker_owned:
		check(_remove_blocker(), "early terminal cleanup touches only this test's exact owned TMP marker and empty directory")
	trace["checks_before_trace_write"] = checks
	trace["failures_before_trace_write"] = failures.duplicate()
	trace["elapsed_usec"] = Time.get_ticks_usec() - started_usec
	if not owned_root.is_empty():
		trace["owned_root"] = ProjectSettings.globalize_path(owned_root)
	var evidence_directory := EVIDENCE_ROOT.path_join(OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID") + "_" + OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"))
	var trace_written := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory)) == OK
	var file: FileAccess = null
	if trace_written:
		file = FileAccess.open(evidence_directory.path_join("PROFILE_ADMISSION_TRACE.json"), FileAccess.WRITE)
	trace_written = file != null
	if file != null:
		file.store_string(JSON.stringify(trace, "  "))
		file.flush()
		trace_written = file.get_error() == OK
		file.close()
	check(trace_written, "native producer writes this invocation's complete owned admission trace")
	var failures_before_receipt := failures.size()
	var receipt_ok: bool = proof.write_receipt(SCENE_ID, checks, failures_before_receipt)
	if failures_before_receipt == 0 and not receipt_ok:
		failures.append("complete check receipt write or validation failed")
	print("PROFILE_LOAD_ADMISSION_20261010_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
