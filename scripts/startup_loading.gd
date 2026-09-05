class_name StartupLoading
extends Control

const TARGET_SCENE_PATH := "res://scenes/character_select.tscn"
const MAIN_SCENE_PREFETCH_PATH := "res://scenes/main.tscn"
const LOADING_CONTRACT_ID := "startup.loading.character_select.v1"
const MAIN_SCENE_PREFETCH_CONTRACT_ID := "startup.loading.main_scene_prefetch.v1"
const STARTUP_STATE_LOADING := "loading"
const STARTUP_STATE_READY_TO_HANDOFF := "ready_to_handoff"
const STARTUP_STATE_RECOVERABLE_FAILURE := "recoverable_failure"
const STARTUP_STATE_UNRECOVERABLE_FAILURE := "unrecoverable_failure"
const STARTUP_STATE_EXITING := "exiting"
const FAILURE_RETRY_AUTHORITY := "authoritative_data"
const FAILURE_RETRY_TARGET := "target_scene"

@export var auto_start := true
@onready var brand_intro: Control = $BrandIntro

var _target_scene: PackedScene
var _resource_ready := false
var _authoritative_data_ready := false
var _authoritative_data_failed := false
var _animation_finished := false
var _transition_started := false
var _target_prepare_started := false
var _target_scene_ready := false
var _load_requested := false
var _target_scene_instance: Node
@export var suppress_scene_handoff_for_test := false
## Test-only failure injection. It never changes the target-scene handoff
## contract and is kept here so the prefetch failure path can be exercised
## without changing the production scene path or ResourceLoader state.
@export var force_main_scene_prefetch_failure_for_test := false

## These non-exported hooks are test-only. They keep failure injection at the
## startup boundary without modifying autoload ownership or production data.
var force_authoritative_data_failure_for_test := ""
var force_target_load_request_failure_for_test := false
var force_target_scene_null_for_test := false
var force_target_scene_instantiate_failure_for_test := false
var target_load_request_mode_for_test := ""
var target_load_status_for_test := ""
var target_scene_loader_for_test: Callable
var target_scene_path_for_test := ""
var suppress_exit_for_test := false

var failure_overlay: Control
var failure_title_label: Label
var failure_code_label: Label
var failure_message_label: Label
var failure_retry_button: Button
var failure_exit_button: Button

var _main_scene_prefetch_attempted := false
var _main_scene_prefetch_accepted := false
var _main_scene_prefetch_already_cached := false
var _main_scene_prefetch_status := "not_started"
var _main_scene_prefetch_request_count := 0

var _startup_state := STARTUP_STATE_LOADING
var _failure_code := ""
var _failure_message := ""
var _failure_retry_kind := ""
var _exit_requested := false
var _authoritative_data_step := ""
var _authoritative_failure_code := ""
var _authoritative_failure_text := ""
var _authoritative_data_attempt_generation := 0
var _authoritative_data_attempt_in_progress := false
var _authoritative_data_attempt_count := 0
var _authoritative_data_ensure_counts: Dictionary = {}
var _authoritative_data_failure_injected := false
var _target_load_generation := 0
var _target_load_attempt_in_progress := false
var _target_load_attempt_count := 0
var _target_load_failed := false
var _target_failure_code := ""
var _target_failure_message := ""
var _target_handoff_count := 0
var _target_request_failure_injected := false


func _ready() -> void:
	_build_failure_overlay()
	if not auto_start:
		return
	# The authored intro plays independently while character selection loads.
	# If loading takes longer, BrandIntro remains on its completed final frame.
	_run_finite_loading_phase.call_deferred()
	_begin_target_load()
	_queue_authoritative_data_attempt()


func _queue_authoritative_data_attempt() -> void:
	if _startup_state == STARTUP_STATE_EXITING or _authoritative_data_attempt_in_progress:
		return
	_authoritative_data_attempt_generation += 1
	_authoritative_data_attempt_in_progress = true
	_authoritative_data_attempt_count += 1
	_authoritative_data_failed = false
	_authoritative_data_ready = false
	_authoritative_data_step = ""
	_authoritative_failure_code = ""
	_authoritative_failure_text = ""
	if not _target_load_failed:
		_clear_failure()
	_prepare_authoritative_data.call_deferred(_authoritative_data_attempt_generation)


