extends Node

## B08 mode/content publication. The fault is a real empty JSON map table in
## this run's owned user directory; every loader and profile writer is formal.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const GameDataScript := preload("res://scripts/game_data.gd")
const ModesScript := preload("res://scripts/layers/runtime/game_mode_service.gd")
const SCENE_ID := "mode_reload_transaction_20261010_test"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var trace: Dictionary = {}
var owned_root := ""
var empty_maps_path := ""
var original_owners: Dictionary = {}
var original_player_runtime: Dictionary = {}
var original_player_processing := false
var owned_manifest: Dictionary = {}
var expected: Dictionary = {}
var signal_counts := {"database": 0, "expansion": 0, "profile": 0}
var observer_records: Array[Dictionary] = []
var connections_installed := false
var reentry_armed := false
var reentry_result := true


func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	# Retain reached assertions in the native log even if the process cannot
	# reach its complete receipt. These lines never replace receipt acceptance.
	print("MODE_TRANSACTION_CHECK %d %s %s" % [checks, "PASS" if value else "FAIL", label])
	if not value:
		failures.append(label)


func _ready() -> void:
	_run.call_deferred()


func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _script_properties(owner: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in owner.get_script().get_script_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var key := str(property.get("name", ""))
		if not key.is_empty():
			result[key] = _copy(owner.get(key))
	return result


func _restore_properties(owner: Object, snapshot: Dictionary) -> void:
	for key: String in snapshot:
		owner.set(key, _copy(snapshot[key]))


func _player_values() -> Dictionary:
	return {"profile_id": PlayerState.active_profile_id, "mode": PlayerState.game_mode_id,
		"later": PlayerState.later_content_enabled, "level": PlayerState.level,
		"gold": PlayerState.gold, "inventory": PlayerState.inventory.duplicate(true),
		"equipment": PlayerState.equipment.duplicate(true),
		"profession_id": PlayerState.profession_id, "gender": PlayerState.gender}


func _configuration(mode_id: String, later: bool) -> Dictionary:
	var result: Dictionary = {}
	var packages: Array = GameModes.modes.get(mode_id, {}).get("enabledPackages", [])
	for package_id: String in ContentLayers.enabled_expansions:
		result[package_id] = later if package_id == "later_176_content" else package_id in packages
	return result


func _expect(mode_id: String, later: bool) -> void:
	expected = {"mode": mode_id, "later": later, "flags": _configuration(mode_id, later)}
	signal_counts = {"database": 0, "expansion": 0, "profile": 0}
	observer_records.clear()


func _formal_catalog_ready() -> bool:
	return GameData.is_loaded() and GameData.load_error.is_empty() \
		and not GameData.maps.is_empty() and not GameData.items.is_empty() \
		and not GameData.skills.is_empty() and not GameData.item_catalog.is_empty() \
		and not GameData.canonical_monster_catalog.is_empty() \
		and not GameData._monsters_by_id.is_empty() and not GameData._catalog_by_item_id.is_empty() \
		and not GameData._skill_books_by_skill.is_empty() and GameData.dpv2_direct_baseline_loaded


func _observe(kind: String) -> void:
	signal_counts[kind] = int(signal_counts[kind]) + 1
	if expected.is_empty():
		return
	var observation := {"kind": kind, "mode": GameModes.active_mode,
		"player_mode": PlayerState.game_mode_id, "later": PlayerState.later_content_enabled,
		"flags": ContentLayers.enabled_expansions.duplicate(true),
		"active_expansions": ContentLayers.enabled_package_ids(), "catalog_ready": _formal_catalog_ready()}
	observer_records.append(observation)
	check(str(observation.mode) == str(expected.mode) and str(observation.player_mode) == str(expected.mode)
		and bool(observation.later) == bool(expected.later) and observation.flags == expected.flags
		and bool(observation.catalog_ready),
		"publication observer reads final mode/later/all flags/formal database: " + kind)
	var active: Array = []
	for package_id: String in expected.flags:
		if bool(expected.flags[package_id]):
			active.append(package_id)
	active.sort()
	var merged_active: Array = ContentLayers.merged_database.get("activeExpansions", []).duplicate()
	merged_active.sort()
	check(merged_active == active and GameData.database.get("activeExpansions", []) == ContentLayers.merged_database.get("activeExpansions", []),
		"publication observer sees the same composed merged database: " + kind)


func _on_database_reloaded() -> void:
	_observe("database")
	if reentry_armed:
		reentry_armed = false
		reentry_result = GameModes.apply_mode("classic_176", false)
		check(not reentry_result, "reentrant mode publication rejects while outer successful publication owns the boundary")


func _on_expansion_changed(_package_id: String, _enabled: bool) -> void:
	_observe("expansion")


func _on_profile_changed() -> void:
	_observe("profile")


func _file_bytes(directory_path: String) -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	for filename: String in directory.get_files():
		var path := directory_path.path_join(filename)
		result[path] = FileAccess.get_file_as_bytes(path)
	for dirname: String in directory.get_directories():
		result.merge(_file_bytes(directory_path.path_join(dirname)))
	return result


func _snapshot() -> Dictionary:
	return {"content_flags": ContentLayers.enabled_expansions.duplicate(true),
		"merged": ContentLayers.merged_database.duplicate(true),
		"mode": GameModes.active_mode, "game_data": _script_properties(GameData),
		"player": _player_values(), "files": _file_bytes(owned_root),
		"signals": signal_counts.duplicate(true)}


func _unchanged(before: Dictionary, label: String) -> void:
	check(ContentLayers.enabled_expansions == before.content_flags and ContentLayers.merged_database == before.merged
		and GameModes.active_mode == before.mode, label + " preserves all active content flags/merged database/mode")
	check(_script_properties(GameData) == before.game_data, label + " preserves every live GameData script property")
	check(_player_values() == before.player, label + " preserves player mode/later/level/gold/inventory/equipment/identity")
	check(_file_bytes(owned_root) == before.files, label + " preserves all owned profile/index/shared/backup bytes")
	check(signal_counts == before.signals, label + " emits no successful database/expansion/profile publication")


func _fault_maps() -> void:
	var vanilla: Dictionary = ContentLayers.manifests.get("vanilla_core", {}).duplicate(true)
	var datasets: Dictionary = vanilla.get("datasets", {}).duplicate(true)
	datasets["maps"] = empty_maps_path
	vanilla["datasets"] = datasets
	ContentLayers.manifests["vanilla_core"] = vanilla


func _restore_manifest() -> void:
	ContentLayers.manifests["vanilla_core"] = owned_manifest.duplicate(true)


func _run() -> void:
	var run_id := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	var invocation := OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	var isolated := user_root.contains("/.godot/runtime_appdata/")
	trace = {"run_id": run_id, "invocation_id": invocation,
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"user_data_directory": OS.get_user_data_dir(), "fixture_retirement_owner": "main controller",
		"scope": "real formal catalogs and real isolated profile persistence; empty maps JSON candidate failure"}
	check(isolated and not run_id.is_empty() and not invocation.is_empty(), "transaction fixture uses this runner invocation's independent runtime userdata")
	if not isolated or run_id.is_empty() or invocation.is_empty():
		_finish()
		return
	owned_root = "user://mode_reload_transaction_20261010_" + run_id + "_" + invocation + "_" + str(get_instance_id())
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(owned_root)), "unique transaction fixture directory is absent before ownership")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(owned_root)):
		owned_root = ""
		_finish()
		return
	check(ContentLayers.ensure_loaded(), "formal content owner reaches READY before transaction component tests")
	check(GameData.ensure_loaded() and _formal_catalog_ready(), "all formal GameData load stages and canonical indexes reach READY")
	if not ContentLayers.is_loaded() or not _formal_catalog_ready():
		_finish()
		return
	original_owners = {"content": _script_properties(ContentLayers), "data": _script_properties(GameData),
		"modes": _script_properties(GameModes), "player": _script_properties(PlayerState)}
	original_player_runtime = PlayerState._creation_runtime_snapshot()
	original_player_processing = PlayerState.is_processing()
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
	check(PlayerState._shared_warehouse_test_isolation_enabled() and not PlayerState.test_mode, "all real persistence authorities point only inside the owned account directory")
	var create_result: String = PlayerState.create_character("事务载入角色", "hc.profession.warrior", "男")
	check(create_result.is_empty(), "real profile owner creates a complete legal starter character: " + create_result)
	if not create_result.is_empty():
		_finish()
		return
	check(GameModes.apply_mode("classic_176", false), "fixture baseline is accepted through the formal composed mode owner")
	var baseline_runtime: Dictionary = PlayerState._creation_runtime_snapshot()
	owned_manifest = ContentLayers.manifests["vanilla_core"].duplicate(true)
	empty_maps_path = owned_root.path_join("empty_maps.json")
	var fault_file := FileAccess.open(empty_maps_path, FileAccess.WRITE)
	check(fault_file != null, "owned fault JSON opens only within the unique isolated account")
	if fault_file == null:
		_finish()
		return
	fault_file.store_string(JSON.stringify({"schemaVersion": 1, "table": "maps", "records": []}))
	fault_file.close()
	trace["owned_root"] = ProjectSettings.globalize_path(owned_root)
	trace["fault_path"] = empty_maps_path
	GameData.database_reloaded.connect(_on_database_reloaded)
	ContentLayers.expansion_state_changed.connect(_on_expansion_changed)
	PlayerState.profile_changed.connect(_on_profile_changed)
	connections_installed = true
	_test_input_and_nochange_boundaries()
	_test_composed_positive_and_reentry()
	_test_stale_and_abandoned_preparations()
	_test_real_profile_failure_and_recovery(baseline_runtime)
	_test_later_facade_positive()
	_test_failed_public_apis()
	_test_pre_ready_boundary()
	trace["final_player"] = _player_values()
	trace["final_file_sha256"] = _file_hashes()
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,
		"real profile and world persistence receipt owners drain before fixture retirement")
	_finish()


