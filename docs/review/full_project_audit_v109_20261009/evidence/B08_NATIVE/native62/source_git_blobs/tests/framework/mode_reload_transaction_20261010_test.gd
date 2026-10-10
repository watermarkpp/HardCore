extends Node

## B08 mode/content publication. The fault is a real empty JSON map table in
## this run's owned user directory; every loader and profile writer is formal.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const GameDataScript := preload("res://scripts/game_data.gd")
const ModesScript := preload("res://scripts/layers/runtime/game_mode_service.gd")
const SCENE_ID := "mode_reload_transaction_20261010_test"
@export var test_partition := "all"
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
var run_started_usec := 0
var timing_records: Array[Dictionary] = []
var property_inventories: Dictionary = {}
var property_copy_records: Array[Dictionary] = []
var property_differences: Array[Dictionary] = []


func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	# Retain reached assertions in the native log even if the process cannot
	# reach its complete receipt. These lines never replace receipt acceptance.
	print("MODE_TRANSACTION_CHECK %d %s %s elapsed_usec=%d" % [checks, "PASS" if value else "FAIL", label, Time.get_ticks_usec() - run_started_usec])
	if not value:
		failures.append(label)


func _ready() -> void:
	run_started_usec = Time.get_ticks_usec()
	_run.call_deferred()


func _begin(label: String) -> int:
	var started: int = Time.get_ticks_usec()
	print("MODE_TRANSACTION_TIMING " + JSON.stringify({"event": "BEGIN", "scope": label,
		"after_check": checks, "elapsed_usec": started - run_started_usec}))
	return started


func _end(label: String, started: int) -> void:
	var finished: int = Time.get_ticks_usec()
	var record: Dictionary = {"event": "END", "scope": label, "after_check": checks,
		"elapsed_usec": finished - run_started_usec, "duration_usec": finished - started}
	timing_records.append(record)
	print("MODE_TRANSACTION_TIMING " + JSON.stringify(record))


func _timed_copy(value: Variant, label: String) -> Variant:
	var started := _begin(label)
	var result: Variant = _copy(value)
	_end(label, started)
	return result


func _value_summary(value: Variant) -> Dictionary:
	var result: Dictionary = {"variant_type": typeof(value)}
	if value is Dictionary or value is Array or value is PackedByteArray or value is PackedStringArray:
		result["size"] = value.size()
	elif value is Object:
		result["class"] = value.get_class() if is_instance_valid(value) else "freed"
		result["instance_id"] = value.get_instance_id() if is_instance_valid(value) else 0
	else:
		result["value"] = value
	return result