func _prepare_authoritative_data(attempt_generation: int) -> void:
	if attempt_generation != _authoritative_data_attempt_generation:
		return
	# The autoloads deliberately stay cold on Android. Wait for a real authored
	# CG frame, then perform their finite synchronous work while the CG continues.
	if brand_intro == null:
		_finish_authoritative_data_attempt(attempt_generation, false, "intro_missing")
		return
	if not bool(brand_intro.get("first_frame_presented")):
		await brand_intro.intro_first_frame_presented
	if attempt_generation != _authoritative_data_attempt_generation:
		return
	if not is_inside_tree():
		_authoritative_data_attempt_in_progress = false
		return
	var success := _ensure_authoritative_step("content_layers")
	if success:
		success = _ensure_authoritative_step("world_content")
	if success:
		success = _ensure_authoritative_step("presentation_assets")
	if success:
		success = _ensure_authoritative_step("game_data")
	if not success:
		_finish_authoritative_data_attempt(attempt_generation, false, _authoritative_data_step)
		return
	_finish_authoritative_data_attempt(attempt_generation, true, "")


func _ensure_authoritative_step(step_id: String) -> bool:
	_authoritative_data_step = step_id
	_authoritative_data_ensure_counts[step_id] = int(_authoritative_data_ensure_counts.get(step_id, 0)) + 1
	var success := false
	match step_id:
		"content_layers":
			success = ContentLayers.ensure_loaded()
		"world_content":
			success = WorldContent.ensure_loaded()
		"presentation_assets":
			success = PresentationAssets.reload_skin()
		"game_data":
			success = GameData.ensure_loaded()
	if (
		force_authoritative_data_failure_for_test == step_id
		and not _authoritative_data_failure_injected
	):
		# The real ensure_loaded/reload call above still runs. The one-shot failure
		# only makes its result fail closed so a following retry can prove that the
		# same authoritative boundary is attempted again.
		_authoritative_data_failure_injected = true
		return false
	return success


func _finish_authoritative_data_attempt(
	attempt_generation: int,
	success: bool,
	failure_step: String,
) -> void:
	if attempt_generation != _authoritative_data_attempt_generation:
		return
	_authoritative_data_attempt_in_progress = false
	_authoritative_data_ready = success
	_authoritative_data_failed = not success
	if not success:
		var code := "STARTUP_DATA_%s_FAILED" % failure_step.to_upper()
		var message := _authoritative_failure_message(failure_step)
		_authoritative_failure_code = code
		_authoritative_failure_text = message
		print("STARTUP_FAILURE %s: %s" % [code, message])
		_show_failure(code, message, FAILURE_RETRY_AUTHORITY)
		return
	_authoritative_failure_code = ""
	_authoritative_failure_text = ""
	_check_transition()


func _authoritative_failure_message(step_id: String) -> String:
	match step_id:
		"content_layers":
			return "权威内容层未准备完成，请检查安装后重试。"
		"world_content":
			return "权威世界数据未准备完成，请检查安装后重试。"
		"presentation_assets":
			return "正式表现资源未准备完成，请检查安装后重试。"
		"game_data":
			return "正式游戏数据未准备完成，请检查安装后重试。"
		"intro_missing":
			return "启动画面初始化失败，请退出并重新启动。"
	return "启动权威数据准备失败，请检查安装后重试。"


