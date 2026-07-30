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
	assert(lab._foot_pick_button != null)
	assert(lab._alignment_button != null)
	assert(lab._alignment_offset_label != null)
	assert(
		lab._preview_root.scale
			== Vector2.ONE * float(lab._zoom_slider.value)
	)
	lab._reset_visual_alignment()
	var expected_foot_origin: Vector2 = (
		lab._player.visual.position
		+ lab._player.visual.sprite.position
		+ Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR)
	)
	assert(lab._visual_foot_origin() == expected_foot_origin)
	var original_visual_position: Vector2 = lab._player.visual.position
	lab._nudge_visual_foot_anchor(Vector2(1.0, -1.0))
	assert(lab._visual_foot_anchor_adjustment == Vector2(1.0, -1.0))
	assert(lab._player.visual.position == original_visual_position)
	assert(
		lab._visual_foot_origin()
			== expected_foot_origin + Vector2(1.0, -1.0)
	)
	lab._nudge_visual_alignment(Vector2(0.5, -0.5))
	assert(lab._visual_alignment_offset == Vector2(0.5, -0.5))
	assert(
		lab._player.visual.position
			== original_visual_position + Vector2(0.5, -0.5)
	)
	lab._align_visual_foot_to_standard()
	assert(lab._visual_foot_origin().is_zero_approx())
	var alignment_payload: Dictionary = lab.alignment_draft_payload()
	assert(not bool(alignment_payload.get("formalRuntimeWritten", true)))
	assert(
		alignment_payload.get("visualFootAnchorAdjustment", [])
			== [1.0, -1.0]
	)
	var canonical_centers: Dictionary = alignment_payload.get(
		"canonicalCenters", {}
	)
	assert(canonical_centers.get("actorGroundOrigin", []) == [0.0, 0.0])
	assert(canonical_centers.get("physicsFootprint", []) == [0.0, 0.0])
	assert(canonical_centers.get("mapDiamond", []) == [0.0, 0.0])
	lab._reset_visual_alignment()
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