func _inventory_script_properties(owner: Object, properties: Array) -> void:
	var owner_path: String = owner.get_script().resource_path
	if property_inventories.has(owner_path):
		return
	var selected: Array[String] = []
	var rows: Array[Dictionary] = []
	for property: Dictionary in properties:
		var included: bool = (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
		var row: Dictionary = property.duplicate(true)
		row["selected_by_existing_snapshot_filter"] = included
		rows.append(row)
		if included:
			selected.append(str(property.get("name", "")))
	var constants: Dictionary = owner.get_script().get_script_constant_map()
	var constant_names: Array = constants.keys()
	constant_names.sort()
	var selected_constants: Array[String] = []
	for name: String in selected:
		if constants.has(name):
			selected_constants.append(name)
	var inventory: Dictionary = {"script": owner_path, "property_rows": rows, "selected_names": selected,
		"constant_names": constant_names, "selected_constant_names": selected_constants,
		"known_source_static_name": "spb_ledger_paths_override" if owner == GameData else "",
		"known_source_static_in_selected_names": "spb_ledger_paths_override" in selected if owner == GameData else false,
		"exclusion_rule": "unchanged original PROPERTY_USAGE_SCRIPT_VARIABLE filter; no new property exclusions"}
	property_inventories[owner_path] = inventory
	print("MODE_TRANSACTION_PROPERTY_INVENTORY " + JSON.stringify(inventory))


func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _script_properties(owner: Object) -> Dictionary:
	var owner_path: String = owner.get_script().resource_path
	var started := _begin("script_properties:" + owner_path)
	var result: Dictionary = {}
	var properties: Array = owner.get_script().get_script_property_list()
	_inventory_script_properties(owner, properties)
	for property: Dictionary in properties:
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var key := str(property.get("name", ""))
		if not key.is_empty():
			var value: Variant = owner.get(key)
			var copy_started: int = Time.get_ticks_usec()
			var large: bool = (value is Dictionary or value is Array) and value.size() >= 1000
			if large and owner == GameData:
				print("MODE_TRANSACTION_PROPERTY_COPY_BEGIN " + JSON.stringify({"property": key, "after_check": checks,
					"elapsed_usec": copy_started - run_started_usec, "summary": _value_summary(value)}))
			result[key] = _copy(value)
			var copy_record: Dictionary = {"script": owner_path, "property": key, "after_check": checks,
				"duration_usec": Time.get_ticks_usec() - copy_started, "summary": _value_summary(value)}
			property_copy_records.append(copy_record)
			if large and owner == GameData or int(copy_record.duration_usec) >= 20000:
				print("MODE_TRANSACTION_PROPERTY_COPY_END " + JSON.stringify(copy_record))
	_end("script_properties:" + owner_path, started)
	return result


func _report_property_differences(before: Dictionary, after: Dictionary, label: String) -> void:
	var names: Dictionary = {}
	for name: String in before:
		names[name] = true
	for name: String in after:
		names[name] = true
	for name: String in names:
		if before.has(name) and after.has(name) and before[name] == after[name]:
			continue
		var difference: Dictionary = {"boundary": label, "property": name, "after_check": checks,
			"before_present": before.has(name), "after_present": after.has(name),
			"before": _value_summary(before.get(name)), "after": _value_summary(after.get(name))}
		property_differences.append(difference)
		print("MODE_TRANSACTION_PROPERTY_DIFF " + JSON.stringify(difference))


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
	var started := _begin("snapshot")
	var files_started := _begin("snapshot:owned_file_bytes")
	var files := _file_bytes(owned_root)
	_end("snapshot:owned_file_bytes", files_started)
	var result := {"content_flags": ContentLayers.enabled_expansions.duplicate(true),
		"merged": _timed_copy(ContentLayers.merged_database, "snapshot:merged_database_copy"),
		"mode": GameModes.active_mode, "game_data": _script_properties(GameData),
		"player": _player_values(), "files": files,
		"signals": signal_counts.duplicate(true)}
	_end("snapshot", started)
	return result


func _unchanged(before: Dictionary, label: String) -> void:
	var started := _begin("unchanged:" + label)
	check(ContentLayers.enabled_expansions == before.content_flags and ContentLayers.merged_database == before.merged
		and GameModes.active_mode == before.mode, label + " preserves all active content flags/merged database/mode")
	var current_game_data: Dictionary = _script_properties(GameData)
	var compare_started := _begin("game_data_property_compare:" + label)
	var properties_equal: bool = current_game_data == before.game_data
	_end("game_data_property_compare:" + label, compare_started)
	check(properties_equal, label + " preserves every live GameData script property")
	if not properties_equal:
		var diff_started := _begin("game_data_property_diff:" + label)
		_report_property_differences(before.game_data, current_game_data, label)
		_end("game_data_property_diff:" + label, diff_started)
	check(_player_values() == before.player, label + " preserves player mode/later/level/gold/inventory/equipment/identity")
	var files_started := _begin("owned_file_bytes_compare:" + label)
	check(_file_bytes(owned_root) == before.files, label + " preserves all owned profile/index/shared/backup bytes")
	_end("owned_file_bytes_compare:" + label, files_started)
	check(signal_counts == before.signals, label + " emits no successful database/expansion/profile publication")
	_end("unchanged:" + label, started)


func _fault_maps() -> void:
	var vanilla: Dictionary = ContentLayers.manifests.get("vanilla_core", {}).duplicate(true)
	var datasets: Dictionary = vanilla.get("datasets", {}).duplicate(true)
	datasets["maps"] = empty_maps_path
	vanilla["datasets"] = datasets
	ContentLayers.manifests["vanilla_core"] = vanilla


func _restore_manifest() -> void:
	ContentLayers.manifests["vanilla_core"] = owned_manifest.duplicate(true)


func _run() -> void:
	var setup_started := _begin("group:setup")
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
	_end("group:setup", setup_started)
	if test_partition not in ["all", "input_composed", "stale", "profile", "later", "failure_boundary", "direct_failure"]:
		check(false, "wrapper names a registered complete transaction partition")
		_finish()
		return
	if test_partition in ["all", "input_composed"]:
		_run_group("input_and_nochange", _test_input_and_nochange_boundaries)
		_run_group("composed_positive_and_reentry", _test_composed_positive_and_reentry)
	else:
		_expect("modded_expansion", true)
		var init_started := _begin("formal_partition_precondition:init_modded")
		check(GameModes.apply_mode("modded_expansion", true), "partition establishes its real modded/later READY precondition through formal mode publication")
		_end("formal_partition_precondition:init_modded", init_started)
	if test_partition in ["all", "stale"]:
		_run_group("stale_and_abandoned", _test_stale_and_abandoned_preparations)
	if test_partition in ["all", "profile"]:
		_run_group("real_profile_failure_and_recovery", _test_real_profile_failure_and_recovery.bind(baseline_runtime))
	if test_partition in ["all", "later"]:
		_run_group("later_facade_positive", _test_later_facade_positive)
	if test_partition in ["all", "failure_boundary"]:
		_run_group("failed_public_apis", _test_failed_public_apis)
		_run_group("pre_ready_boundary", _test_pre_ready_boundary)
	if test_partition in ["all", "direct_failure"]:
		_run_group("direct_loaded_catalog_failure", _test_direct_loaded_catalog_failure)
	trace["final_player"] = _player_values()
	trace["final_file_sha256"] = _file_hashes()
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,
		"real profile and world persistence receipt owners drain before fixture retirement")
	_finish()


