extends Node

const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const EPSILON := 0.001
var _checks_failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Control.new()
	stage.name = "ViewportStage"
	add_child(stage)
	var overlay: Control = LoadingTransitionOverlayScript.new()
	stage.add_child(overlay)
	await get_tree().process_frame
	var cases := [
		{
			"name": "2400x1080_left_cutout",
			"window": Vector2(2400, 1080),
			"safe": Rect2(120, 0, 2280, 1080),
		},
		{
			"name": "2400x1080_right_cutout",
			"window": Vector2(2400, 1080),
			"safe": Rect2(0, 0, 2280, 1080),
		},
		{
			"name": "2340x1080_bilateral_inset",
			"window": Vector2(2340, 1080),
			"safe": Rect2(90, 0, 2160, 1080),
		},
		{
			"name": "1920x1080_no_inset",
			"window": Vector2(1920, 1080),
			"safe": Rect2(0, 0, 1920, 1080),
		},
		{
			"name": "2400x1080_left_cutout_logical_1598x720",
			"window": Vector2(2400, 1080),
			"viewport": Vector2(1598, 720),
			"safe": Rect2(120, 0, 2280, 1080),
		},
	]
	for entry: Dictionary in cases:
		var viewport_size: Vector2 = entry.get("viewport", entry.window)
		var margins := MobileLayoutRules.safe_margins(entry.window, entry.safe, viewport_size)
		overlay.apply_layout(viewport_size, margins)
		_assert_full_viewport_rect(overlay, viewport_size, "%s overlay" % entry.name)
		_assert_full_viewport_rect(overlay.shade, viewport_size, "%s shade" % entry.name)
		_assert_full_viewport_rect(overlay.battlefield_background, viewport_size, "%s battlefield background" % entry.name)
		_assert_full_viewport_rect(overlay.vignette, viewport_size, "%s vignette" % entry.name)
		var expected_safe_position := Vector2(margins.x, margins.y)
		var expected_safe_size := viewport_size - Vector2(margins.x + margins.z, margins.y + margins.w)
		_assert_vector(overlay.content_safe_root.position, expected_safe_position, "%s safe position" % entry.name)
		_assert_vector(overlay.content_safe_root.size, expected_safe_size, "%s safe size" % entry.name)
		_assert_safe_content(overlay, entry.name)
		await _assert_caption_counterexamples(overlay, entry.name)
		_assert_safe_content(overlay, "%s restored" % entry.name)
	_assert_handshake_unchanged(overlay)
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	_require(hud.loading_transition_overlay.get_parent() == hud, "Loading overlay must be a direct CanvasLayer child")
	_require(hud.loading_transition_overlay.get_parent().name != "MobileSafeRoot", "Loading overlay must not inherit safe-area clipping")
	if _checks_failed:
		get_tree().quit(1)
		return
	print("LOADING_TRANSITION_VIEWPORT_COVERAGE_PASS: 2400x1080/2340x1080/1920x1080、左右安全区、四边零缝隙与安全区内容均通过")
	get_tree().quit(0)


func _assert_full_viewport_rect(control: Control, viewport_size: Vector2, label: String) -> void:
	_assert_vector(control.position, Vector2.ZERO, "%s origin" % label)
	_assert_vector(control.size, viewport_size, "%s size" % label)
	_require(control.position.x <= EPSILON and control.position.y <= EPSILON, "%s left/top gap" % label)
	_require(control.position.x + control.size.x >= viewport_size.x - EPSILON, "%s right gap" % label)
	_require(control.position.y + control.size.y >= viewport_size.y - EPSILON, "%s bottom gap" % label)


func _assert_safe_content(overlay: Control, label: String) -> void:
	var safe_bounds := Rect2(Vector2.ZERO, overlay.content_safe_root.size)
	_require(safe_bounds.encloses(Rect2(overlay.game_icon_watermark.position, overlay.game_icon_watermark.size)), "%s icon exceeds safe area" % label)
	_require(safe_bounds.encloses(Rect2(overlay.red_glow.position, overlay.red_glow.size)), "%s glow exceeds safe area" % label)
	var caption: Label = overlay.loading_label
	_require(caption.text == overlay.LOADING_TEXT, "%s caption text changed" % label)
	_require(caption.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and caption.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "%s caption alignment changed" % label)
	_require(caption.autowrap_mode == TextServer.AUTOWRAP_OFF, "%s caption unexpectedly wraps" % label)
	var text_rect := _caption_render_bounds(caption)
	_require(_caption_is_inside_safe_area(caption, safe_bounds), "%s shaped text exceeds safe area: %s outside %s" % [label, text_rect, safe_bounds])
	var world_center_x: float = overlay.size.x * 0.5
	_require(absf(overlay.content_safe_root.position.x + overlay.game_icon_watermark.position.x + overlay.game_icon_watermark.size.x * 0.5 - world_center_x) <= EPSILON, "%s icon is not on the gameplay centerline" % label)
	_require(absf(overlay.content_safe_root.position.x + overlay.progress_root.position.x + overlay.progress_root.size.x * 0.5 - world_center_x) <= EPSILON, "%s progress is not on the gameplay centerline" % label)
	_require(absf(overlay.content_safe_root.position.x + overlay.loading_label.position.x + overlay.loading_label.size.x * 0.5 - world_center_x) <= EPSILON, "%s text is not on the gameplay centerline" % label)


