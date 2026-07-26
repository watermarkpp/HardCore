extends Node


const PROFILE_ID := "test.character.warrior.chiyue.v1"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/equipment_warrior_chiyue_world_dress"
const CAPTURE_RECT := Rect2i(288, 90, 384, 360)
const POSES := [
	{"name": "idle_front", "facing": Vector2.DOWN, "velocity": Vector2.ZERO},
	{"name": "idle_side", "facing": Vector2.RIGHT, "velocity": Vector2.ZERO},
	{"name": "walk_side", "facing": Vector2.RIGHT, "velocity": Vector2(70.0, 0.0)},
]


func _ready() -> void:
	_capture.call_deferred()


func _checkerboard() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = -100
	for row: int in 9:
		for column: int in 16:
			var tile := ColorRect.new()
			tile.position = Vector2(column * 60, row * 60)
			tile.size = Vector2(60, 60)
			tile.color = Color("2b3340") if (row + column) % 2 == 0 else Color("566274")
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(tile)
	return root


func _visible_bounds(sprite: Sprite2D) -> Rect2i:
	var image := sprite.texture.get_image()
	var cell := image.get_region(Rect2i(sprite.region_rect))
	var minimum := Vector2i(cell.get_width(), cell.get_height())
	var maximum := Vector2i(-1, -1)
	for y: int in cell.get_height():
		for x: int in cell.get_width():
			if cell.get_pixel(x, y).a > 0.99:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	assert(maximum.x >= minimum.x and maximum.y >= minimum.y, "世界动作帧不得为空")
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _capture() -> void:
	get_viewport().size = Vector2i(960, 540)
	add_child(_checkerboard())
	PlayerState.test_mode = true
	var sandbox_id := str(Time.get_ticks_usec())
	PlayerState.profile_directory = "user://equipment_warrior_chiyue_world_dress_capture/%s/characters" % sandbox_id
	PlayerState.profile_index_path = "user://equipment_warrior_chiyue_world_dress_capture/%s/character_profiles.json" % sandbox_id
	PlayerState.ensure_equipment_skill_test_roster()
	assert(PlayerState.select_character(PROFILE_ID))
	assert(str(PlayerState.equipment.get("衣服", {}).get("name", "")) == "天魔神甲")

	var player := PlayerCharacter.new()
	player.position = Vector2(480, 340)
	add_child(player)
	for _frame: int in 5:
		await get_tree().process_frame
	var visual: Node2D = player.visual
	assert(player.visible and visual.visible and visual.sprite.visible)
	assert(is_equal_approx(player.modulate.a, 1.0) and is_equal_approx(player.self_modulate.a, 1.0))
	assert(is_equal_approx(visual.modulate.a, 1.0) and is_equal_approx(visual.self_modulate.a, 1.0))
	assert(is_equal_approx(visual.sprite.modulate.a, 1.0) and is_equal_approx(visual.sprite.self_modulate.a, 1.0))
	assert(visual.z_index == 0 and visual.sprite.z_index == 0)

	var output_dir := ProjectSettings.globalize_path(OUTPUT_ROOT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var manifest_poses: Array[Dictionary] = []
	for pose: Dictionary in POSES:
		player.facing = pose.facing
		player.actual_motion_facing = pose.facing
		player.velocity = pose.velocity
		visual._action_remaining = 0.0
		visual._elapsed = 0.0
		visual._last_state = ""
		visual._process(0.11)
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var bounds := _visible_bounds(visual.sprite)
		assert(bounds.size.x >= 25 and bounds.size.y >= 70, "%s 人物可见包围盒异常" % pose.name)
		var viewport_image := get_viewport().get_texture().get_image()
		assert(viewport_image != null and not viewport_image.is_empty())
		var crop := viewport_image.get_region(CAPTURE_RECT)
		var output_path := output_dir.path_join("%s.png" % pose.name)
		assert(crop.save_png(output_path) == OK)
		manifest_poses.append({
			"name": pose.name,
			"state": visual.current_state,
			"direction": visual.current_direction,
			"frame": visual.current_frame,
			"bodyTexture": visual.sprite.texture.resource_path,
			"region": [
				int(visual.sprite.region_rect.position.x),
				int(visual.sprite.region_rect.position.y),
				int(visual.sprite.region_rect.size.x),
				int(visual.sprite.region_rect.size.y),
			],
			"visibleBounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"playerVisible": player.visible,
			"visualVisible": visual.visible,
			"spriteVisible": visual.sprite.visible,
			"playerAlpha": player.modulate.a * player.self_modulate.a,
			"visualAlpha": visual.modulate.a * visual.self_modulate.a,
			"spriteAlpha": visual.sprite.modulate.a * visual.sprite.self_modulate.a,
			"output": "%s/%s.png" % [OUTPUT_ROOT, pose.name],
		})

	var manifest := {
		"contractId": "equipment.world_wear.warrior_chiyue.runtime_capture.v1",
		"profileId": PROFILE_ID,
		"itemId": 140,
		"itemName": "天魔神甲",
		"feature": 12,
		"renderer": RenderingServer.get_current_rendering_method(),
		"displayServer": DisplayServer.get_name(),
		"checkerboardBackground": true,
		"poses": manifest_poses,
	}
	var manifest_file := FileAccess.open(output_dir.path_join("capture_manifest.json"), FileAccess.WRITE)
	assert(manifest_file != null)
	manifest_file.store_string(JSON.stringify(manifest, "\t", false))
	manifest_file.close()
	player.queue_free()
	print("EQUIPMENT_WARRIOR_CHIYUE_WORLD_DRESS_CAPTURE_PASS poses=3 itemId=140 feature=12")
	get_tree().quit(0)
