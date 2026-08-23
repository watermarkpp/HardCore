extends Node

const LabScript := preload(
	"res://tools/visual_acceptance_lab/visual_acceptance_lab.gd"
)


func _runtime_target_ring_overlays(lab) -> Array:
	var result: Array = []
	if lab._overlay_root == null:
		return result
	for child: Node in lab._overlay_root.get_children():
		if child.name == LabScript.RUNTIME_TARGET_RING_OVERLAY_NAME:
			result.append(child)
	return result


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
	assert(LabScript.monster_id_from_args(["--monster-id=180"]) == 180)
	assert(LabScript.monster_id_from_args(["--monster-id", "180"]) == 180)
	assert(LabScript.monster_id_from_args(["--monster-id=0"]) == -1)
	assert(not lab._player.is_processing())
	assert(not lab._player.is_physics_processing())
	assert(not lab._player.visual.is_processing())
	assert(lab._action_option.item_count == 6)
	assert(lab._mode_option.item_count == 3)
	assert(lab._mode_option.selected == 0)
	assert(lab._monster_option.item_count == 156)
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
	lab._mode_option.select(2)
	lab._on_mode_changed(2)
	assert(lab._is_warrior_skill_mode())
	assert(not lab._is_monster_mode())
	assert(lab._action_option.item_count == 6)
	assert(lab._profession_option.get_parent().visible)
	assert(lab._profession_option.disabled)
	assert(lab._profession_option.selected == 0)
	assert(lab._warrior_skill_controls.visible)
	assert(not lab._foot_pick_button.visible)
	assert(not lab._alignment_button.visible)
	assert(not lab._alignment_actions.visible)
	assert(not lab._save_alignment_button.visible)
	assert(lab._player.visible)
	assert(lab._monster == null or not lab._monster.visible)
	assert(lab._frame_count() == lab.WARRIOR_SKILL_EXPECTED_FRAMES)
	var contact_layout := lab.warrior_contact_sheet_layout()
	assert(int(contact_layout.get("columns", 0)) == 8)
	assert(int(contact_layout.get("rows", 0)) == 6)
	assert(
		contact_layout.get("columnOrder", [])
		== lab.DIRECTION_LABELS
	)
	assert(
		contact_layout.get("imageSize", Vector2i.ZERO)
		== Vector2i(
			lab.WARRIOR_CONTACT_CELL_SIZE.x * 8,
			lab.WARRIOR_CONTACT_CELL_SIZE.y * 6,
		)
	)
	for skill_index in lab.WARRIOR_SKILL_ACTIONS.size():
		lab._action_option.select(skill_index)
		lab._direction_option.select(skill_index % 8)
		lab._apply_selection()
		var skill_action: String = lab.WARRIOR_SKILL_ACTIONS[
			skill_index
		]
		var skill_audit := lab.warrior_skill_audit_snapshot()
		assert(
			skill_audit.get("contractId", "")
			== lab.WARRIOR_SKILL_LAB_CONTRACT_ID
		)
		assert(skill_audit.get("skillAction", "") == skill_action)
		assert(skill_audit.get("bodyAction", "") == "attack")
		assert(int(skill_audit.get("frameCount", 0)) == 6)
		assert(
			lab._player.visual.current_animation_name()
			== skill_action
		)
		var expects_effect := skill_action in [
			"攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法",
		]
		assert(
			bool(skill_audit.get("mainEffectSupported", false))
			== expects_effect
		)
		assert(
			bool(skill_audit.get("mainEffectVisible", false))
			== expects_effect
		)
		assert(not bool(skill_audit.get("passiveEffectVisible", true)))
		if expects_effect:
			assert(int(skill_audit.get("sourceIndex", -1)) >= 0)
	lab._action_option.select(
		lab.WARRIOR_SKILL_ACTIONS.find("半月弯刀")
	)
	lab._direction_option.select(3)
	lab._current_frame = 4
	lab._frame_spin.set_value_no_signal(4)
	lab._apply_preview_frame()
	var half_moon_main_region: Rect2 = (
		lab._player.visual.skill_effect_sprite.region_rect
	)
	lab._passive_effect_layer_button.set_pressed_no_signal(true)
	lab._apply_preview_frame()
	var layered_audit := lab.warrior_skill_audit_snapshot()
	assert(layered_audit.get("skillAction", "") == "半月弯刀")
	assert(bool(layered_audit.get("mainEffectVisible", false)))
	assert(bool(layered_audit.get("passiveEffectVisible", false)))
	assert(
		lab._player.visual.skill_effect_sprite.region_rect
		== half_moon_main_region
	)
	assert(lab._player.visual._action_name == "半月弯刀")
	lab._body_layer_button.set_pressed_no_signal(false)
	lab._weapon_layer_button.set_pressed_no_signal(false)
	lab._main_effect_layer_button.set_pressed_no_signal(false)
	lab._apply_preview_frame()
	assert(not lab._player.visual.sprite.visible)
	assert(not lab._player.visual.worn_hair_sprite.visible)
	assert(not lab._player.visual.worn_weapon_sprite.visible)
	assert(not lab._player.visual.skill_effect_sprite.visible)
	assert(lab._player.visual.passive_proc_effect_sprite.visible)
	assert(lab._player.visual._action_name == "半月弯刀")
	lab._body_layer_button.set_pressed_no_signal(true)
	lab._weapon_layer_button.set_pressed_no_signal(true)
	lab._main_effect_layer_button.set_pressed_no_signal(true)
	lab._passive_effect_layer_button.set_pressed_no_signal(false)
	lab._action_option.select(
		lab.WARRIOR_SKILL_ACTIONS.find("烈火剑法")
	)
	for direction_index in 8:
		for frame_index in 6:
			lab._direction_option.select(direction_index)
			lab._current_frame = frame_index
			lab._frame_spin.set_value_no_signal(frame_index)
			lab._apply_preview_frame()
			var fire_audit := lab.warrior_skill_audit_snapshot()
			assert(
				int(fire_audit.get("direction", -1))
				== direction_index
			)
			assert(int(fire_audit.get("frame", -1)) == frame_index)
			assert(bool(fire_audit.get("mainEffectVisible", false)))
			assert(
				not str(
					fire_audit.get("mainEffectAsset", "")
				).is_empty()
			)
			assert(int(fire_audit.get("sourceIndex", -1)) >= 0)
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
		lab._monster.position.is_zero_approx(),
		"acceptance monster must use the game's actor-local origin",
	)
	assert(
		lab._monster.visual.position.is_equal_approx(
			lab._monster_runtime_visual_origin
			+ lab._monster_visual_alignment_offset
			+ lab._monster_manual_replay_displacement()
		),
		"acceptance lab must use the same normalized visual transform as runtime",
	)
	assert(
		lab._monster.is_targeted,
		"acceptance lab must use the runtime-owned target ring",
	)
	assert(lab._active_monster_id == 18)
	assert(lab._monster.visual.sprite.texture != null)
	var ground_review := lab.monster_ground_review_snapshot()
	assert(int(ground_review.get("monsterId", -1)) == 18)
	assert(bool(ground_review.get("runtimeSelected", false)))
	assert(bool(ground_review.get("runtimeRingVisible", false)))
	assert(ground_review.get("runtimeRingOwner", "") == "monster_visual")
	assert(
		ground_review.get("runtimeRingMode", "")
		== "authored_cast_with_contact_core"
	)
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
	assert(
		lab._monster.position.is_zero_approx(),
		"forced rebuild must preserve the game's actor-local origin",
	)
	assert(
		lab._monster.visual.position.is_equal_approx(
			lab._monster_runtime_visual_origin
			+ lab._monster_visual_alignment_offset
			+ lab._monster_manual_replay_displacement()
		),
		"forced rebuild must preserve the normalized visual transform",
	)
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
	assert(lab._select_monster_id(180))
	assert(lab._active_monster_id == 180)
	assert(lab._monster_picked_visual_foot_offset == Vector2(31.5, -2.0))
	var red_moon_review := lab.monster_ground_review_snapshot()
	assert(int(red_moon_review.get("monsterId", -1)) == 180)
	assert(bool(red_moon_review.get("draftLoaded", false)))
	assert(bool(red_moon_review.get("runtimeSelected", false)))
	assert(bool(red_moon_review.get("runtimeRingVisible", false)))
	assert(
		red_moon_review.get("runtimeRingOwner", "") == "monster_visual"
	)
	assert(
		red_moon_review.get("runtimeRingMode", "")
		== "authored_cast_with_contact_core"
	)
	assert(
		red_moon_review.get("runtimeRingCenter", Vector2.INF)
		.is_zero_approx()
	)
	assert(red_moon_review.get("matches", false))
	lab._update_overlay()
	var red_moon_ring_nodes := _runtime_target_ring_overlays(lab)
	assert(red_moon_ring_nodes.size() == 1)
	var red_moon_ring: Line2D = red_moon_ring_nodes[0]
	assert(
		red_moon_ring.get_meta("center", Vector2.INF)
		.is_equal_approx(lab._visual_foot_origin())
	)
	assert(
		red_moon_ring.get_meta("radii", Vector2.INF)
		.is_equal_approx(lab._monster.ground_indicator_radii())
	)
	assert(
		red_moon_ring.default_color.is_equal_approx(
			LabScript.RUNTIME_TARGET_RING_COLOR
		)
	)
	assert(is_equal_approx(red_moon_ring.width, LabScript.RUNTIME_TARGET_RING_WIDTH))
	var original_red_moon_visual_position := lab._monster.visual.position
	var original_red_moon_foot_offset := (
		lab._monster_picked_visual_foot_offset
	)
	var original_red_moon_ring_center: Vector2 = red_moon_ring.get_meta(
		"center", Vector2.INF
	)
	lab._monster.visual.position += Vector2(8.0, -5.0)
	lab._monster_picked_visual_foot_offset += Vector2(1.5, 2.5)
	lab._update_overlay()
	var moved_red_moon_ring_nodes := _runtime_target_ring_overlays(lab)
	assert(moved_red_moon_ring_nodes.size() == 1)
	var moved_red_moon_ring: Line2D = moved_red_moon_ring_nodes[0]
	assert(
		moved_red_moon_ring.get_meta("center", Vector2.INF)
		.is_equal_approx(lab._visual_foot_origin())
	)
	assert(
		not moved_red_moon_ring.get_meta("center", Vector2.INF)
		.is_equal_approx(original_red_moon_ring_center)
	)
	assert(
		moved_red_moon_ring.get_meta("radii", Vector2.INF)
		.is_equal_approx(lab._monster.ground_indicator_radii())
	)
	lab._monster.visual.position = original_red_moon_visual_position
	lab._monster_picked_visual_foot_offset = original_red_moon_foot_offset
	lab._update_overlay()
	assert(_runtime_target_ring_overlays(lab).size() == 1)
	var default_monster_index := -1
	for row_index in lab._monster_rows.size():
		if int(lab._monster_rows[row_index].get("monster_id", -1)) == 18:
			default_monster_index = row_index
			break
	assert(default_monster_index >= 0)
	lab._monster_option.select(default_monster_index)
	lab._on_monster_changed(default_monster_index)
	assert(lab._active_monster_id == 18)
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
		+ "monster_actions=5 monsters=156 auto_monster_id=180 "
		+ "warrior_skills=6 "
		+ "directions=8 frames=6 passive_layer_isolated=true "
		+ "single_target_drafts=true runtime_composite=true"
	)
	get_tree().quit(0)