func _test_input_and_nochange_boundaries() -> void:
	_expect("classic_176", false)
	var same: Dictionary = _configuration("classic_176", false)
	var before := _snapshot()
	check(ContentLayers.apply_expansion_configuration(same), "exact same complete boolean configuration is an accepted no-change request")
	_unchanged(before, "same configuration")
	check(not RuntimeServices.set_expansion_enabled("later_176_content", false), "facade keeps its no-change false contract")
	_unchanged(before, "no-change facade")
	check(not GameModes.apply_mode("hc.mode.invalid.fixture", true), "unknown mode rejects before publication")
	_unchanged(before, "unknown mode")
	var unknown := same.duplicate(true)
	unknown["hc.package.invalid.fixture"] = true
	check(not ContentLayers.apply_expansion_configuration(unknown), "unknown package rejects the complete candidate")
	_unchanged(before, "unknown package")
	var missing := same.duplicate(true)
	missing.erase("later_176_content")
	check(not ContentLayers.apply_expansion_configuration(missing), "missing known package key rejects incomplete flags")
	_unchanged(before, "missing package key")
	var nonbool := same.duplicate(true)
	nonbool["later_176_content"] = 1
	check(not ContentLayers.apply_expansion_configuration(nonbool), "nonboolean package value rejects instead of coercing the identity configuration")
	_unchanged(before, "nonboolean configuration")


