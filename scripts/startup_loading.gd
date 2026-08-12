class_name StartupLoading
extends Control

const TARGET_SCENE_PATH := "res://scenes/character_select.tscn"
const LOADING_CONTRACT_ID := "startup.loading.character_select.v1"
const FINITE_ANIMATION_SECONDS := 1.20
const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")

@export var auto_start := true
@onready var loading_overlay: LoadingTransitionOverlay = $LoadingOverlay

var _target_scene: PackedScene
var _resource_ready := false
var _animation_finished := false
var _transition_started := false
var _load_requested := false


func _ready() -> void:
	if not auto_start:
		return
	loading_overlay.show_loading_immediately(LOADING_CONTRACT_ID)
	# The finite visual phase is independent of resource-request success. A
	# failed request must still reach its final frame and hold there rather
	# than leaving an unbounded animation running forever.
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
	# Present the startup scene for at least one real frame before the minimum
	# duration begins. Cold Android launches can otherwise replace this scene
	# before the custom loading surface is ever composited.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().create_timer(FINITE_ANIMATION_SECONDS).timeout
	if not is_inside_tree():
		return
	_animation_finished = true
	loading_overlay.freeze_final_visual()
	_check_transition()


func _check_transition() -> void:
	if _transition_started or not _resource_ready or not _animation_finished:
		return
	_transition_started = true
	get_tree().change_scene_to_packed(_target_scene)