func _caption_render_bounds(caption: Label) -> Rect2:
	# Control.get_minimum_size uses the current content/font/theme. With the
	# fixed centered, unwrapped caption, this is a conservative text geometry
	# bound plus outline, not a GPU/raster-pixel measurement.
	var text_size := caption.get_minimum_size()
	return Rect2(caption.position + (caption.size - text_size) * 0.5, text_size).grow(float(caption.get_theme_constant("outline_size")))


func _caption_is_inside_safe_area(caption: Label, safe_bounds: Rect2) -> bool:
	var text_rect := _caption_render_bounds(caption)
	return text_rect.has_area() and safe_bounds.encloses(text_rect)


func _assert_caption_counterexamples(overlay: Control, label: String) -> void:
	var caption: Label = overlay.loading_label
	var safe_bounds := Rect2(Vector2.ZERO, overlay.content_safe_root.size)
	var original_position := caption.position
	var original_size := caption.size
	var original_font_size := caption.get_theme_font_size("font_size")
	var had_font_override := caption.has_theme_font_size_override("font_size")
	_require(_caption_is_inside_safe_area(caption, safe_bounds), "%s caption positive fixture is not safe" % label)
	# Move the actual production Label, then query the same safety predicate.
	caption.position = safe_bounds.end + original_size + Vector2.ONE
	_require(not _caption_is_inside_safe_area(caption, safe_bounds), "%s moved-unsafe caption was not detected" % label)
	caption.position = original_position
	caption.size = original_size
	_require(_caption_is_inside_safe_area(caption, safe_bounds), "%s caption did not recover after position restoration" % label)
	# Mutate the real Label's font, letting native theme/text sizing refresh.
	var oversized_font_size := maxi(512, int(ceil(safe_bounds.size.y * 2.0)))
	caption.add_theme_font_size_override("font_size", oversized_font_size)
	await get_tree().process_frame
	var oversized_bounds := _caption_render_bounds(caption)
	_require(caption.get_theme_font_size("font_size") == oversized_font_size and (oversized_bounds.size.x > safe_bounds.size.x or oversized_bounds.size.y > safe_bounds.size.y), "%s enlarged caption did not establish an oversized geometry fixture" % label)
	_require(not _caption_is_inside_safe_area(caption, safe_bounds), "%s enlarged-unsafe caption was not detected" % label)
	if had_font_override:
		caption.add_theme_font_size_override("font_size", original_font_size)
	else:
		caption.remove_theme_font_size_override("font_size")
	# Theme changes dirty Label text/desired size, but the hidden Control's
	# combined minimum cache must be invalidated before set_size reads it.
	caption.update_minimum_size()
	caption.size = original_size
	caption.position = original_position
	_require(_caption_is_inside_safe_area(caption, safe_bounds), "%s caption did not recover after font restoration" % label)
	_assert_vector(caption.size, original_size, "%s restored caption size" % label)
	_assert_vector(caption.position, original_position, "%s restored caption position" % label)
	_require(caption.get_theme_font_size("font_size") == original_font_size and caption.has_theme_font_size_override("font_size") == had_font_override, "%s caption font authority did not restore" % label)

func _assert_handshake_unchanged(overlay: Control) -> void:
	_require(overlay.has_signal("transition_covered") and overlay.has_signal("transition_finished"), "Loading handshake signals changed")
	_require(overlay.has_method("begin_loading") and overlay.has_method("finish_loading"), "Loading handshake methods changed")
	_require(overlay.CONTRACT_ID == "ui.loading.transition.v1", "Loading contract id changed")


func _assert_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_require(actual.distance_to(expected) <= EPSILON, "%s: %s != %s" % [label, actual, expected])


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	_checks_failed = true
	push_error(message)
