extends Node

const LabScript := preload(
	"res://tools/visual_acceptance_lab/visual_acceptance_lab.gd"
)


func _ready() -> void:
	var original_test_mode := PlayerState.test_mode
	var lab := LabScript.new()
	add_child(lab)
	await get_tree().process_frame
	assert(lab.LAB_CONTRACT_ID == "local.visual_acceptance_lab.player_runtime.v1")
	assert(
		lab._viewport != null
			and lab._viewport.size.x > 0
			and lab._viewport.size.y > 0
	)
	assert(lab._player != null and lab._player.visual != null)
	assert(not lab._player.is_processing())
	assert(not lab._player.is_physics_processing())
	assert(not lab._player.visual.is_processing())
	assert(lab._action_option.item_count == 6)
	assert(lab._direction_option.item_count == 8)
	assert(lab._speed_option.item_count == 4)
	assert(lab._background_option.item_count == 3)
	assert(
		lab._preview_root.scale
			== Vector2.ONE * float(lab._zoom_slider.value)
	)
	lab._action_option.select(lab.ACTIONS.find("walk"))
	lab._direction_option.select(0)
	lab._apply_selection()
	var playback_frame_count: int = lab._frame_count()
	assert(playback_frame_count > 1)
	var initial_lab_frame: int = lab._current_frame
	var initial_visual_frame: int = lab._player.visual.current_frame
	var initial_body_region: Rect2 = lab._player.visual.sprite.region_rect
	for tick in 20:
		await get_tree().process_frame
	assert(lab._current_frame != initial_lab_frame)
	assert(lab._player.visual.current_frame != initial_visual_frame)
	assert(lab._player.visual.sprite.region_rect != initial_body_region)
	for action_index in lab.ACTIONS.size():
		lab._action_option.select(action_index)
		lab._direction_option.select(action_index % 8)
		lab._apply_selection()
		assert(lab._frame_count() >= 1)
		assert(lab._player.visual.current_animation_name() == lab.ACTIONS[action_index])
	lab.queue_free()
	await get_tree().process_frame
	assert(PlayerState.test_mode == original_test_mode)
	print(
		"UI_VISUAL_ACCEPTANCE_LAB_PASS actions=6 directions=8 "
		+ "readonly=true runtime_composite=true"
	)
	get_tree().quit(0)