func _run_group(label: String, callback: Callable) -> void:
	var started := _begin("group:" + label)
	callback.call()
	_end("group:" + label, started)


func _scene_id() -> String:
	return SCENE_ID if test_partition == "all" else "mode_reload_transaction_" + test_partition + "_20261010_test"


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
	var prepare_started := _begin("formal_prepare:modded_composed")
	var prepared: Dictionary = GameModes.prepare_mode_configuration("modded_expansion", true)
	_end("formal_prepare:modded_composed", prepare_started)
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
	var apply_started := _begin("formal_apply:modded_composed")
	check(GameModes.apply_prepared_mode_configuration(prepared), "mode packages and explicit later override commit through one real validated candidate")
	_end("formal_apply:modded_composed", apply_started)
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
	var retire_started := _begin("prepared_release:consumed")
	prepared = {}
	_end("prepared_release:consumed", retire_started)
	check(GameModes.apply_mode("modded_expansion", true), "same composed mode/later transaction remains accepted")
	_unchanged(before, "same mode/later request")


func _test_stale_and_abandoned_preparations() -> void:
	_expect("modded_expansion", true)
	var before := _snapshot()
	var prepare_started := _begin("formal_prepare:stale_enhanced")
	var prepared: Dictionary = GameModes.prepare_mode_configuration("enhanced_loot", false)
	_end("formal_prepare:stale_enhanced", prepare_started)
	check(bool(prepared.get("success", false)), "stale fixture prepares a distinct legal mode through the real catalog validators")
	_unchanged(before, "stale fixture detached preparation")
	if not bool(prepared.get("success", false)):
		return
	var candidate_id: int = prepared.content.database_candidate.get_instance_id()
	var candidate_ref: WeakRef = weakref(prepared.content.database_candidate)
	var database_revision: int = GameData.database_revision
	var reload_started := _begin("formal_direct_reload:stale_live_revision")
	check(GameData.load_database(), "real direct reload advances the live database while a prior candidate is outstanding")
	_end("formal_direct_reload:stale_live_revision", reload_started)
	check(GameData.database_revision > database_revision and int(signal_counts.database) == 1,
		"stale preparation is caused by a genuine live database publication revision")
	before = _snapshot()
	check(not GameModes.apply_prepared_mode_configuration(prepared), "real revision change rejects the outstanding stale mode preparation")
	check(ContentLayers.last_expansion_error == "content_configuration_stale", "stale rejection exposes the preparation ownership diagnostic")
	_unchanged(before, "stale preparation rejection")
	var retire_started := _begin("prepared_release:stale_after_check94_in_native58")
	prepared = {}
	_end("prepared_release:stale_after_check94_in_native58", retire_started)
	check(candidate_ref.get_ref() == null and not is_instance_id_valid(candidate_id),
		"discarding a rejected stale preparation immediately frees its original detached GameData node")
	before = _snapshot()
	prepare_started = _begin("formal_prepare:abandoned_enhanced")
	var abandoned: Dictionary = GameModes.prepare_mode_configuration("enhanced_loot", false)
	_end("formal_prepare:abandoned_enhanced", prepare_started)
	check(bool(abandoned.get("success", false)), "abandoned fixture creates another real valid detached preparation")
	_unchanged(before, "abandoned detached preparation")
	if bool(abandoned.get("success", false)):
		candidate_id = abandoned.content.database_candidate.get_instance_id()
		candidate_ref = weakref(abandoned.content.database_candidate)
		retire_started = _begin("prepared_release:abandoned")
		abandoned = {}
		_end("prepared_release:abandoned", retire_started)
		check(candidate_ref.get_ref() == null and not is_instance_id_valid(candidate_id),
			"abandoning an uncommitted RefCounted preparation immediately frees its detached GameData node")
		_unchanged(before, "uncommitted preparation retirement")


