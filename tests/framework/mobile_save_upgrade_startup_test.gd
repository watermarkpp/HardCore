extends Node

const Startup := preload("res://scripts/startup_loading.gd")
const FakeIntro := preload("res://tests/startup_fake_brand_intro.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SaveDiagnostic := preload("res://scripts/save_upgrade_diagnostic.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const RelicRecovery := preload("res://scripts/save_relic_recovery.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func put(path: String, document: Dictionary) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK, "owned startup fixture directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned startup fixture file")
	if file != null:
		file.store_string(JSON.stringify(document, "\t"))
		file.close()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("HARDCORE_SAVE_RECOVERY_COLD_ONLY") == "1":
		_cold_recovery()
		return
	var root := "user://mobile_upgrade_startup_%d" % Time.get_ticks_usec()
	PlayerState.test_mode = false
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	var path := PlayerState.profile_directory.path_join("A.json")
	var known := {"save_version":7,"profile_id":"A","profession":"战士","gender":"男",
		"character_name":"启动升级验证","level":10,"gold":98765,"experience":123,
		"inventory":[],"equipment":{},"learned_skills":{},"quest_states":{}}
	var future := known.duplicate(true)
	future.save_version = 11
	put(path, future)
	put(path + ".bak", known)
	put(PlayerState.profile_index_path, {"version":1,"profiles":[{"id":"A"}]})
	var future_sha := FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	var startup := Startup.new()
	startup.auto_start = false
	startup.suppress_scene_handoff_for_test = true
	startup.force_main_scene_prefetch_failure_for_test = true
	var intro := FakeIntro.new()
	intro.name = "BrandIntro"
	intro.first_frame_presented = true
	intro.animation_complete = true
	startup.add_child(intro)
	add_child(startup)
	# The handoff uses an actual scene resource; unknown saves must stop even
	# when destination loading and the authored intro are already complete.
	startup._target_scene = load("res://scenes/character_select.tscn")
	startup._resource_ready = true
	startup._animation_finished = true
	startup._queue_authoritative_data_attempt()
	for frame in range(3): await get_tree().process_frame
	var diagnostic := startup.startup_diagnostic()
	check(diagnostic.get("state") == Startup.STARTUP_STATE_RECOVERABLE_FAILURE, "real startup exposes failed save upgrade")
	check(diagnostic.get("failure_code") == "STARTUP_DATA_SAVE_UPGRADE_FAILED", "save boundary failure classified")
	var save_detail: Dictionary = diagnostic.get("save_upgrade", {})
	check(save_detail.get("reason_code") == "future_save_version", "phone exposes precise upgrade reason without save contents")
	check(save_detail.get("phase") == "preflight" and bool(save_detail.get("source_backup_verified", false)), "phone distinguishes verified original backup from failed conversion")
	check(startup.failure_message_label.text.contains("future_save_version") and startup.failure_message_label.text.contains("备份已验证"), "real failure overlay includes reason and custody status")
	check(not startup.failure_message_label.text.contains(root) and not JSON.stringify(save_detail).contains(path), "public startup diagnostic contains no private profile path")
	check(not startup._target_prepare_started and not is_instance_valid(startup._target_scene_instance), "no CharacterSelect instance before aggregate admission")
	check(startup.failure_overlay.visible and startup.failure_retry_button.visible, "phone has retry UI")
	check(FileAccess.get_sha256(path) == future_sha and not PlayerState.select_character("A"), "unknown primary remains intact and unplayable despite old backup")
	# Model an externally repaired owned fixture, then use the real UI retry.
	# Production never guesses this repair or substitutes its older backup.
	put(path, known)
	startup.failure_retry_button.emit_signal("pressed")
	for frame in range(60):
		await get_tree().process_frame
		if startup._target_handoff_count > 0: break
	diagnostic = startup.startup_diagnostic()
	check(bool(diagnostic.get("authoritative_data_ready")), "retry re-enters real authority and migration boundaries")
	check(bool(PlayerState.startup_save_upgrade_result.get("success")), "real retry commits automatic save conversion")
	check(startup._target_handoff_count == 1 and is_instance_valid(startup._target_scene_instance), "real CharacterSelect admitted exactly once")
	check(not startup.failure_overlay.visible, "successful retry removes failure overlay")
	check((diagnostic.get("save_upgrade", {}) as Dictionary).is_empty(), "successful retry clears stale save failure details")
	check(PlayerState.list_characters().size() == 1, "real CharacterSelect sees upgraded profile")
	check(PlayerState.select_character("A") and PlayerState.gold == 98765 and PlayerState.experience == 123, "real destination can load retained progress")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0, "startup writes and accepted receipts ended before gameplay")
	var unsafe := SaveDiagnostic.build({"reason":"private player/path secret", "path":path, "phase":"private phase"})
	check(unsafe.get("reason_code") == "unclassified_upgrade_failure" and unsafe.get("phase") == "unknown", "unknown diagnostic strings are not echoed to screenshots")
	check(not JSON.stringify(unsafe).contains("secret") and not JSON.stringify(unsafe).contains(path), "diagnostic projection omits arbitrary input and private path")
	# A genuinely invalid before-image manifest must remain a failure, never
	# claim verified custody, and never change the player's original bytes.
	var bad_root := root + "_bad_manifest"
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = bad_root.path_join("characters")
	PlayerState.profile_index_path = bad_root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = bad_root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = bad_root.path_join("shared_warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	var retained := PlayerState.profile_directory.path_join("A.json")
	put(retained, known)
	put(bad_root.path_join("save_upgrades/framework_identity_v1/manifest.json"), {"contract_id":"unknown"})
	var retained_sha := FileAccess.get_sha256(retained)
	PlayerState.begin_startup_save_upgrade()
	startup._queue_authoritative_data_attempt()
	for frame in range(3): await get_tree().process_frame
	diagnostic = startup.startup_diagnostic()
	save_detail = diagnostic.get("save_upgrade", {})
	check(save_detail.get("reason_code") == "upgrade_backup_manifest_invalid" and save_detail.get("phase") == "backup", "real backup failure has specific stage and reason")
	check(not bool(save_detail.get("source_backup_verified", true)) and startup.failure_message_label.text.contains("尚未验证"), "failed backup cannot claim verified original custody")
	check(FileAccess.get_sha256(retained) == retained_sha and not PlayerState.select_character("A"), "diagnostic reporting cannot overwrite or admit unverified profile")
	startup.failure_retry_button.emit_signal("pressed")
	for frame in range(3): await get_tree().process_frame
	check(FileAccess.get_sha256(retained) == retained_sha and startup.failure_overlay.visible, "unchanged storage fault remains protected on real retry")
	PlayerState.active_profile_id = ""
	startup.queue_free()
	await get_tree().process_frame
	await _relic_recovery_cases(known, root + "_relic")
	if not proof.write_receipt("mobile_save_upgrade_startup_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_MOBILE_SAVE_UPGRADE_STARTUP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _relic_recovery_cases(known: Dictionary, root: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 112
	var good := RelicRules.roll_instance(950202, "法师", rng)
	good.instance_id = "retained_wizard_badge"
	var broken := good.duplicate(true)
	broken.instance_id = "broken_wizard_badge"
	broken.modifiers = []
	var documents := {}
	for id: String in ["A", "B", "C"]:
		var doc := known.duplicate(true)
		doc.profile_id = id
		doc.profession = {"A":"战士", "B":"法师", "C":"道士"}[id]
		doc.gold = 123456
		doc.level = 35
		if id == "B": doc.inventory = [good, broken]
		documents[id] = doc
	_setup_recovery_root(root, documents)
	var path := PlayerState.profile_directory.path_join("B.json")
	var old: Dictionary = documents.B.duplicate(true)
	old.inventory = [good]
	old.gold = 99
	put(path + ".bak", old)
	var original_sha := FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	var recovered := PlayerState.finish_startup_save_upgrade()
	check(recovered, "known corrupt wizard badge recovers through startup owner")
	check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/characters/B.json")) == original_sha, "recovery retains exact original corrupt profile before removal")
	if recovered:
		check(PlayerState.select_character("B") and PlayerState.gold == 123456, "repair uses latest primary progress rather than older valid backup")
		# The existing load/save owner trims an empty tail. Interior positions
		# are preserved by the planner; no healthy record is compacted by it.
		check(PlayerState.inventory.size() == 1 and PlayerState.inventory[0].get("instance_id") == good.instance_id and PlayerState.inventory[0].get("relic_roll") == good.relic_roll, "repair removes only broken badge and retains exact healthy roll through normal tail trim")
		check(PlayerState._can_accept_immediate_item_use() and PlayerState.save_game(true, true, true), "recovered wizard accepts mutation and real durable save")
		var equipped: Dictionary = PlayerState.equip_inventory_index_result(0, "hc.slot.badge", good.instance_id)
		check(bool(equipped.get("success", false)) and PlayerState.save_game(true, true, true), "recovered wizard can change equipment and persist it")
		var stock := [{"entity_id":"hc.item.000080"}]
		var quotes := PlayerState.shop_buy_quotes(stock)
		var balance: int = PlayerState.gold
		var purchase: Dictionary = PlayerState.buy_shop_item({"stock_index":0, "quote_id":quotes[0].get("quote_id", ""), "quantity":1}, stock)
		check(bool(purchase.get("success", false)) and PlayerState.gold == balance - int(quotes[0].get("total_price", 0)), "recovered wizard accepts real NPC shop transaction with durable save")
		# Each formal runner invocation owns independent user data. Publish a
		# source/run-bound fixture link; the next native process reads these
		# actual producer files, never a reconstructed or copied profile.
		put("res://outputs/test_logs/framework/save_recovery_v112_pointer.json", {
			"root":ProjectSettings.globalize_path(root), "gold":PlayerState.gold,
			"good":good, "archive_sha256":original_sha,
			"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"source_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"producer_pid":OS.get_process_id()})
		for id: String in ["A", "C"]:
			check(PlayerState.select_character(id) and PlayerState.gold == 123456, "repair retains other role progress " + id)
		var report: Array = PlayerState.startup_save_upgrade_result.get("relic_recovery", [])
		check(report.size() == 1 and report[0].get("profile_id") == "B" and (report[0].get("removed", []) as Array).size() == 1, "successful repair reports exact role and item removal count")
		var hall: Control = load("res://scenes/character_select.tscn").instantiate()
		add_child(hall)
		check(hall.message_label.text.contains("1 件损坏") and hall.message_label.text.contains("原档已备份"), "real character hall displays loss count and original custody")
		hall.queue_free()
		await get_tree().process_frame
	PlayerState.active_profile_id = ""
	# A second non-item fault must reject the whole account before any repair.
	var invalid: Dictionary = documents.B.duplicate(true)
	invalid.gold = -1
	_setup_recovery_root(root + "_other_fault", {"B":invalid})
	path = PlayerState.profile_directory.path_join("B.json")
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and FileAccess.get_sha256(path) == original_sha, "other profile failure prevents item deletion and preserves source")
	# Even a known broken item cannot override an unknown outer version.
	invalid = documents.B.duplicate(true)
	invalid.save_version = 11
	_setup_recovery_root(root + "_future", {"B":invalid})
	path = PlayerState.profile_directory.path_join("B.json")
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and FileAccess.get_sha256(path) == original_sha, "future profile with broken relic remains untouched")
	# A future item owner must never fall back over a latest primary.
	var future_item := good.duplicate(true)
	future_item.relic_roll.contract_id = "equipment.relic_synthesis.v2"
	invalid = documents.B.duplicate(true)
	invalid.inventory = [future_item, broken]
	_setup_recovery_root(root + "_future_item", {"B":invalid})
	path = PlayerState.profile_directory.path_join("B.json")
	put(path + ".bak", old)
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and PlayerState.startup_save_upgrade_result.get("reason") == "unsupported_relic_roll_contract" and FileAccess.get_sha256(path) == original_sha, "future relic owner rejects partial repair and older valid backup")
	# All containers use the same pure planner, without changing good records.
	var tray: Array = [{},{},{},{},{},{},{},{},broken]
	var proposal := RelicRecovery.plan({"inventory":[good,broken], "equipment":{"徽章":broken}, "forge_tray":tray})
	check(bool(proposal.changed) and proposal.removed.size() == 3 and proposal.document.inventory == [good,{}] and proposal.document.equipment["徽章"].is_empty() and proposal.document.forge_tray.size() == 9 and proposal.document.forge_tray[8].is_empty(), "multiple known bad locations are isolated while normal positions and tray shape survive")
	# Duplicate normal ownership remains a fault, rather than a deletion guess.
	invalid = documents.B.duplicate(true)
	invalid.inventory = [good,good]
	_setup_recovery_root(root + "_duplicate", {"B":invalid})
	path = PlayerState.profile_directory.path_join("B.json")
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and FileAccess.get_sha256(path) == original_sha, "duplicate valid relics are not silently removed")
	# A broken shared relic uses the same aggregate preflight and writer.
	_setup_recovery_root(root + "_shared", {"A":documents.A})
	var shared: Dictionary = PlayerState._shared_warehouse_empty_document()
	shared.legacy_migration.completed = true
	shared.warehouse_inventory = [good,broken]
	put(PlayerState.shared_warehouse_path, shared)
	original_sha = FileAccess.get_sha256(PlayerState.shared_warehouse_path)
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(), "shared warehouse broken badge also uses validated recovery " + str(PlayerState.startup_save_upgrade_result))
	var shared_records: Array = PlayerState._shared_warehouse_read_inventory()
	check(FileAccess.get_sha256((root + "_shared").path_join("save_upgrades/framework_identity_v1/original/shared_warehouse.json")) == original_sha and shared_records.size() >= 1 and shared_records[0].get("instance_id") == good.instance_id and shared_records[0].get("relic_roll") == good.relic_roll and shared_records.slice(1).all(func(item: Dictionary): return item.is_empty()), "shared recovery retains raw before image and exact healthy position through canonical import")
	# Reject stale custody: a prior archive cannot authorize removal in newer
	# manual data when it does not contain the exact bytes being replaced.
	_setup_recovery_root(root + "_stale_custody", {"B":old})
	var backup := preload("res://scripts/save_upgrade_backup.gd").new()
	check(backup.prepare(root + "_stale_custody", PlayerState._startup_upgrade_sources()), "stale-custody fixture has genuine older archive")
	path = PlayerState.profile_directory.path_join("B.json")
	put(path, documents.B)
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and PlayerState.startup_save_upgrade_result.get("reason") == "relic_recovery_backup_mismatch" and FileAccess.get_sha256(path) == original_sha, "different archived bytes cannot authorize destructive repair")
	# A later bad sibling rejects all planned account repairs before any write.
	var bad_sibling: Dictionary = documents.C.duplicate(true)
	bad_sibling.gold = -1
	_setup_recovery_root(root + "_sibling", {"B":documents.B,"C":bad_sibling})
	path = PlayerState.profile_directory.path_join("B.json")
	original_sha = FileAccess.get_sha256(path)
	PlayerState.begin_startup_save_upgrade()
	check(not PlayerState.finish_startup_save_upgrade() and FileAccess.get_sha256(path) == original_sha, "another invalid role prevents otherwise valid relic repair from writing")
	# Plans are bound to the exact latest source, including external/manual edits.
	_setup_recovery_root(root + "_source_changed", {"B":documents.B})
	backup = preload("res://scripts/save_upgrade_backup.gd").new()
	check(backup.prepare(root + "_source_changed", PlayerState._startup_upgrade_sources()), "source-change fixture has genuine before-image custody")
	var preflight: Dictionary = PlayerState._startup_upgrade_preflight()
	check(bool(preflight.success) and preflight.relic_recoveries.size() == 1, "source-change test uses actual aggregate repair plan")
	path = PlayerState.profile_directory.path_join("B.json")
	var latest: Dictionary = documents.B.duplicate(true)
	latest.gold = 234567
	put(path, latest)
	original_sha = FileAccess.get_sha256(path)
	var refused: Dictionary = PlayerState._startup_apply_relic_recoveries(preflight.relic_recoveries, backup)
	check(not bool(refused.success) and refused.reason == "relic_recovery_source_changed" and FileAccess.get_sha256(path) == original_sha, "newer manual source after planning is never replaced")
	PlayerState.active_profile_id = ""

