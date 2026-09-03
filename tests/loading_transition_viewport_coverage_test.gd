extends Node

const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const EPSILON := 0.001


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
	]
	for entry: Dictionary in cases:
		var viewport_size: Vector2 = entry.window
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
	_assert_handshake_unchanged(overlay)
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	assert(hud.loading_transition_overlay.get_parent() == hud, "Loading overlay must be a direct CanvasLayer child")
	assert(hud.loading_transition_overlay.get_parent().name != "MobileSafeRoot", "Loading overlay must not inherit safe-area clipping")
	print("LOADING_TRANSITION_VIEWPORT_COVERAGE_PASS: 2400x1080/2340x1080/1920x1080、左右安全区、四边零缝隙与安全区内容均通过")
	get_tree().quit(0)


func _assert_full_viewport_rect(control: Control, viewport_size: Vector2, label: String) -> void:
	_assert_vector(control.position, Vector2.ZERO, "%s origin" % label)
	_assert_vector(control.size, viewport_size, "%s size" % label)
	assert(control.position.x <= EPSILON and control.position.y <= EPSILON, "%s left/top gap" % label)
	assert(control.position.x + control.size.x >= viewport_size.x - EPSILON, "%s right gap" % label)
	assert(control.position.y + control.size.y >= viewport_size.y - EPSILON, "%s bottom gap" % label)


func _assert_safe_content(overlay: Control, label: String) -> void:
	var safe_bounds := Rect2(Vector2.ZERO, overlay.content_safe_root.size)
	assert(safe_bounds.encloses(Rect2(overlay.game_icon_watermark.position, overlay.game_icon_watermark.size)), "%s icon exceeds safe area" % label)
	assert(safe_bounds.encloses(Rect2(overlay.red_glow.position, overlay.red_glow.size)), "%s glow exceeds safe area" % label)
	assert(safe_bounds.encloses(Rect2(overlay.loading_label.position, overlay.loading_label.size)), "%s text exceeds safe area" % label)
	assert(absf(overlay.game_icon_watermark.position.x + overlay.game_icon_watermark.size.x * 0.5 - safe_bounds.size.x * 0.5) <= EPSILON, "%s icon is not horizontally centered" % label)
	assert(absf(overlay.loading_label.position.x + overlay.loading_label.size.x * 0.5 - safe_bounds.size.x * 0.5) <= EPSILON, "%s text is not horizontally centered" % label)


func _assert_handshake_unchanged(overlay: Control) -> void:
	assert(overlay.has_signal("transition_covered") and overlay.has_signal("transition_finished"), "Loading handshake signals changed")
	assert(overlay.has_method("begin_loading") and overlay.has_method("finish_loading"), "Loading handshake methods changed")
	assert(overlay.CONTRACT_ID == "ui.loading.transition.v1", "Loading contract id changed")


func _assert_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	assert(actual.distance_to(expected) <= EPSILON, "%s: %s != %s" % [label, actual, expected])
