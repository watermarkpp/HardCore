class_name StartupLoading
extends Control

const TARGET_SCENE_PATH := "res://scenes/character_select.tscn"
const MAIN_SCENE_PREFETCH_PATH := "res://scenes/main.tscn"
const LOADING_CONTRACT_ID := "startup.loading.character_select.v1"
const MAIN_SCENE_PREFETCH_CONTRACT_ID := "startup.loading.main_scene_prefetch.v1"

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

var _main_scene_prefetch_attempted := false
var _main_scene_prefetch_accepted := false
var _main_scene_prefetch_already_cached := false
var _main_scene_prefetch_status := "not_started"
var _main_scene_prefetch_request_count := 0


func _ready() -> void:
	if not auto_start:
		return
	# The authored intro plays independently while character selection loads.
	# If loading takes longer, BrandIntro remains on its completed final frame.
	_run_finite_loading_phase.call_deferred()
	_begin_target_load()
	_prepare_authoritative_data.call_deferred()


func _prepare_authoritative_data() -> void:
	# The autoloads deliberately stay cold on Android. Wait for a real authored
	# CG frame, then perform their finite synchronous work while the CG continues.
	if not bool(brand_intro.get("first_frame_presented")):
		await brand_intro.intro_first_frame_presented
	if not is_inside_tree():
		return
	var success := ContentLayers.ensure_loaded()
	if success:
		success = WorldContent.ensure_loaded()
	if success:
		success = PresentationAssets.reload_skin()
	if success:
		success = GameData.ensure_loaded()
	_authoritative_data_ready = success
	_authoritative_data_failed = not success
	if not success:
		push_error("startup authoritative data preparation failed")
	_check_transition()


func _begin_target_load() -> void:
	# A scene that survived in Godot's resource cache must not be submitted as a
	# second threaded request. That request can be rejected even though the
	# resource is already usable, which used to leave the intro waiting forever.
	if ResourceLoader.has_cached(TARGET_SCENE_PATH):
		_target_scene = ResourceLoader.load(TARGET_SCENE_PATH) as PackedScene
		_resource_ready = _target_scene != null
		_check_transition()
		return
	var request_error := ResourceLoader.load_threaded_request(TARGET_SCENE_PATH)
	_load_requested = request_error == OK or request_error == ERR_BUSY
	if not _load_requested:
		# Keep the first authored frame on screen before the rare synchronous
		# recovery path. A cached/restarted launch must always remain able to reach
		# character selection.
		_recover_target_load.call_deferred(request_error)


func _recover_target_load(request_error: Error) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or _resource_ready:
		return
	_target_scene = ResourceLoader.load(TARGET_SCENE_PATH) as PackedScene
	_resource_ready = _target_scene != null
	if not _resource_ready:
		push_error("startup loading request failed (%s): %s" % [request_error, TARGET_SCENE_PATH])
	_check_transition()


func _process(_delta: float) -> void:
	_poll_main_scene_prefetch()
	if not _load_requested or _resource_ready:
		return
	var progress: Array[float] = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE_PATH, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_target_scene = ResourceLoader.load_threaded_get(TARGET_SCENE_PATH) as PackedScene
		_resource_ready = _target_scene != null
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_load_requested = false
		_recover_target_load.call_deferred(ERR_CANT_OPEN)
		return
	_check_transition()


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
	if not bool(brand_intro.get("animation_complete")):
		await brand_intro.intro_animation_finished
	if not is_inside_tree():
		return
	_animation_finished = true
	_check_transition()


func _check_transition() -> void:
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
		_prepare_target_scene.call_deferred()
	if _transition_started or not _target_scene_ready:
		return
	_transition_started = true
	_reveal_target_scene.call_deferred()


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


func _prepare_target_scene() -> void:
	if not is_inside_tree() or _target_scene == null:
		_target_prepare_started = false
		return
	_target_scene_instance = _target_scene.instantiate()
	if _target_scene_instance == null:
		_target_prepare_started = false
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
	if not is_inside_tree() or not is_instance_valid(_target_scene_instance):
		return
	_target_scene_ready = true
	_check_transition()


func _reveal_target_scene() -> void:
	if not is_inside_tree() or not _target_scene_ready or not is_instance_valid(_target_scene_instance):
		_transition_started = false
		return
	if _target_scene_instance is CanvasItem:
		(_target_scene_instance as CanvasItem).visible = true
	if suppress_scene_handoff_for_test:
		return
	get_tree().current_scene = _target_scene_instance
	queue_free()
