extends Node2D

const OUTPUT_PREFIX := "res://outputs/test_logs/w6_sort_render"


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("181522"))
	var sort_root := Node2D.new()
	sort_root.name = "WorldYSortRoot"
	sort_root.y_sort_enabled = true
	add_child(sort_root)

	var actor := Node2D.new()
	actor.name = "BodyAtFootpoint"
	actor.position = Vector2(360, 250)
	sort_root.add_child(actor)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-23, 22), Vector2(-18, -18), Vector2(0, -34),
		Vector2(18, -18), Vector2(23, 22), Vector2(0, 34),
	])
	body.color = Color("f11d71")
	body.z_index = 0
	actor.add_child(body)
	var body_mark := Polygon2D.new()
	body_mark.polygon = PackedVector2Array([
		Vector2(-4, -18), Vector2(4, -18), Vector2(4, 18), Vector2(-4, 18),
	])
	body_mark.color = Color("fff0a5")
	body_mark.z_index = 1
	actor.add_child(body_mark)

	var profile: Dictionary = CasterSkillVisualRegistry.profile("wizard.lightning")
	var plan := {
		"success": true,
		"skill_id": "wizard.lightning",
		"visual": profile,
		"visual_radius_px": 72.0,
		"visual_duration": CasterSkillVisualRegistry.animation_duration("wizard.lightning"),
		"skill_footprint_snapshot": {},
	}
	var sky := CasterSkillRuntime.create_visual(plan, actor.global_position, Vector2.RIGHT, actor, "")
	sort_root.add_child(sky)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("same_footpoint", sky)
	var rear_wall := _make_wall(sort_root, 210.0, Color("2bd66f"))
	await get_tree().process_frame
	_capture("rear_wall_y210_effect_on_top", sky)
	rear_wall.queue_free()
	await get_tree().process_frame
	var front_wall := _make_wall(sort_root, 290.0, Color("d64b75"))
	await get_tree().process_frame
	_capture("front_wall_y290_wall_on_top", sky)
	print("W6_SORT_RENDER_SAVED z=%d sort_key_y=%.2f visual_y=%.1f body_visible_contract=%s" % [
		sky.z_index,
		float(sky.get_meta("sky_strike_world_footpoint_sort_key_y", sky.global_position.y)),
		float(sky.get_meta("sky_strike_world_footpoint_render_y", sky.global_position.y)),
		str(sky.get_meta("sky_strike_actor_visibility_preserved", false)),
	])
	get_tree().quit(0)


func _make_wall(sort_root: Node2D, sort_y: float, wall_color: Color) -> Node2D:
	var wall := Node2D.new()
	wall.name = "WallY%d" % int(sort_y)
	wall.position = Vector2(360.0, sort_y)
	sort_root.add_child(wall)
	var panel := Polygon2D.new()
	panel.polygon = PackedVector2Array([
		Vector2(-56, -48), Vector2(56, -48), Vector2(56, 100), Vector2(-56, 100),
	])
	panel.color = wall_color
	wall.add_child(panel)
	return wall


func _capture(label: String, sky: Node2D) -> void:
	var image := get_viewport().get_texture().get_image()
	var output_path := "%s_%s.png" % [OUTPUT_PREFIX, label]
	image.save_png(output_path)
	print("W6_SORT_RENDER_CASE label=%s path=%s sky_y=%.2f" % [label, output_path, sky.global_position.y])