func _test_composed_positive_and_reentry() -> void:
	_expect("modded_expansion", true)
	var before_prepare := _snapshot()
	var prepared: Dictionary = GameModes.prepare_mode_configuration("modded_expansion", true)
	check(bool(prepared.get("success", false)), "mode/later preparation validates the complete formal detached catalog")
	_unchanged(before_prepare, "successful detached preparation")
	if not bool(prepared.get("success", false)):
		return
	var candidate_id: int = prepared.content.database_candidate.get_instance_id()
	var candidate_ref: WeakRef = weakref(prepared.content.database_candidate)
	check(candidate_ref.get_ref() != null and not prepared.content.database_candidate.is_inside_tree(),
		"prepared catalog is a live detached GameData node before publication")
	reentry_result = true
	reentry_armed = true
	check(GameModes.apply_prepared_mode_configuration(prepared), "mode packages and explicit later override commit through one real validated candidate")
	check(not reentry_armed and not reentry_result, "actual live database publication exercised the reentry rejection")
	check(bool(prepared.content.consumed) and prepared.content.database_candidate == null
		and candidate_ref.get_ref() == null and not is_instance_id_valid(candidate_id),
		"successful adoption consumes preparation and immediately frees its detached GameData node")
	check(int(signal_counts.database) == 1 and int(signal_counts.expansion) == 3,
		"composed mode/later transaction publishes one live database and exactly its three changed package signals")
	check(GameModes.active_mode == "modded_expansion" and PlayerState.game_mode_id == "modded_expansion"
		and PlayerState.later_content_enabled and ContentLayers.enabled_expansions == expected.flags and _formal_catalog_ready(),
		"successful transaction retains the complete composed mode/later/formal catalog")
	trace["composed_publication_observers"] = observer_records.duplicate(true)
	var before := _snapshot()
	check(not GameModes.apply_prepared_mode_configuration(prepared), "consumed mode/content preparation rejects a second publication")
	_unchanged(before, "consumed preparation")
	prepared = {}
	check(GameModes.apply_mode("modded_expansion", true), "same composed mode/later transaction remains accepted")
	_unchanged(before, "same mode/later request")


