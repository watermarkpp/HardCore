extends Node

const StartupLoadingScript := preload("res://scripts/startup_loading.gd")
const FakeBrandIntroScript := preload("res://tests/startup_fake_brand_intro.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _assert_authoritative_data_failures()
	await _assert_real_authority_retry_semantics()
	await _assert_target_load_failures()
	await _assert_exit_action()
	await _assert_exit_blocks_pending_work()
	print("STARTUP_LOADING_FAILURE_RECOVERY_PASS: authority and target failures are visible, retryable, singleflight, and fail closed")
	get_tree().quit(0)


func _new_startup(first_frame_presented := true, animation_complete := true) -> StartupLoading:
	var startup: StartupLoading = StartupLoadingScript.new()
	startup.auto_start = false
	startup.suppress_scene_handoff_for_test = true
	startup.force_main_scene_prefetch_failure_for_test = true
	var intro: Control = FakeBrandIntroScript.new()
	intro.name = "BrandIntro"
	intro.first_frame_presented = first_frame_presented
	intro.animation_complete = animation_complete
	startup.add_child(intro)
	add_child(startup)
	await get_tree().process_frame
	return startup


func _assert_authoritative_data_failures() -> void:
	var steps := ["content_layers", "world_content", "presentation_assets", "game_data"]
	for step: String in steps:
		var startup: StartupLoading = await _new_startup()
		startup._target_scene = _packed_scene("AuthorityRetryTarget_%s" % step)
		startup._resource_ready = true
		startup._animation_finished = true
		startup.force_authoritative_data_failure_for_test = step
		startup._queue_authoritative_data_attempt()
		startup._queue_authoritative_data_attempt()
		assert(startup.startup_diagnostic().get("authoritative_data_attempt_count", 0) == 1, "%s duplicate deferred attempt was not coalesced" % step)
		await _wait_frames(2)
		var diagnostic: Dictionary = startup.startup_diagnostic()
		assert(
			diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_RECOVERABLE_FAILURE,
			"%s failure did not enter a recoverable startup state: %s" % [step, diagnostic],
		)
		assert(
			diagnostic.get("failure_code", "") == "STARTUP_DATA_%s_FAILED" % step.to_upper(),
			"%s failure code is not visible: %s" % [step, diagnostic],
		)
		assert(startup.failure_overlay.visible, "%s failure overlay is not visible" % step)
		assert(startup.failure_title_label.text == "启动失败")
		assert(startup.failure_code_label.text.contains(str(diagnostic.get("failure_code", ""))))
		assert(startup.failure_message_label.text.contains("重试"))
		var counts: Dictionary = diagnostic.get("authoritative_data_ensure_counts", {})
		assert(int(counts.get(step, 0)) == 1, "%s did not call its real authority boundary" % step)
		for later_step: String in steps:
			if steps.find(later_step) > steps.find(step):
				assert(int(counts.get(later_step, 0)) == 0, "%s failure ran past failed step %s" % [step, later_step])
		assert(not startup._target_prepare_started, "%s failure prepared a target before authority was ready" % step)

		# Clear only the test injection. The retry calls the same real ensure_loaded /
		# reload boundary again and may now complete the normal handoff.
		startup.force_authoritative_data_failure_for_test = ""
		startup.failure_retry_button.emit_signal("pressed")
		await _wait_for_handoff(startup)
		diagnostic = startup.startup_diagnostic()
		counts = diagnostic.get("authoritative_data_ensure_counts", {})
		assert(int(diagnostic.get("authoritative_data_attempt_count", 0)) == 2, "%s retry duplicated or skipped its attempt" % step)
		assert(int(counts.get(step, 0)) == 2, "%s retry did not re-attempt its authority boundary" % step)
		assert(bool(diagnostic.get("authoritative_data_ready", false)), "%s retry did not publish authority ready" % step)
		assert(int(diagnostic.get("target_handoff_count", 0)) == 1, "%s retry handed off more than once" % step)
		assert(is_instance_valid(startup._target_scene_instance), "%s retry did not prepare a target" % step)
		assert(not startup.failure_overlay.visible, "%s retry left the failure overlay visible" % step)
		startup.queue_free()
		await get_tree().process_frame


func _assert_real_authority_retry_semantics() -> void:
	# The startup failure injection above is deliberately after the real call so
	# it can cover every downstream boundary. Separately exercise each service's
	# real in-progress false-return path and then its normal second ensure call.
	var content_layers: Node = load("res://scripts/layers/runtime/content_layer_registry.gd").new()
	content_layers.initial_load_deferred = true
	add_child(content_layers)
	await get_tree().process_frame
	content_layers._initial_load_started = true
	assert(not content_layers.ensure_loaded(), "content layer real failure did not return false")
	content_layers._initial_load_started = false
	assert(content_layers.ensure_loaded(), "content layer did not retry its real boundary")
	content_layers.queue_free()
	await get_tree().process_frame

	var world_content: Node = load("res://scripts/layers/runtime/world_content_service.gd").new()
	world_content.initial_load_deferred = true
	add_child(world_content)
	await get_tree().process_frame
	world_content._initial_load_started = true
	assert(not world_content.ensure_loaded(), "world content real failure did not return false")
	world_content._initial_load_started = false
	assert(world_content.ensure_loaded(), "world content did not retry its real boundary")
	world_content.queue_free()
	await get_tree().process_frame

	var game_data: Node = load("res://scripts/game_data.gd").new()
	game_data.initial_load_deferred = true
	add_child(game_data)
	await get_tree().process_frame
	# This is the real in-progress guard in GameData.ensure_loaded(), not a
	# post-success result override. Clearing it lets the same call run normally.
	game_data._initial_load_started = true
	assert(not game_data.ensure_loaded(), "GameData in-progress guard did not return false")
	game_data._initial_load_started = false
	assert(game_data.ensure_loaded(), "GameData did not retry its real boundary")
	game_data.queue_free()
	await get_tree().process_frame


func _assert_target_load_failures() -> void:
	await _assert_target_failure("request", "STARTUP_TARGET_REQUEST_FAILED")
	await _assert_target_failure("invalid", "STARTUP_TARGET_THREAD_INVALID")
	await _assert_target_failure("null_scene", "STARTUP_TARGET_SCENE_NULL")
	await _assert_target_failure("null_instance", "STARTUP_TARGET_INSTANTIATE_NULL")


func _assert_target_failure(kind: String, expected_code: String) -> void:
	var startup: StartupLoading = await _new_startup()
	startup._authoritative_data_ready = true
	startup._animation_finished = true
	if kind == "request":
		startup.target_scene_loader_for_test = Callable(self, "_packed_scene").bind("RequestRetryTarget")
		startup.force_target_load_request_failure_for_test = true
		startup._begin_target_load()
	elif kind == "invalid":
		startup.target_load_request_mode_for_test = "accepted"
		startup.target_load_status_for_test = "invalid"
		startup._begin_target_load()
	elif kind == "null_scene":
		startup.target_load_request_mode_for_test = "accepted"
		startup.target_load_status_for_test = "loaded"
		startup.force_target_scene_null_for_test = true
		startup._begin_target_load()
	elif kind == "null_instance":
		startup._target_scene = _packed_scene("NullInstanceTarget")
		startup._resource_ready = true
		startup.force_target_scene_instantiate_failure_for_test = true
		startup._check_transition()
	await _wait_frames(3)
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(
		diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_RECOVERABLE_FAILURE,
		"%s target failure did not enter recovery state: %s" % [kind, diagnostic],
	)
	assert(diagnostic.get("failure_code", "") == expected_code, "%s target failure code mismatch: %s" % [kind, diagnostic])
	assert(startup.failure_overlay.visible, "%s target failure overlay is not visible" % kind)
	assert(startup.failure_retry_button.visible and startup.failure_exit_button.visible, "%s recovery actions missing" % kind)

	if kind == "request":
		startup.force_target_load_request_failure_for_test = false
		startup.failure_retry_button.emit_signal("pressed")
		await _wait_for_handoff(startup)
		diagnostic = startup.startup_diagnostic()
		assert(int(diagnostic.get("target_load_attempt_count", 0)) == 2, "request retry did not create one new target attempt")
		assert(int(diagnostic.get("target_handoff_count", 0)) == 1, "request retry did not hand off exactly once")
		startup.failure_retry_button.emit_signal("pressed")
		await _wait_frames(2)
		assert(int(startup.startup_diagnostic().get("target_handoff_count", 0)) == 1, "duplicate retry repeated handoff")
	startup.queue_free()
	await get_tree().process_frame


func _assert_exit_action() -> void:
	var startup: StartupLoading = await _new_startup()
	startup.suppress_exit_for_test = true
	startup._show_failure(
		"STARTUP_TARGET_THREAD_INVALID",
		"角色选择场景异步请求无效，请重试。",
		StartupLoading.FAILURE_RETRY_TARGET,
	)
	startup.failure_exit_button.emit_signal("pressed")
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_EXITING, "exit did not enter terminal state")
	assert(bool(diagnostic.get("exit_requested", false)), "exit action did not publish an exit request")
	assert(startup.failure_overlay.visible, "exit action removed the visible failure context")
	assert(startup.failure_retry_button.disabled and startup.failure_exit_button.disabled, "exit action left retry controls active")
	startup.queue_free()
	await get_tree().process_frame