func _cold_recovery() -> void:
	PlayerState.test_mode = false
	var pointer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/save_recovery_v112_pointer.json"))
	check(pointer is Dictionary, "cold process receives actual recovered profile from previous native process")
	if pointer is Dictionary:
		var root: String = pointer.root
		var owner_prefix := ProjectSettings.globalize_path("res://.godot/runtime_appdata/")
		var producer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/mobile_save_upgrade_startup_test.result.json"))
		var bound: bool = root.begins_with(owner_prefix) and pointer.source_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256") and int(pointer.producer_pid) != OS.get_process_id()
		bound = bound and producer is Dictionary and producer.get("status") == "PASS" and producer.get("run_id") == pointer.producer_run_id and producer.get("source_content_sha256") == pointer.source_sha256
		check(bound, "cold fixture is checkout-owned and bound to a passing producer source/run/native process")
		if not bound:
			get_tree().quit(1)
			return
		put("res://outputs/test_logs/framework/save_recovery_cold_link.json", {"producer_run_id":pointer.producer_run_id, "consumer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "source_sha256":pointer.source_sha256, "producer_root":root})
		PlayerState.active_profile_id = ""
		PlayerState.profile_directory = root.path_join("characters")
		PlayerState.profile_index_path = root.path_join("character_profiles.json")
		PlayerState.shared_warehouse_path = root.path_join("shared_warehouse.json")
		PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
		PlayerState._shared_warehouse_initialized = false
		PlayerState.begin_startup_save_upgrade()
		check(PlayerState.finish_startup_save_upgrade(), "cold restart accepts recovered account through full startup owner")
		check((PlayerState.startup_save_upgrade_result.get("relic_recovery", []) as Array).is_empty(), "cold restart does not delete additional normal items")
		check(PlayerState.select_character("B") and PlayerState.gold == int(pointer.gold), "cold restart preserves latest progress and successful NPC purchase balance")
		check(PlayerState.equipment["hc.slot.badge"].get("instance_id") == pointer.good.instance_id and PlayerState.equipment["hc.slot.badge"].get("relic_roll") == pointer.good.relic_roll, "cold restart preserves repaired wizard equipment and exact healthy roll")
		check(PlayerState.has_item("hc.item.000080") and PlayerState._can_accept_immediate_item_use() and PlayerState.save_game(true, true, true), "cold recovered wizard keeps NPC goods and can still mutate and save")
		check(FileAccess.get_sha256(root.path_join("save_upgrades/framework_identity_v1/original/characters/B.json")) == pointer.archive_sha256, "cold restart retains original broken file custody unchanged")
		for id: String in ["A", "C"]:
			check(PlayerState.select_character(id) and PlayerState.gold == 123456, "cold recovered account keeps unaffected role " + id)
	PlayerState.active_profile_id = ""
	if not proof.write_receipt("mobile_save_upgrade_startup_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_MOBILE_SAVE_UPGRADE_STARTUP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup_recovery_root(root: String, documents: Dictionary) -> void:
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	var entries: Array = []
	for id: String in documents:
		put(PlayerState.profile_directory.path_join(id + ".json"), documents[id])
		entries.append({"id":id})
	put(PlayerState.profile_index_path, {"version":1,"profiles":entries})