func _test_stale_and_abandoned_preparations() -> void:
	_expect("modded_expansion", true)
	var before := _snapshot()
	var prepared: Dictionary = GameModes.prepare_mode_configuration("enhanced_loot", false)
	check(bool(prepared.get("success", false)), "stale fixture prepares a distinct legal mode through the real catalog validators")
	_unchanged(before, "stale fixture detached preparation")
	if not bool(prepared.get("success", false)):
		return
	var candidate_id: int = prepared.content.database_candidate.get_instance_id()
	var candidate_ref: WeakRef = weakref(prepared.content.database_candidate)
	var database_revision: int = GameData.database_revision
	check(GameData.load_database(), "real direct reload advances the live database while a prior candidate is outstanding")
	check(GameData.database_revision > database_revision and int(signal_counts.database) == 1,
		"stale preparation is caused by a genuine live database publication revision")
	before = _snapshot()
	check(not GameModes.apply_prepared_mode_configuration(prepared), "real revision change rejects the outstanding stale mode preparation")
	check(ContentLayers.last_expansion_error == "content_configuration_stale", "stale rejection exposes the preparation ownership diagnostic")
	_unchanged(before, "stale preparation rejection")
	prepared = {}
	check(candidate_ref.get_ref() == null and not is_instance_id_valid(candidate_id),
		"discarding a rejected stale preparation immediately frees its original detached GameData node")
	before = _snapshot()
	var abandoned: Dictionary = GameModes.prepare_mode_configuration("enhanced_loot", false)
	check(bool(abandoned.get("success", false)), "abandoned fixture creates another real valid detached preparation")
	_unchanged(before, "abandoned detached preparation")
	if bool(abandoned.get("success", false)):
		candidate_id = abandoned.content.database_candidate.get_instance_id()
		candidate_ref = weakref(abandoned.content.database_candidate)
		abandoned = {}
		check(candidate_ref.get_ref() == null and not is_instance_id_valid(candidate_id),
			"abandoning an uncommitted RefCounted preparation immediately frees its detached GameData node")
		_unchanged(before, "uncommitted preparation retirement")