func _build_failure_overlay() -> void:
	if failure_overlay != null:
		return
	failure_overlay = Control.new()
	failure_overlay.name = "StartupFailureOverlay"
	failure_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	failure_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	failure_overlay.z_index = 1000
	add_child(failure_overlay)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.012, 0.018, 0.98)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	failure_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "MessagePanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_top = -150.0
	panel.offset_right = 300.0
	panel.offset_bottom = 150.0
	failure_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	failure_title_label = Label.new()
	failure_title_label.text = "启动失败"
	failure_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_title_label.add_theme_font_size_override("font_size", 28)
	column.add_child(failure_title_label)
	failure_code_label = Label.new()
	failure_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_code_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.38))
	column.add_child(failure_code_label)
	failure_message_label = Label.new()
	failure_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	failure_message_label.custom_minimum_size = Vector2(0.0, 58.0)
	column.add_child(failure_message_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	failure_retry_button = Button.new()
	failure_retry_button.name = "RetryButton"
	failure_retry_button.text = "重试"
	failure_retry_button.custom_minimum_size = Vector2(150.0, 48.0)
	failure_retry_button.pressed.connect(_on_failure_retry_pressed)
	buttons.add_child(failure_retry_button)
	failure_exit_button = Button.new()
	failure_exit_button.name = "ExitButton"
	failure_exit_button.text = "退出"
	failure_exit_button.custom_minimum_size = Vector2(150.0, 48.0)
	failure_exit_button.pressed.connect(_on_failure_exit_pressed)
	buttons.add_child(failure_exit_button)

	failure_overlay.visible = false


func _show_failure(code: String, message: String, retry_kind: String) -> void:
	_failure_code = code
	_failure_message = message
	_failure_retry_kind = retry_kind
	_startup_state = (
		STARTUP_STATE_RECOVERABLE_FAILURE
		if not retry_kind.is_empty()
		else STARTUP_STATE_UNRECOVERABLE_FAILURE
	)
	if failure_overlay == null:
		return
	failure_code_label.text = "错误码：%s" % code
	failure_message_label.text = message
	failure_retry_button.visible = not retry_kind.is_empty()
	failure_retry_button.disabled = false
	failure_exit_button.disabled = false
	failure_overlay.visible = true


func _clear_failure() -> void:
	_failure_code = ""
	_failure_message = ""
	_failure_retry_kind = ""
	if failure_overlay != null:
		failure_overlay.visible = false
		failure_retry_button.disabled = false
		failure_exit_button.disabled = false
	_startup_state = STARTUP_STATE_LOADING


func _on_failure_retry_pressed() -> void:
	if _startup_state != STARTUP_STATE_RECOVERABLE_FAILURE:
		return
	if _failure_retry_kind == FAILURE_RETRY_AUTHORITY:
		_queue_authoritative_data_attempt()
	elif _failure_retry_kind == FAILURE_RETRY_TARGET:
		_retry_target_load()


func _on_failure_exit_pressed() -> void:
	if _startup_state == STARTUP_STATE_EXITING:
		return
	_exit_requested = true
	_startup_state = STARTUP_STATE_EXITING
	# Invalidate every deferred/await continuation. This keeps a late loader,
	# data boundary, preparation settle, or reveal callback from reopening the
	# overlay or handing off after the user selected exit.
	_authoritative_data_attempt_generation += 1
	_authoritative_data_attempt_in_progress = false
	_target_load_generation += 1
	_target_load_attempt_in_progress = false
	_load_requested = false
	_target_prepare_started = false
	_transition_started = false
	if failure_retry_button != null:
		failure_retry_button.disabled = true
	if failure_exit_button != null:
		failure_exit_button.disabled = true
	if not suppress_exit_for_test:
		get_tree().quit(0)


func startup_diagnostic() -> Dictionary:
	return {
		"contract_id": LOADING_CONTRACT_ID,
		"state": _startup_state,
		"failure_code": _failure_code,
		"failure_message": _failure_message,
		"failure_retry_kind": _failure_retry_kind,
		"exit_requested": _exit_requested,
		"authoritative_data_ready": _authoritative_data_ready,
		"authoritative_data_failed": _authoritative_data_failed,
		"authoritative_data_step": _authoritative_data_step,
		"authoritative_failure_code": _authoritative_failure_code,
		"authoritative_data_attempt_count": _authoritative_data_attempt_count,
		"authoritative_data_ensure_counts": _authoritative_data_ensure_counts.duplicate(true),
		"target_load_attempt_count": _target_load_attempt_count,
		"target_load_generation": _target_load_generation,
		"target_load_failed": _target_load_failed,
		"target_handoff_count": _target_handoff_count,
	}


func _begin_target_load() -> void:
	if _startup_state == STARTUP_STATE_EXITING:
		return
	_target_load_generation += 1
	_target_load_attempt_count += 1
	_target_load_attempt_in_progress = true
	_target_load_failed = false
	_target_failure_code = ""
	_target_failure_message = ""
	_target_scene = null
	_resource_ready = false
	_load_requested = false
	_target_scene_ready = false
	_target_prepare_started = false
	_transition_started = false
	if is_instance_valid(_target_scene_instance):
		_target_scene_instance.queue_free()
	_target_scene_instance = null
	var generation := _target_load_generation
	if force_target_load_request_failure_for_test and not _target_request_failure_injected:
		_target_request_failure_injected = true
		_target_load_attempt_in_progress = false
		_fail_target_load(
			"STARTUP_TARGET_REQUEST_FAILED",
			"角色选择场景请求失败，请重试。",
			generation,
		)
		return
	if target_load_request_mode_for_test == "accepted":
		_load_requested = true
		return
	if target_scene_loader_for_test.is_valid():
		_target_scene = target_scene_loader_for_test.call() as PackedScene
		_resource_ready = _target_scene != null
		_target_load_attempt_in_progress = false
		if not _resource_ready:
			_fail_target_load(
				"STARTUP_TARGET_SCENE_NULL",
				"角色选择场景为空，请重试。",
				generation,
			)
			return
		_check_transition()
		return
	var target_path := _target_scene_path()
	# A scene that survived in Godot's resource cache must not be submitted as a
	# second threaded request. That request can be rejected even though the
	# resource is already usable, which used to leave the intro waiting forever.
	if ResourceLoader.has_cached(target_path):
		_target_scene = ResourceLoader.load(target_path) as PackedScene
		_resource_ready = _target_scene != null
		_target_load_attempt_in_progress = false
		if not _resource_ready:
			_fail_target_load(
				"STARTUP_TARGET_SCENE_NULL",
				"角色选择场景为空，请重试。",
				generation,
			)
			return
		_check_transition()
		return
	var request_error := ResourceLoader.load_threaded_request(target_path)
	_load_requested = request_error == OK or request_error == ERR_BUSY
	_target_load_attempt_in_progress = _load_requested
	if not _load_requested:
		# Keep the first authored frame on screen before the rare synchronous
		# recovery path. A cached/restarted launch must always remain able to reach
		# character selection.
		_recover_target_load.call_deferred(request_error, generation)


func _retry_target_load() -> void:
	if _startup_state == STARTUP_STATE_EXITING or _target_load_attempt_in_progress:
		return
	if _failure_retry_kind == FAILURE_RETRY_TARGET:
		_clear_failure()
	_begin_target_load()


func _target_scene_path() -> String:
	return target_scene_path_for_test if not target_scene_path_for_test.is_empty() else TARGET_SCENE_PATH


func _recover_target_load(request_error: Error, generation: int) -> void:
	await get_tree().process_frame
	if generation != _target_load_generation or not is_inside_tree() or _resource_ready:
		return
	_target_scene = ResourceLoader.load(_target_scene_path()) as PackedScene
	_resource_ready = _target_scene != null
	_target_load_attempt_in_progress = false
	if not _resource_ready:
		_fail_target_load(
			"STARTUP_TARGET_SYNC_LOAD_FAILED",
			"角色选择场景加载失败（%s），请重试。" % request_error,
			generation,
		)
		return
	_check_transition()


func _process(_delta: float) -> void:
	if _startup_state == STARTUP_STATE_EXITING:
		return
	_poll_main_scene_prefetch()
	if not _load_requested or _resource_ready:
		return
	var progress: Array[float] = []
	var status: int = _target_load_status(progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_load_requested = false
		_target_load_attempt_in_progress = false
		_target_scene = _target_threaded_get()
		_resource_ready = _target_scene != null
		if not _resource_ready:
			_fail_target_load(
				"STARTUP_TARGET_SCENE_NULL",
				"角色选择场景返回为空，请重试。",
				_target_load_generation,
			)
			return
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_load_requested = false
		_target_load_attempt_in_progress = false
		_fail_target_load(
			"STARTUP_TARGET_THREAD_FAILED",
			"角色选择场景异步加载失败，请重试。",
			_target_load_generation,
		)
		return
	elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_load_requested = false
		_target_load_attempt_in_progress = false
		_fail_target_load(
			"STARTUP_TARGET_THREAD_INVALID",
			"角色选择场景异步请求无效，请重试。",
			_target_load_generation,
		)
		return
	_check_transition()


func _target_load_status(progress: Array[float]):
	match target_load_status_for_test:
		"loaded":
			return ResourceLoader.THREAD_LOAD_LOADED
		"failed":
			return ResourceLoader.THREAD_LOAD_FAILED
		"invalid":
			return ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	return ResourceLoader.load_threaded_get_status(_target_scene_path(), progress)


func _target_threaded_get() -> PackedScene:
	if force_target_scene_null_for_test:
		return null
	return ResourceLoader.load_threaded_get(_target_scene_path()) as PackedScene


func _fail_target_load(code: String, message: String, generation: int) -> void:
	if generation != _target_load_generation:
		return
	_load_requested = false
	_target_load_attempt_in_progress = false
	_target_load_failed = true
	_target_failure_code = code
	_target_failure_message = message
	_target_scene_ready = false
	_target_prepare_started = false
	print("STARTUP_FAILURE %s: %s" % [code, message])
	_show_failure(code, message, FAILURE_RETRY_TARGET)


func _poll_main_scene_prefetch() -> void:
	if not _main_scene_prefetch_attempted or not _main_scene_prefetch_accepted:
		return
	if _main_scene_prefetch_status in ["ready", "failed"]:
		return
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PREFETCH_PATH)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_main_scene_prefetch_status = "ready"
	elif status in [
		ResourceLoader.THREAD_LOAD_FAILED,
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
	]:
		_main_scene_prefetch_status = "failed"
	else:
		_main_scene_prefetch_status = "loading"


func main_scene_prefetch_diagnostic() -> Dictionary:
	return {
		"contract_id": MAIN_SCENE_PREFETCH_CONTRACT_ID,
		"attempted": _main_scene_prefetch_attempted,
		"accepted": _main_scene_prefetch_accepted,
		"already_cached": _main_scene_prefetch_already_cached,
		"status": _main_scene_prefetch_status,
		"request_count": _main_scene_prefetch_request_count,
	}


func _run_finite_loading_phase() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if brand_intro == null:
		# A malformed startup scene must still leave the failure overlay in control;
		# do not dereference the missing authored intro while reporting that fault.
		_animation_finished = true
		_check_transition()
		return
	if not bool(brand_intro.get("animation_complete")):
		await brand_intro.intro_animation_finished
	if not is_inside_tree():
		return
	_animation_finished = true
	_check_transition()


func _check_transition() -> void:
	if _startup_state == STARTUP_STATE_EXITING:
		return
	if _startup_state in [STARTUP_STATE_RECOVERABLE_FAILURE, STARTUP_STATE_UNRECOVERABLE_FAILURE]:
		if _target_load_failed and _failure_retry_kind != FAILURE_RETRY_TARGET:
			_show_failure(_target_failure_code, _target_failure_message, FAILURE_RETRY_TARGET)
		return
	if _target_load_failed and not _resource_ready:
		_show_failure(_target_failure_code, _target_failure_message, FAILURE_RETRY_TARGET)
		return
	if _authoritative_data_failed or not _authoritative_data_ready:
		if _failure_retry_kind != FAILURE_RETRY_AUTHORITY and not _authoritative_failure_code.is_empty():
			_show_failure(
				_authoritative_failure_code,
				_authoritative_failure_text,
				FAILURE_RETRY_AUTHORITY,
			)
		return
	# Once the character hall PackedScene and authoritative data are ready, use
	# the remaining authored Logo/CG time to warm the eventual main scene. This
	# is intentionally fire-and-forget: no await, instantiate, HUD, world, or
	# transition state is touched by the prefetch itself.
	if (
		not _main_scene_prefetch_attempted
		and _resource_ready
		and _authoritative_data_ready
	):
		_begin_main_scene_prefetch()
	# Let the authored CG complete at its intended speed. Character-selection
	# construction is intentionally delayed until then; its expensive _ready()
	# work may block Android's main thread, so the already-rendered final CG frame
	# remains visible as the loading surface instead of freezing the intro near
	# its first semi-transparent logo frame.
	if not _target_prepare_started and _resource_ready and _authoritative_data_ready and _animation_finished:
		_target_prepare_started = true
		_prepare_target_scene.call_deferred(_target_load_generation)
	if _transition_started or not _target_scene_ready:
		return
	_startup_state = STARTUP_STATE_READY_TO_HANDOFF
	_transition_started = true
	_reveal_target_scene.call_deferred(_target_load_generation)


func _begin_main_scene_prefetch() -> void:
	_main_scene_prefetch_attempted = true
	if force_main_scene_prefetch_failure_for_test:
		_main_scene_prefetch_status = "failed"
		return
	if ResourceLoader.has_cached(MAIN_SCENE_PREFETCH_PATH):
		_main_scene_prefetch_accepted = true
		_main_scene_prefetch_already_cached = true
		_main_scene_prefetch_status = "already_cached"
		return
	var existing_status := ResourceLoader.load_threaded_get_status(
		MAIN_SCENE_PREFETCH_PATH
	)
	if existing_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# CharacterSelect or another startup instance already owns the global
		# request. Reuse it; do not submit a second request.
		_main_scene_prefetch_accepted = true
		_main_scene_prefetch_status = "already_requested"
		return
	if existing_status == ResourceLoader.THREAD_LOAD_LOADED:
		_main_scene_prefetch_accepted = true
		_main_scene_prefetch_status = "ready"
		return
	var request_error := ResourceLoader.load_threaded_request(
		MAIN_SCENE_PREFETCH_PATH,
		"PackedScene"
	)
	_main_scene_prefetch_request_count = 1
	if request_error == OK:
		_main_scene_prefetch_accepted = true
		_main_scene_prefetch_status = "accepted"
	elif request_error == ERR_BUSY:
		# A request can become visible between the status probe and submission.
		# Treat that race as reuse, not as a startup failure.
		_main_scene_prefetch_accepted = true
		_main_scene_prefetch_status = "already_requested"
	else:
		# Main-scene prefetch is an optimization only. CharacterSelect remains
		# responsible for its own bounded retry and handoff.
		_main_scene_prefetch_status = "failed"


func _prepare_target_scene(generation: int) -> void:
	if generation != _target_load_generation:
		return
	if not is_inside_tree():
		_target_prepare_started = false
		return
	if _target_scene == null:
		_fail_target_load(
			"STARTUP_TARGET_SCENE_NULL",
			"角色选择场景为空，请重试。",
			generation,
		)
		return
	_target_scene_instance = (
		null
		if force_target_scene_instantiate_failure_for_test
		else _target_scene.instantiate()
	)
	if _target_scene_instance == null:
		_fail_target_load(
			"STARTUP_TARGET_INSTANTIATE_NULL",
			"角色选择场景实例化失败，请重试。",
			generation,
		)
		return
	# Build and settle the next UI behind the completed intro. PackedScene
	# instantiation and _ready() may be expensive on Android, but the already
	# rendered final intro frame remains visible during that synchronous work.
	# change_scene_to_packed() removed the intro first and exposed a black frame.
	if _target_scene_instance is CanvasItem:
		(_target_scene_instance as CanvasItem).visible = false
	get_tree().root.add_child(_target_scene_instance)
	await get_tree().process_frame
	await get_tree().process_frame
	if (
		generation != _target_load_generation
		or _startup_state == STARTUP_STATE_EXITING
		or not is_inside_tree()
		or not is_instance_valid(_target_scene_instance)
	):
		if generation != _target_load_generation or _startup_state == STARTUP_STATE_EXITING:
			return
		_fail_target_load(
			"STARTUP_TARGET_INSTANCE_INVALID",
			"角色选择场景实例已失效，请重试。",
			generation,
		)
		return
	_target_scene_ready = true
	_check_transition()


func _reveal_target_scene(generation: int) -> void:
	if _startup_state == STARTUP_STATE_EXITING or generation != _target_load_generation:
		return
	if not is_inside_tree() or not _target_scene_ready or not is_instance_valid(_target_scene_instance):
		_transition_started = false
		_fail_target_load(
			"STARTUP_TARGET_INSTANCE_INVALID",
			"角色选择场景实例已失效，请重试。",
			generation,
		)
		return
	if _target_scene_instance is CanvasItem:
		(_target_scene_instance as CanvasItem).visible = true
	if suppress_scene_handoff_for_test:
		_target_handoff_count += 1
		return
	get_tree().current_scene = _target_scene_instance
	_target_handoff_count += 1
	queue_free()