func _assert_exit_blocks_pending_work() -> void:
	await _assert_exit_blocks_pending_authority()
	await _assert_exit_blocks_pending_target_load()
	await _assert_exit_blocks_pending_prepare()
	await _assert_exit_blocks_pending_reveal()


func _assert_exit_blocks_pending_authority() -> void:
	var startup: StartupLoading = await _new_startup(false)
	startup.suppress_exit_for_test = true
	startup._queue_authoritative_data_attempt()
	await get_tree().process_frame
	assert(startup._authoritative_data_attempt_in_progress, "authority pending fixture did not suspend at intro boundary")
	startup._show_failure(
		"STARTUP_DATA_CONTENT_LAYERS_FAILED",
		"权威内容层未准备完成，请检查安装后重试。",
		StartupLoading.FAILURE_RETRY_AUTHORITY,
	)
	startup.failure_exit_button.emit_signal("pressed")
	var intro := startup.brand_intro
	intro.first_frame_presented = true
	intro.intro_first_frame_presented.emit()
	await _wait_frames(3)
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_EXITING, "pending authority completion escaped exit terminal state")
	assert(not bool(diagnostic.get("authoritative_data_ready", false)), "pending authority completion published ready after exit")
	assert(int(diagnostic.get("target_handoff_count", 0)) == 0, "pending authority completion handed off after exit")
	assert(startup.failure_overlay.visible, "exit removed pending authority failure context")
	startup.queue_free()
	await get_tree().process_frame