func _test_real_profile_failure_and_recovery(baseline_runtime: Dictionary) -> void:
	PlayerState.level = 17
	PlayerState.gold = 1234
	var receive_result: Dictionary = PlayerState.receive("hc.item.920001", 2)
	check(bool(receive_result.get("success", false)), "desired legal profile obtains a registered item through the real inventory transaction")
	var unequip_result: Dictionary = PlayerState.unequip_to_inventory_slot("hc.slot.weapon", 2)
	check(bool(unequip_result.get("success", false)), "desired legal equipment snapshot changes through the real equipment transaction")
	check(PlayerState.save_game(), "real writer persists the complete desired mode/later/player document")
	var desired := _player_values()
	var profile_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var desired_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	check(desired_document is Dictionary and bool(PlayerState._validate_profile_document_status(desired_document, PlayerState.active_profile_id, false).get("valid", false)),
		"desired load fixture is the real writer's complete business-valid profile payload")
	check(desired_document is Dictionary and desired_document.get("game_mode_id", "") == "modded_expansion"
		and bool(desired_document.get("later_content_enabled", false)) and int(desired_document.get("level", 0)) == 17,
		"real profile bytes carry the desired mode/later and distinguishable loaded player values")
	expected.clear()
	PlayerState._restore_creation_runtime(baseline_runtime)
	check(GameModes.apply_mode("classic_176", false), "live runtime baseline is restored through the formal mode owner before loading the desired bytes")
	_expect("classic_176", false)
	_fault_maps()
	var before := _snapshot()
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)) and PlayerState.last_load_result.get("reason", "") == "content_configuration_failed",
		"real profile loader records the actual candidate content failure before publishing player restoration")
	check(not ContentLayers.last_expansion_error.is_empty() and PlayerState.last_load_result.get("catalog_error", "") == ContentLayers.last_expansion_error,
		"real load failure receipt retains the content owner's actual catalog error")
	_unchanged(before, "failed real mode/later profile load")
	check(PlayerState._save_blocked_profile_id == PlayerState.active_profile_id and PlayerState._save_blocked_reason == "content_configuration_failed",
		"failed content profile load installs the real profile save guard")
	trace["failed_load_result"] = PlayerState.last_load_result.duplicate(true)
	check(not PlayerState.save_game() and PlayerState.last_save_result.get("reason", "") == "profile_save_blocked_after_invalid_load",
		"real save owner rejects autosave-equivalent overwrite after failed content load")
	_unchanged(before, "save blocked after failed load")
	_restore_manifest()
	_expect("modded_expansion", true)
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)), "same real profile loads successfully after restoring the exact formal manifest")
	check(_player_values() == desired and _formal_catalog_ready(), "complete successful reload restores the writer's mode/later/level/gold/inventory/equipment/identity")
	check(int(signal_counts.database) == 1 and int(signal_counts.expansion) == 3,
		"real loader composes persisted mode/later into one live database publication")
	check(PlayerState._save_blocked_profile_id.is_empty() and PlayerState._save_blocked_reason.is_empty(), "validated same-profile reload clears the real save guard")
	trace["recovered_load_result"] = PlayerState.last_load_result.duplicate(true)
	trace["recovered_load_observers"] = observer_records.duplicate(true)
	check(PlayerState.save_game(), "real save owner accepts the profile after successful content recovery")


func _test_later_facade_positive() -> void:
	_expect("modded_expansion", false)
	check(PlayerState.set_later_content_enabled(false), "formal player later setter commits a validated change and real durable profile")
	check(int(signal_counts.database) == 1 and int(signal_counts.expansion) == 1 and int(signal_counts.profile) == 1,
		"player later setter reloads once and publishes its one package and profile signal after consistency")
	var profile_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	check(saved is Dictionary and not bool(saved.get("later_content_enabled", true)), "real later setter saves the committed false flag through the profile authority")
	_expect("modded_expansion", true)
	check(RuntimeServices.set_expansion_enabled("later_176_content", true), "facade later change reaches the formal player/content transaction")
	check(int(signal_counts.database) == 1 and int(signal_counts.expansion) == 1 and int(signal_counts.profile) == 1,
		"facade later change uses exactly one candidate reload and one durable player signal")
	saved = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	check(saved is Dictionary and bool(saved.get("later_content_enabled", false)), "facade later change persists the same committed true flag")


func _test_failed_public_apis() -> void:
	_expect("modded_expansion", true)
	_fault_maps()
	var before := _snapshot()
	check(not ContentLayers.apply_expansion_configuration(_configuration("classic_176", false)), "real empty-map candidate rejects the public complete configuration")
	check(not ContentLayers.last_expansion_error.is_empty(), "failed real candidate exposes a content-owned diagnostic")
	_unchanged(before, "failed content transaction")
	check(not GameModes.apply_mode("classic_176", false), "real empty-map candidate rejects the formal mode API")
	_unchanged(before, "failed mode API")
	check(not RuntimeServices.set_expansion_enabled("personal_expansion_001", false), "real empty-map candidate rejects the regular package facade")
	_unchanged(before, "failed regular facade")
	check(not RuntimeServices.set_expansion_enabled("later_176_content", false), "real empty-map candidate rejects the later-content facade")
	_unchanged(before, "failed later facade")
	check(not PlayerState.set_later_content_enabled(false), "real empty-map candidate rejects the player later setter without saving or signalling")
	_unchanged(before, "failed player later setter")
	check(not RuntimeServices.set_expansion_enabled("hc.package.invalid.fixture", true), "unknown facade package rejects explicitly")
	_unchanged(before, "unknown facade package")
	_restore_manifest()


