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
