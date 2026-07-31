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
	assert(lab._mode_option.item_count == 2)
	assert(lab._mode_option.selected == 0)
	assert(lab._monster_option.item_count == 214)
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
	if (
		FileAccess.file_exists(lab.FORMAL_ALIGNMENT_CONTRACT_PATH)
		and FileAccess.file_exists(lab.ALIGNMENT_DRAFT_PATH)
	):
		assert(lab._visual_alignment_offset.is_zero_approx())
		assert(
			lab._visual_foot_anchor_adjustment.is_equal_approx(
				lab._runtime_foot_anchor_adjustment
			)
		)
		assert(lab._visual_foot_origin().is_zero_approx())
	lab._reset_visual_alignment()
	var expected_foot_origin: Vector2 = (
		lab._player.visual.position
		+ lab._player.visual.sprite.position
		+ Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR)
		+ lab._runtime_foot_anchor_adjustment
	)
	assert(lab._visual_foot_origin() == expected_foot_origin)
	var original_visual_position: Vector2 = lab._player.visual.position
	var original_foot_adjustment: Vector2 = (
		lab._runtime_foot_anchor_adjustment
	)
	lab._nudge_visual_foot_anchor(Vector2(1.0, -1.0))
	assert(
		lab._visual_foot_anchor_adjustment
			== original_foot_adjustment + Vector2(1.0, -1.0)
	)
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
			== [
				original_foot_adjustment.x + 1.0,
				original_foot_adjustment.y - 1.0,
			]
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
	lab._mode_option.select(1)
	lab._on_mode_changed(1)
	await get_tree().process_frame
	assert(lab._is_monster_mode())
	assert(lab._action_option.item_count == 5)
	assert(not lab._profession_option.get_parent().visible)
	assert(lab._monster_option.get_parent().visible)
	assert(lab._monster != null and lab._monster.visual != null)
	assert(lab._monster.visual.uses_final_art())
	assert(
		not lab._monster.is_targeted,
		"acceptance lab must suppress the runtime-owned target ring",
	)
	assert(lab._active_monster_id == 18)
	assert(lab._monster.visual.sprite.texture != null)
	var ground_review := lab.monster_ground_review_snapshot()
	assert(int(ground_review.get("monsterId", -1)) == 18)
	assert(
		ground_review.get("runtimeRingCenter", Vector2.INF)
		== lab._monster.ground_indicator_center()
	)
	assert(
		ground_review.get("runtimeRingRadii", Vector2.INF)
		== lab._monster.ground_indicator_radii()
	)
	assert(
		ground_review.get("actorGroundOrigin", Vector2.INF)
		== Vector2.ZERO
	)
	assert(
		ground_review.get("delta", Vector2.INF)
		== (
			ground_review.get("runtimeRingCenter", Vector2.ZERO)
			- ground_review.get("manualFootCenter", Vector2.ZERO)
		)
	)
	assert(
		bool(ground_review.get("targetMatchesContract", false))
		== (
			ground_review.get("runtimeTargetDelta", Vector2.INF).length()
			<= lab.MONSTER_FOOT_MATCH_EPSILON
		)
	)
	assert(
		ground_review.get("runtimeRingCenter", Vector2.INF)
		== ground_review.get("expectedTargetCenter", Vector2.ZERO)
	)
	var original_monster_visual_position := lab._monster.visual.position
	var original_monster_foot_offset := (
		lab._monster_picked_visual_foot_offset
	)
	lab._monster.visual.position += Vector2(8.0, -5.0)
	lab._monster_picked_visual_foot_offset += Vector2(1.5, 2.5)
	var isolated_review := lab.monster_ground_review_snapshot()
	assert(
		isolated_review.get("runtimeRingCenter", Vector2.INF)
		== Vector2(8.0, -5.0)
	)
	assert(not bool(isolated_review.get("targetMatchesContract", true)))
	assert(
		not bool(
			isolated_review.get("manualFootMatchesActorOrigin", true)
		)
	)
	assert(not bool(isolated_review.get("matches", true)))
	lab._monster.visual.position = original_monster_visual_position
	lab._monster_picked_visual_foot_offset = original_monster_foot_offset
	var replay_draft := {
		"runtimeVisualOrigin": [2.0, 7.0],
		"visualOffset": [3.5, -4.5],
		"pickedVisualFootOffset": [-5.5, -2.5],
		"selection": {
			"action": "hit",
			"direction": 6,
			"frame": 1,
		},
	}
	lab._restore_monster_alignment_draft(replay_draft)
	assert(lab._monster_runtime_visual_origin == Vector2(2.0, 7.0))
	assert(lab._monster_visual_alignment_offset == Vector2(3.5, -4.5))
	assert(lab._monster_picked_visual_foot_offset == Vector2(-5.5, -2.5))
	assert(lab._selected_action() == "hit")
	assert(lab._direction_option.selected == 6)
	assert(lab._current_frame == 1)
	var replay_review := lab.monster_ground_review_snapshot()
	assert(bool(replay_review.get("poseMatchesCalibration", false)))
	assert(
		replay_review.get("calibrationSelection", {})
		== replay_review.get("currentSelection", {})
	)
	lab._direction_option.select(5)
	lab._apply_preview_frame()
	assert(
		not bool(
			lab.monster_ground_review_snapshot().get(
				"poseMatchesCalibration", true
			)
		)
	)
	lab._direction_option.select(6)
	lab._apply_preview_frame()
	assert(
		(
			lab._monster_runtime_visual_origin
			+ lab._monster_visual_alignment_offset
			+ lab._monster_picked_visual_foot_offset
		).is_zero_approx()
	)
	lab._rebuild_monster_actor(true)
	lab._reset_visual_alignment()
	lab._set_visual_foot_anchor_from_preview(Vector2(3.0, -2.0))
	assert(lab._visual_foot_origin().is_equal_approx(Vector2(3.0, -2.0)))
	lab._align_visual_foot_to_standard()
	assert(lab._visual_foot_origin().is_zero_approx())
	var monster_payload := lab.monster_alignment_draft_payload()
	assert(
		monster_payload.get("contractId", "")
		== lab.MonsterDraftScript.CONTRACT_ID
	)
	assert(int(monster_payload.get("monsterId", -1)) == 18)
	assert(monster_payload.get("finalVisualFootPoint", []) == [0.0, 0.0])
	assert(not bool(monster_payload.get("formalRuntimeWritten", true)))
	for action_index in lab.MONSTER_ACTIONS.size():
		lab._action_option.select(action_index)
		lab._direction_option.select(action_index % 8)
		lab._apply_selection()
		assert(lab._frame_count() >= 1)
		assert(
			lab._monster.visual.current_state
			== lab.MONSTER_ACTIONS[action_index]
		)
	var touch_dragon_index := -1
	for row_index in lab._monster_rows.size():
		if int(lab._monster_rows[row_index].get("monster_id", -1)) == 124:
			touch_dragon_index = row_index
			break
	assert(touch_dragon_index >= 0)
	lab._monster_option.select(touch_dragon_index)
	lab._rebuild_monster_actor(true)
	assert(lab._active_monster_id == 124)
	assert(not lab._monster._burrowed)
	assert(lab._monster.visual.visible)
	for action_name in ["idle", "attack", "death"]:
		lab._action_option.select(lab.MONSTER_ACTIONS.find(action_name))
		lab._apply_selection()
		assert(lab._frame_count() > 1)
		assert(lab._monster.visual.sprite.texture != null)
	lab._mode_option.select(0)
	lab._on_mode_changed(0)
	assert(not lab._is_monster_mode())
	assert(lab._action_option.item_count == 6)
	assert(lab._player.visible)
	assert(not lab._monster.visible)
	lab.queue_free()
	await get_tree().process_frame
	assert(PlayerState.test_mode == original_test_mode)
	print(
		"UI_VISUAL_ACCEPTANCE_LAB_PASS player_actions=6 "
		+ "monster_actions=5 monsters=214 directions=8 "
		+ "single_target_drafts=true runtime_composite=true"
	)
	get_tree().quit(0)