func _test_pre_ready_boundary() -> void:
	_expect("modded_expansion", true)
	var ready_before: bool = ContentLayers._initial_load_complete
	ContentLayers._initial_load_complete = false
	var before := _snapshot()
	check(not ContentLayers.apply_expansion_configuration(_configuration("classic_176", false)), "content transaction rejects before content component READY")
	_unchanged(before, "pre-READY content request")
	check(not GameModes.apply_mode("classic_176", false), "mode request rejects before content component READY")
	_unchanged(before, "pre-READY mode request")
	check(not RuntimeServices.set_expansion_enabled("later_176_content", false), "facade request rejects before content component READY")
	_unchanged(before, "pre-READY facade request")
	check(not PlayerState.set_later_content_enabled(false), "player later setter rejects before content component READY")
	_unchanged(before, "pre-READY player later request")
	var modes_fixture: Node = ModesScript.new()
	modes_fixture._ready()
	check(not modes_fixture.modes.is_empty(), "detached real GameModes ready reads its formal mode configuration")
	_unchanged(before, "pre-READY GameModes initialization")
	modes_fixture.free()
	var direct: Node = GameDataScript.new()
	direct._initial_load_complete = true
	check(not direct.load_database() and not direct.is_loaded() and direct.load_error == "content_layers_not_ready",
		"direct real GameData reload failure returns false and invalidates its own loaded flag")
	_unchanged(before, "detached direct-load failure")
	direct.free()
	ContentLayers._initial_load_complete = ready_before
	check(ContentLayers.is_loaded() and _formal_catalog_ready(), "pre-READY diagnostic restores original formal component readiness")


func _file_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in _file_bytes(owned_root):
		result[path] = FileAccess.get_sha256(path)
	return result


func _finish() -> void:
	if connections_installed:
		GameData.database_reloaded.disconnect(_on_database_reloaded)
		ContentLayers.expansion_state_changed.disconnect(_on_expansion_changed)
		PlayerState.profile_changed.disconnect(_on_profile_changed)
		connections_installed = false
	if not original_owners.is_empty():
		_restore_properties(ContentLayers, original_owners.content)
		_restore_properties(GameData, original_owners.data)
		_restore_properties(GameModes, original_owners.modes)
		_restore_properties(PlayerState, original_owners.player)
		PlayerState._restore_creation_runtime(original_player_runtime)
		PlayerState.set_process(original_player_processing)
		check(_script_properties(ContentLayers) == original_owners.content and _script_properties(GameData) == original_owners.data
			and _script_properties(GameModes) == original_owners.modes,
			"fixture retirement restores original live content/database/mode owner properties")
		check(_player_values().get("profile_id", "") == str(original_player_runtime.get("active_profile_id", ""))
			and PlayerState.profile_directory == original_owners.player.profile_directory
			and PlayerState.shared_warehouse_path == original_owners.player.shared_warehouse_path,
			"fixture retirement restores original player identity and persistence paths")
	trace["owned_files_retained"] = not owned_root.is_empty()
	var trace_path := "res://outputs/test_logs/framework/" + SCENE_ID + "." + OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID") + ".trace.json"
	var directory_ok := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_path.get_base_dir())) == OK
	var trace_file := FileAccess.open(trace_path, FileAccess.WRITE) if directory_ok and not FileAccess.file_exists(trace_path) else null
	check(trace_file != null, "transaction trace writes beside the complete framework receipt")
	trace["checks"] = checks
	trace["failures"] = failures.duplicate()
	if trace_file != null:
		trace_file.store_string(JSON.stringify(trace, "  "))
		trace_file.close()
	var receipt_ok := proof.write_receipt(SCENE_ID, checks, failures.size())
	if not receipt_ok:
		failures.append("framework receipt write failed")
	print("MODE_RELOAD_TRANSACTION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if receipt_ok and failures.is_empty() else 1)