func _test_real_profile_failure_and_recovery(baseline_runtime: Dictionary) -> void:
	PlayerState.level = 17
	PlayerState.gold = 1234
	var operation_started := _begin("formal_profile:receive")
	var receive_result: Dictionary = PlayerState.receive("hc.item.920001", 2)
	_end("formal_profile:receive", operation_started)
	check(bool(receive_result.get("success", false)), "desired legal profile obtains a registered item through the real inventory transaction")
	operation_started = _begin("formal_profile:unequip")
	var unequip_result: Dictionary = PlayerState.unequip_to_inventory_slot("hc.slot.weapon", 2)
	_end("formal_profile:unequip", operation_started)
	check(bool(unequip_result.get("success", false)), "desired legal equipment snapshot changes through the real equipment transaction")
	operation_started = _begin("formal_profile:save_desired")
	check(PlayerState.save_game(), "real writer persists the complete desired mode/later/player document")
	_end("formal_profile:save_desired", operation_started)
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
	operation_started = _begin("formal_profile:restore_classic_content")
	check(GameModes.apply_mode("classic_176", false), "live runtime baseline is restored through the formal mode owner before loading the desired bytes")
	_end("formal_profile:restore_classic_content", operation_started)
	_expect("classic_176", false)
	_fault_maps()
	var before := _snapshot()
	operation_started = _begin("formal_profile:load_owned_empty_maps_failure")
	PlayerState.load_save()
	_end("formal_profile:load_owned_empty_maps_failure", operation_started)
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
	operation_started = _begin("formal_profile:load_same_profile_recovery")
	PlayerState.load_save()
	_end("formal_profile:load_same_profile_recovery", operation_started)
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


