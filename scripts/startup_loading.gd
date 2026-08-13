class_name StartupLoading
extends Control

const TARGET_SCENE_PATH := "res://scenes/character_select.tscn"
const LOADING_CONTRACT_ID := "startup.loading.character_select.v1"

@export var auto_start := true
@onready var brand_intro: Control = $BrandIntro

var _target_scene: PackedScene
var _resource_ready := false
var _animation_finished := false
var _transition_started := false
var _load_requested := false


func _ready() -> void:
	if not auto_start:
		return
	# The authored intro plays independently while character selection loads.
	# If loading takes longer, BrandIntro remains on its completed final frame.
	_run_finite_loading_phase.call_deferred()
	_load_requested = ResourceLoader.load_threaded_request(TARGET_SCENE_PATH) == OK
	if not _load_requested:
		push_error("startup loading request failed: %s" % TARGET_SCENE_PATH)
		return


func _process(_delta: float) -> void:
	if not _load_requested or _resource_ready:
		return
	var progress: Array[float] = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE_PATH, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_target_scene = ResourceLoader.load_threaded_get(TARGET_SCENE_PATH) as PackedScene
		_resource_ready = _target_scene != null
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_load_requested = false
		push_error("startup loading failed: %s" % TARGET_SCENE_PATH)
	_check_transition()


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
	if _transition_started or not _resource_ready or not _animation_finished:
		return
	_transition_started = true
	get_tree().change_scene_to_packed(_target_scene)
