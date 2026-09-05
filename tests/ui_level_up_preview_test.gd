extends Node

const PreviewScript := preload("res://scripts/ui_level_up_preview.gd")

var started := 0
var paused := 0
var finished := 0


func _ready() -> void:
	var preview := PreviewScript.new()
	add_child(preview)
	await get_tree().process_frame
	assert(preview.get_meta("stable_id") == PreviewScript.CONTRACT_ID)
	assert(bool(preview.get_meta("preview_only", false)))
	assert(str(preview.get_meta("gameplay_event_source", "")) == "none")
	assert(not preview.visible and not preview.is_playing())

	var source := FileAccess.get_file_as_string("res://scripts/ui_level_up_preview.gd")
	assert(not source.contains("PlayerState"), "preview component must not read PlayerState")
	assert(not source.contains("GameRoot"), "preview component must not bind GameRoot events")
	assert(not source.contains("profile_changed"), "preview component must not bind progression signals")
	assert(not source.contains("level_up_requested"), "preview component must not bind upgrade signals")
	# The accepted foot ring is a frozen visual contract: retain its three-ring
	# projection, radius, alpha and ground bloom while replacing only the old
	# hard-symbol layers above it.
	assert(source.contains("draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.34))"))
	assert(source.contains("lerpf(24.0, 78.0, ease(ring_phase, 0.72))"))
	assert(source.contains("alpha * (0.62 - float(ring_index) * 0.13) * (1.0 - ring_phase * 0.58)"))
	assert(source.contains("draw_circle(Vector2.ZERO, lerpf(20.0, 43.0, t), Color(OUTER_GLOW, alpha * 0.08))"))
	assert(source.count("draw_arc(") == 1, "old central rune arc must be removed")
	assert(not source.contains("draw_line("), "hard line segments must be removed")
	assert(not source.contains("rune_radius"), "central cross/rune geometry must be removed")
	assert(source.contains("FLAME_PETAL_COUNT"))
	assert(source.contains("draw_primitive"), "replacement must use filled triangle primitives")
	assert(not source.contains("draw_colored_polygon"), "solid polygon fills must stay removed")
	assert(source.contains("PackedColorArray([color, edge, edge])"), "flame edges must fade to transparent")
	assert(source.contains("var edge := Color(color, 0.0)"), "flame edge alpha must be zero")
	assert(source.contains("_draw_if_triangulatable"), "flame layers must use the triangulation gate")
	assert(source.contains("Geometry2D.triangulate_polygon"), "flame layers must be geometry-checked before drawing")
	assert(source.contains("FLAME_SIZE_SCALE := 0.75"), "flame column must be scaled to 75 percent")
	assert(source.contains("ground_width := FLAME_SIZE_SCALE *"), "flame width must use the 75 percent scale")
	assert(source.contains("rise := FLAME_SIZE_SCALE *"), "flame height must use the 75 percent scale")
	assert(source.contains("lerpf(24.0, 60.0, ease(t, 0.82))"), "flame rise must reach the approved waist/chest scale")
	assert(source.contains("Color(FLAME_AMBER_GLOW, alpha * 0.24)"), "outer flame must retain the bright amber layer")
	assert(source.contains("Color(GOLD_GLOW, alpha * 0.44)"), "middle flame must retain the bright gold layer")
	assert(source.contains("Color(FLAME_CORE_GLOW, alpha * 0.72)"), "core flame must retain the bright gold-white layer")
	assert(source.contains("GROUND_PROJECTION_Y := 0.34"))
	assert(source.contains("_project_ground(radial * ground_radius)"))
	assert(source.contains("var ground_drift := _project_ground(tangent *"), "petal ground drift must use the same ellipse projection")
	assert(source.contains("behind_body := ground_base.y < 0.0"), "depth must follow the projected ground base")
	assert(source.contains("show_behind_parent = true"), "back pass must use actor-parent occlusion")
	assert(source.contains("RENDER_PASS_BACK"), "flame rendering must have a back pass")
	assert(source.contains("func petal_depth_pass"), "depth partition must be observable for the visual test")
	var workbench_source := FileAccess.get_file_as_string("res://tests/ui_layout_calibration_workbench.gd")
	assert(workbench_source.contains("player.add_child(level_up_preview)"), "calibration preview must share the player actor plane")
	assert(not workbench_source.contains("game_root.add_child(level_up_preview)"), "calibration preview must not remain a world sibling")
	assert(workbench_source.contains("approved_ground_footpoint_local_px"), "calibration anchor must be player-local")
	assert(not workbench_source.contains("level_up_preview.position + preview_offset"), "calibration actor move must not double-shift the preview")

	# Exercise the real Node2D draw path at every progress boundary and interior
	# sample. This catches invalid/self-intersecting flame polygons instead of
	# merely checking the source text or the playback state machine.
	var draw_actor := Node2D.new()
	draw_actor.name = "DrawActor"
	add_child(draw_actor)
	var draw_preview := PreviewScript.new()
	draw_preview.name = "DrawPreview"
	draw_actor.add_child(draw_preview)
	await get_tree().process_frame
	var back_layer := draw_actor.get_node_or_null("DrawPreviewBackLayer") as Node2D
	assert(back_layer != null, "actor-mounted preview must create a back render sibling")
	assert(back_layer.show_behind_parent, "back render sibling must be behind the actor")
	assert(back_layer.z_index == 0 and back_layer.z_as_relative, "back render sibling escaped actor z=0")
	assert(draw_preview.petal_depth_pass(0, 0.0) == "front", "boundary petal starts in front at ground y=0")
	assert(draw_preview.petal_depth_pass(0, 0.2) == "back", "same rotating petal must switch behind the body")
	draw_preview.replay()
	draw_preview.set_process(false)
	var saw_draw := false
	var max_attempts := 0
	var max_front_petals := 0
	var max_back_petals := 0
	for sample_index in range(41):
		if sample_index > 0:
			draw_preview.advance_preview(PreviewScript.DURATION_SECONDS / 40.0)
		draw_preview.queue_redraw()
		# process_frame is deterministic under the project's headless runner and
		# still executes the Node2D draw callback before the safety snapshot.
		await get_tree().process_frame
		var safety: Dictionary = draw_preview.draw_safety_snapshot()
		var attempts := int(safety.get("polygon_attempts", 0))
		var skips := int(safety.get("invalid_polygon_skips", 0))
		var front_petals := int(safety.get("front_petals", 0))
		var back_petals := int(safety.get("back_petals", 0))
		assert(attempts >= 0 and attempts <= PreviewScript.FLAME_PETAL_COUNT * 3)
		assert(skips == 0, "all flame layers must triangulate at progress sample %d" % sample_index)
		assert(front_petals + back_petals <= PreviewScript.FLAME_PETAL_COUNT)
		if attempts > 0:
			saw_draw = true
		max_attempts = maxi(max_attempts, attempts)
		max_front_petals = maxi(max_front_petals, front_petals)
		max_back_petals = maxi(max_back_petals, back_petals)
	assert(saw_draw, "draw path did not render any flame layer")
	assert(max_attempts == PreviewScript.FLAME_PETAL_COUNT * 3, "all eight petals and three layers must draw")
	assert(max_front_petals > 0 and max_back_petals > 0, "both actor depth passes must render petals")
	draw_preview.reset()
	draw_actor.queue_free()

	preview.playback_started.connect(_on_preview_started)
	preview.playback_paused.connect(_on_preview_paused)
	preview.playback_finished.connect(_on_preview_finished)
	var anchor := Vector2(42.5, 18.25)
	preview.replay(anchor)
	assert(preview.visible and preview.is_playing())
	assert(preview.position == anchor)
	assert(is_equal_approx(preview.progress(), 0.0))
	assert(started == 1)

	preview.advance_preview(PreviewScript.DURATION_SECONDS * 0.25)
	assert(preview.is_playing())
	assert(preview.progress() > 0.0 and preview.progress() < 1.0)
	preview.pause()
	var paused_progress := preview.progress()
	preview.advance_preview(PreviewScript.DURATION_SECONDS)
	assert(is_equal_approx(preview.progress(), paused_progress), "paused preview advanced")
	assert(paused == 1 and finished == 0)

	preview.play()
	assert(preview.is_playing())
	preview.advance_preview(PreviewScript.DURATION_SECONDS)
	assert(not preview.is_playing())
	assert(is_equal_approx(preview.progress(), 1.0))
	assert(finished == 1)
	assert(started == 2, "replay/pause/play start count changed")

	preview.replay(Vector2(-4.0, 7.0))
	assert(preview.is_playing() and is_equal_approx(preview.progress(), 0.0))
	assert(started == 3, "replay must restart the same preview instance")
	preview.reset()
	assert(not preview.visible and not preview.is_playing())
	var snapshot: Dictionary = preview.playback_snapshot()
	assert(bool(snapshot.get("preview_only", false)))
	assert(snapshot.get("gameplay_event_source", "") == "none")
	print("UI_LEVEL_UP_PREVIEW_TEST_PASS contract=%s preview_only=true replay=true paused=true finished=true" % PreviewScript.CONTRACT_ID)
	get_tree().quit(0)


func _on_preview_started() -> void:
	started += 1


func _on_preview_paused() -> void:
	paused += 1


func _on_preview_finished() -> void:
	finished += 1
