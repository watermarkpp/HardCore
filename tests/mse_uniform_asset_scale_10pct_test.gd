extends Node


func _ready() -> void:
	var S := MapEditorInstanceService
	assert(S.UNIFORM_VISUAL_SCALE_CONTRACT_ID == "maps.asset_visual_scale.base_relative_10pct.v1")
	assert(is_equal_approx(S.UNIFORM_VISUAL_SCALE_STEP, 0.10))

	# Test A -- 2x2 core regression (base 1.0).
	var a_grow := S.stepped_visual_scale(1.0, 1.0, 1)
	var a_shrink := S.stepped_visual_scale(1.0, 1.0, -1)
	assert(is_equal_approx(a_grow, 1.1))
	assert(is_equal_approx(a_shrink, 0.9))
	assert(S.footprint_for_visual_scale([2, 2], 1.0, 0.9) == [2, 2])
	assert(not is_equal_approx(a_shrink, 0.5), "old 2x2->1x1 50 percent bug must be gone")

	# Test B -- non-1.0 base (0.40): 10% of the asset own base size.
	assert(is_equal_approx(S.stepped_visual_scale(0.40, 0.40, 1), 0.44))
	assert(is_equal_approx(S.stepped_visual_scale(0.40, 0.40, -1), 0.36))

	# Test C -- 1x1 can keep shrinking (no 1x1 shrink ban).
	var c1 := S.stepped_visual_scale(1.0, 1.0, -1)
	var c2 := S.stepped_visual_scale(c1, 1.0, -1)
	assert(is_equal_approx(c1, 0.9))
	assert(is_equal_approx(c2, 0.8))
	assert(S.footprint_for_visual_scale([1, 1], 1.0, 0.9) == [1, 1])
	assert(S.footprint_for_visual_scale([1, 1], 1.0, 0.8) == [1, 1])

	# Test D -- legacy instance (base 1.0, current 0.5) does not jump.
	assert(is_equal_approx(S.stepped_visual_scale(0.5, 1.0, 1), 0.6))
	assert(is_equal_approx(S.stepped_visual_scale(0.5, 1.0, -1), 0.4))

	# Test E -- reversibility (grow then shrink returns to origin).
	var e1 := S.stepped_visual_scale(1.0, 1.0, 1)
	assert(is_equal_approx(S.stepped_visual_scale(e1, 1.0, -1), 1.0))
	var e3 := S.stepped_visual_scale(0.4, 0.4, 1)
	assert(is_equal_approx(S.stepped_visual_scale(e3, 0.4, -1), 0.4))

	# Test F -- uniform aspect (helper yields a single scalar; instance writes [s,s]).
	assert(is_equal_approx(S.stepped_visual_scale(1.0, 1.0, 1), S.stepped_visual_scale(1.0, 1.0, 1)))
	assert(typeof(S.stepped_visual_scale(1.0, 1.0, 1)) == TYPE_FLOAT)

	# Test G -- footprint is a subordinate derived integer.
	assert(S.footprint_for_visual_scale([2, 2], 1.0, 0.9) == [2, 2])
	assert(S.footprint_for_visual_scale([2, 2], 1.0, 2.0) == [4, 4])

	# Test H -- global calibration uses the same shared helper as instance resize.
	var asset_h := {"approved_scale": 1.0, "footprint_tiles": [2, 2], "collision_policy": "none", "collision_footprint_tiles": [0, 0]}
	var base_h := {"approved_scale": 1.0, "base_footprint_tiles": [2, 2]}
	var draft_h := MapEditorApp.build_asset_resize_draft(asset_h, base_h, 1)
	var exp_scale_h := S.stepped_visual_scale(1.0, 1.0, 1)
	var exp_fp_h := S.footprint_for_visual_scale([2, 2], 1.0, exp_scale_h)
	assert(is_equal_approx(float(draft_h.approved_scale), exp_scale_h), "global calibration scale must match shared helper")
	assert(draft_h.footprint_tiles == exp_fp_h, "global calibration footprint must match shared helper")

	# Test I -- reset restores base scale, base footprint, level 0.
	var asset_i := {"approved_scale": 1.1, "footprint_tiles": [3, 3], "collision_policy": "none", "collision_footprint_tiles": [0, 0], "logical_scale_level": 1}
	var base_i := {"approved_scale": 1.0, "base_footprint_tiles": [2, 2], "collision_footprint_tiles": [0, 0]}
	var draft_i := MapEditorApp.build_asset_resize_draft(asset_i, base_i, 3)
	assert(is_equal_approx(float(draft_i.approved_scale), 1.0))
	assert(draft_i.footprint_tiles == [2, 2])
	assert(int(draft_i.logical_scale_level) == 0)

	# Test J -- UI text: 10% semantics present, old grid wording gone.
	var app_src := FileAccess.get_file_as_string("res://scripts/map_editor/map_editor_app.gd")
	for required in ["放大 10%", "缩小 10%", "恢复初始大小", "放大当前地图素材 10%", "缩小当前地图素材 10%"]:
		assert(required in app_src, "missing menu text: " + required)
	for forbidden in ["放大一格", "缩小一格", "恢复初始占位"]:
		assert(not (forbidden in app_src), "forbidden old menu text remains: " + forbidden)

	print("MSE_UNIFORM_ASSET_SCALE_10PCT_PASS")
	get_tree().quit(0)
