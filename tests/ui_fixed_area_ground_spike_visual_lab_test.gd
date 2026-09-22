extends Node

const LabScript := preload(
	"res://tools/visual_acceptance_lab/visual_acceptance_lab.gd"
)
const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)


func _ready() -> void:
	var original_test_mode := PlayerState.test_mode
	var lab := LabScript.new()
	add_child(lab)
	await get_tree().process_frame
	lab._mode_option.select(1)
	lab._on_mode_changed(1)
	assert(lab._select_monster_id(180))
	lab._action_option.select(2)
	lab._on_selection_changed(2)
	assert(lab._fixed_area_ground_spike_preview_active())
	assert(lab._ground_spike_preview.visible)
	assert(lab._player.visible, "ground-spike review must show the victim")
	assert(lab._frame_count() >= MonsterGroundSpikeEffectScript.FRAME_COUNT)
	for frame_index: int in range(MonsterGroundSpikeEffectScript.FRAME_COUNT):
		lab._current_frame = frame_index
		lab._apply_preview_frame()
		assert(lab._ground_spike_preview.current_frame() == frame_index)
		assert(
			lab._ground_spike_preview.position.is_equal_approx(
				lab._preview_root.to_local(
					lab._player.approved_ground_footpoint_world_px()
				)
			)
		)
		assert(
			lab._ground_spike_preview.position.is_equal_approx(
				lab._player.position
			),
			"validator must attach the spike to the original approved (0,0) point",
		)

	# The formal runner uses Godot's dummy headless renderer, which has no
	# readable viewport texture. Pixel visibility is verified in the real GUI
	# validator after this structural/frame contract passes.
	lab.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = original_test_mode
	print("UI_FIXED_AREA_GROUND_SPIKE_VISUAL_LAB_PASS")
	get_tree().quit(0)
