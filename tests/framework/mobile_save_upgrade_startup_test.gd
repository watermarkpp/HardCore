extends Node

const Startup := preload("res://scripts/startup_loading.gd")
const FakeIntro := preload("res://tests/startup_fake_brand_intro.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
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
	check(PlayerState.list_characters().size() == 1, "real CharacterSelect sees upgraded profile")
	check(PlayerState.select_character("A") and PlayerState.gold == 98765 and PlayerState.experience == 123, "real destination can load retained progress")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0, "startup writes and accepted receipts ended before gameplay")
	PlayerState.active_profile_id = ""
	startup.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("mobile_save_upgrade_startup_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_MOBILE_SAVE_UPGRADE_STARTUP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