func _assert_exit_blocks_pending_target_load() -> void:
	var startup: StartupLoading = await _new_startup()
	startup.suppress_exit_for_test = true
	startup._authoritative_data_ready = true
	startup.target_load_request_mode_for_test = "accepted"
	startup.target_load_status_for_test = "loading"
	startup._begin_target_load()
	var generation := startup._target_load_generation
	assert(startup._load_requested, "target pending fixture did not retain its accepted request")
	# Start the real deferred fallback continuation too; both it and the
	# threaded status poll must be invalidated by exit.
	startup._recover_target_load(ERR_CANT_OPEN, generation)
	startup._target_load_failed = true
	startup._target_failure_code = "STARTUP_TARGET_THREAD_INVALID"
	startup._target_failure_message = "角色选择场景异步请求无效，请重试。"
	startup._show_failure(
		"STARTUP_TARGET_THREAD_INVALID",
		"角色选择场景异步请求无效，请重试。",
		StartupLoading.FAILURE_RETRY_TARGET,
	)
	startup.failure_exit_button.emit_signal("pressed")
	startup.target_load_status_for_test = "loaded"
	await _wait_frames(3)
	startup._check_transition()
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_EXITING, "pending target completion escaped exit terminal state")
	assert(int(diagnostic.get("target_load_generation", 0)) > generation, "exit did not invalidate target generation")
	assert(int(diagnostic.get("target_handoff_count", 0)) == 0, "pending target completion handed off after exit")
	assert(startup.failure_overlay.visible, "exit removed pending target failure context")
	startup.queue_free()
	await get_tree().process_frame