func _test_direct_loaded_catalog_failure() -> void:
	_expect("modded_expansion", true)
	var before := _snapshot()
	var original_merged: Dictionary = ContentLayers.merged_database
	var skill_sample: Dictionary = GameData.skills[0]
	var monster_id: int = int(GameData._monsters_by_id.keys()[0])
	var direct: Node = GameDataScript.new()
	var direct_signals := {"count": 0}
	direct.database_reloaded.connect(func(): direct_signals["count"] += 1)
	var load_started := _begin("formal_direct_reload:detached_valid_baseline")
	check(direct.load_database() and direct.is_loaded() and not direct.maps.is_empty() and not direct.item_catalog.is_empty(),
		"B08-004 detached direct owner first loads the complete actual formal catalog")
	_end("formal_direct_reload:detached_valid_baseline", load_started)
	direct_signals["count"] = 0
	_fault_maps()
	var fault_build_started := _begin("formal_content_merge:owned_empty_maps")
	var fault_database: Dictionary = ContentLayers.build_merged_database()
	_end("formal_content_merge:owned_empty_maps", fault_build_started)
	check(fault_database.get("maps", []).is_empty(), "B08-004 real owned empty-map JSON reaches the formal merged database builder")
	check(ContentLayers.prepare_expansion_configuration(_configuration("classic_176", false)) == null,
		"B08-004 real failed candidate does not publish its empty map database")
	_unchanged(before, "B08-004 failed candidate retains live owner")
	ContentLayers.merged_database = fault_database
	trace["expected_production_rejection"] = {"classification": "EXPECTED_PRODUCTION_REJECTION",
		"scope": "direct empty-map load retains the formal push_error; runner FAIL must remain visible",
		"error": "五层内容注册表未能生成Merged Game Database"}
	print("MODE_TRANSACTION_EXPECTED_PRODUCTION_REJECTION " + JSON.stringify(trace.expected_production_rejection))
	load_started = _begin("formal_direct_reload:detached_owned_empty_maps_failure")
	var direct_result: bool = direct.load_database()
	_end("formal_direct_reload:detached_owned_empty_maps_failure", load_started)
	ContentLayers.merged_database = original_merged
	_restore_manifest()
	check(not direct_result and not direct.is_loaded() and not direct.load_error.is_empty(),
		"B08-004 real direct empty-map reload fails unloaded and retains its diagnostic")
	var failure_error: String = direct.load_error
	for field: String in GameDataScript.DATABASE_STATE_FIELDS:
		var value: Variant = direct.get(field)
		var empty := false
		if field == "load_error":
			empty = str(value) == failure_error and not failure_error.is_empty()
		elif value is Dictionary or value is Array or value is String or value is PackedStringArray:
			empty = value.is_empty()
		elif value is bool:
			empty = not value
		else:
			empty = value == null
		check(empty, "B08-004 direct failure clears formal catalog field or retains error: " + field)
	check(not direct._database_build_in_progress and int(direct_signals["count"]) == 0,
		"B08-004 direct failure closes its formal build guard and emits no success publication")
	check(direct.get_map_by_id(910001).is_empty() and direct.get_available_maps(true).is_empty(),
		"B08-004 unavailable direct map getters expose no prior map")
	check(direct.get_monster_by_id(monster_id).is_empty() and direct.get_canonical_monster_entry(monster_id).is_empty(),
		"B08-004 unavailable direct monster getters expose no prior canonical entry")
	check(direct.get_item("木剑").is_empty() and direct.get_item_record("hc.item.000080").is_empty()
		and direct.get_item_price_record("hc.item.000080").is_empty() and direct.item_catalog_counts().is_empty(),
		"B08-004 unavailable direct item and price getters do not repopulate old catalog authority")
	check(direct.get_skill(str(skill_sample.get("skill_id", "")), int(skill_sample.get("skillLevel", 0))).is_empty()
		and direct.get_bich_quests().is_empty() and direct.get_dpv2_direct_profile(monster_id).is_empty(),
		"B08-004 unavailable direct skill quest and drop getters expose no prior records")
	check(direct.load_error == failure_error and not direct.is_loaded(), "B08-004 getter reads retain the direct failure state and diagnostic")
	_unchanged(before, "B08-004 direct failure and getters retain original live owner")
	load_started = _begin("formal_direct_reload:detached_valid_before_pre_ready_failure")
	check(direct.load_database() and direct.is_loaded() and not direct.item_catalog.is_empty(),
		"B08-004 pre-READY negative begins from a real complete loaded direct catalog")
	_end("formal_direct_reload:detached_valid_before_pre_ready_failure", load_started)
	direct_signals["count"] = 0
	var content_ready: bool = ContentLayers._initial_load_complete
	ContentLayers._initial_load_complete = false
	load_started = _begin("formal_direct_reload:detached_pre_ready_failure")
	direct_result = direct.load_database()
	_end("formal_direct_reload:detached_pre_ready_failure", load_started)
	ContentLayers._initial_load_complete = content_ready
	check(not direct_result and not direct.is_loaded() and direct.load_error == "content_layers_not_ready",
		"B08-004 unavailable content owner rejects direct reload without the empty-map engine error path")
	for field: String in GameDataScript.DATABASE_STATE_FIELDS:
		var value: Variant = direct.get(field)
		var empty := false
		if field == "load_error":
			empty = str(value) == "content_layers_not_ready"
		elif value is Dictionary or value is Array or value is String or value is PackedStringArray:
			empty = value.is_empty()
		elif value is bool:
			empty = not value
		else:
			empty = value == null
		check(empty, "B08-004 pre-READY direct failure clears formal catalog field or retains error: " + field)
	check(not direct._database_build_in_progress and int(direct_signals["count"]) == 0,
		"B08-004 pre-READY direct rejection closes build guard and emits no success publication")
	check(direct.get_map_by_id(910001).is_empty() and direct.get_available_maps(true).is_empty()
		and direct.get_monster_by_id(monster_id).is_empty() and direct.get_canonical_monster_entry(monster_id).is_empty()
		and direct.get_item("木剑").is_empty() and direct.get_item_record("hc.item.000080").is_empty()
		and direct.get_item_price_record("hc.item.000080").is_empty() and direct.item_catalog_counts().is_empty()
		and direct.get_skill(str(skill_sample.get("skill_id", "")), int(skill_sample.get("skillLevel", 0))).is_empty()
		and direct.get_bich_quests().is_empty() and direct.get_dpv2_direct_profile(monster_id).is_empty(),
		"B08-004 pre-READY direct rejection keeps all public getter lanes empty without lazy reload")
	check(direct.load_error == "content_layers_not_ready" and not direct.is_loaded(),
		"B08-004 pre-READY getter reads retain unloaded state and the original unavailable-owner error")
	_unchanged(before, "B08-004 pre-READY direct failure retains original live owner")
	var free_started := _begin("direct_owner_release:failed_catalog")
	direct.free()
	_end("direct_owner_release:failed_catalog", free_started)


func _file_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in _file_bytes(owned_root):
		result[path] = FileAccess.get_sha256(path)
	return result


func _finish() -> void:
	var finish_started := _begin("group:fixture_retirement")
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
	trace["test_partition"] = test_partition
	trace["scene_id"] = _scene_id()
	trace["timings"] = timing_records
	trace["property_inventories"] = property_inventories
	trace["property_copy_timings"] = property_copy_records
	trace["property_differences"] = property_differences
	var trace_path := "res://outputs/test_logs/framework/" + _scene_id() + "." + OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID") + ".trace.json"
	var directory_ok := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_path.get_base_dir())) == OK
	var trace_file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE) if directory_ok and not FileAccess.file_exists(trace_path) else null
	check(trace_file != null, "transaction trace writes beside the complete framework receipt")
	trace["checks"] = checks
	trace["failures"] = failures.duplicate()
	if trace_file != null:
		trace_file.store_string(JSON.stringify(trace, "  "))
		trace_file.close()
	var receipt_ok := proof.write_receipt(_scene_id(), checks, failures.size())
	if not receipt_ok and failures.is_empty():
		failures.append("receipt write/validation failed")
	_end("group:fixture_retirement", finish_started)
	print("MODE_RELOAD_TRANSACTION_%s checks=%d failures=%s partition=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures), test_partition])
	get_tree().quit(0 if receipt_ok and failures.is_empty() else 1)