func _assert_exit_blocks_pending_prepare() -> void:
	var startup: StartupLoading = await _new_startup()
	startup.suppress_exit_for_test = true
	startup._authoritative_data_ready = true
	startup._animation_finished = true
	startup._target_scene = _packed_scene("ExitPendingPrepareTarget")
	startup._resource_ready = true
	startup._target_prepare_started = true
	startup._prepare_target_scene(startup._target_load_generation)
	assert(is_instance_valid(startup._target_scene_instance), "target prepare fixture did not reach its settle await")
	startup._show_failure(
		"STARTUP_TARGET_INSTANTIATE_NULL",
		"角色选择场景实例化失败，请重试。",
		StartupLoading.FAILURE_RETRY_TARGET,
	)
	startup.failure_exit_button.emit_signal("pressed")
	await _wait_frames(4)
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_EXITING, "pending prepare completion escaped exit terminal state")
	assert(not startup._target_scene_ready, "pending prepare completion published ready after exit")
	assert(int(diagnostic.get("target_handoff_count", 0)) == 0, "pending prepare completion handed off after exit")
	assert(startup.failure_overlay.visible, "exit removed pending prepare failure context")
	if is_instance_valid(startup._target_scene_instance):
		startup._target_scene_instance.queue_free()
	startup.queue_free()
	await get_tree().process_frame


func _assert_exit_blocks_pending_reveal() -> void:
	var startup: StartupLoading = await _new_startup()
	startup.suppress_exit_for_test = true
	var packed_target := _packed_scene("ExitPendingRevealTarget")
	startup._target_scene_instance = packed_target.instantiate()
	assert(is_instance_valid(startup._target_scene_instance), "reveal fixture target instance creation failed")
	(startup._target_scene_instance as CanvasItem).visible = false
	startup._target_scene_ready = true
	startup._transition_started = true
	var generation := startup._target_load_generation
	startup._reveal_target_scene.call_deferred(generation)
	startup._show_failure(
		"STARTUP_TARGET_THREAD_INVALID",
		"角色选择场景异步请求无效，请重试。",
		StartupLoading.FAILURE_RETRY_TARGET,
	)
	startup.failure_exit_button.emit_signal("pressed")
	await _wait_frames(3)
	var diagnostic: Dictionary = startup.startup_diagnostic()
	assert(diagnostic.get("state", "") == StartupLoading.STARTUP_STATE_EXITING, "pending reveal escaped exit terminal state")
	assert(int(diagnostic.get("target_handoff_count", 0)) == 0, "pending reveal handed off after exit")
	assert(not (startup._target_scene_instance as CanvasItem).visible, "pending reveal made target visible after exit")
	if is_instance_valid(startup._target_scene_instance):
		startup._target_scene_instance.free()
	startup.queue_free()
	await get_tree().process_frame


func _wait_for_handoff(startup: StartupLoading) -> void:
	for _index in range(12):
		if int(startup.startup_diagnostic().get("target_handoff_count", 0)) == 1:
			return
		await get_tree().process_frame
	assert(int(startup.startup_diagnostic().get("target_handoff_count", 0)) == 1, "startup handoff did not complete")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _packed_scene(node_name: String) -> PackedScene:
	var packed := PackedScene.new()
	var control := Control.new()
	control.name = node_name
	assert(packed.pack(control) == OK, "failed to create test target scene")
	control.free()
	return packed
