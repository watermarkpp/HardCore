extends Node

const Bounds := preload("res://scripts/ui_style_visual_bounds.gd")
const Adaptive := preload("res://scripts/adaptive_button_style_box.gd")
const Space := preload("res://scripts/ui_shop_detail_space.gd")
var checks := 0
var failures: Array[String] = []
var start_us := 0
var finished := false

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func near(a: Rect2, b: Rect2) -> bool:
	return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)

func _ready() -> void:
	start_us = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not finished and Time.get_ticks_usec() - start_us > 5000000:
		failures.append("SMOKE_RUNTIME_ABORT_OR_TIMEOUT")
		finish()

func _run() -> void:
	var base := Rect2(0, 0, 100, 40)
	var texture := StyleBoxTexture.new()
	texture.set_expand_margin(SIDE_LEFT, 3)
	texture.set_expand_margin(SIDE_TOP, 5)
	texture.set_expand_margin(SIDE_RIGHT, 7)
	texture.set_expand_margin(SIDE_BOTTOM, 11)
	var result := Bounds.style_bounds(texture, base)
	expect(bool(result.ok) and near(result.rect, Rect2(-3, -5, 110, 56)), "TEXTURE_PUBLIC_EXPAND_MARGIN")
	var flat := StyleBoxFlat.new()
	flat.anti_aliasing = false
	flat.set_expand_margin_all(2)
	flat.shadow_size = 4
	flat.shadow_offset = Vector2(8, -3)
	result = Bounds.style_bounds(flat, base)
	expect(bool(result.ok) and near(result.rect, Rect2(-2, -9, 116, 52)), "FLAT_SHADOW_OFFSET_ENVELOPE")
	flat.skew = Vector2(0.2, -0.1)
	var skewed := Bounds.style_bounds(flat, base)
	expect(bool(skewed.ok) and (skewed.rect as Rect2).encloses(result.rect), "SKEW_CONSERVATIVE")
	result = Bounds.style_bounds(StyleBoxEmpty.new(), base)
	expect(bool(result.ok) and near(result.rect, base), "EMPTY_STYLE_NO_PHANTOM_MARGIN")
	result = Bounds.style_bounds(StyleBoxLine.new(), base)
	expect(not bool(result.ok) and str(result.reason).begins_with("UNSUPPORTED_"), "UNKNOWN_RENDERER_NOT_SILENTLY_ACCEPTED")

	var adaptive := Adaptive.new()
	adaptive.compact = texture
	adaptive.standard = StyleBoxTexture.new()
	adaptive.wide = StyleBoxTexture.new()
	adaptive.wide.set_expand_margin(SIDE_RIGHT, 20)
	# Direct field assignment does NOT invoke expensive image generation.
	adaptive.feedback_style = flat
	adaptive.feedback_inset = 6.0
	adaptive.feedback_layered = false
	result = Bounds.style_bounds(adaptive, base)
	expect(bool(result.ok), "REAL_ADAPTIVE_ADAPTER_SUPPORTED")
	expect((result.rect as Rect2).encloses(Rect2(-3, -5, 123, 56)), "ALL_ADAPTIVE_RATIO_FAMILIES_INCLUDED")
	var feedback_bounds := Bounds.style_bounds(flat, base.grow(-6))
	expect((result.rect as Rect2).encloses(feedback_bounds.rect), "ADAPTIVE_NONLAYERED_SHADOW_INCLUDED")
	adaptive.feedback_layered = true
	var layer := StyleBoxTexture.new()
	layer.set_expand_margin(SIDE_BOTTOM, 22)
	adaptive.feedback_background_styles["sample"] = layer
	adaptive.feedback_frame_styles["sample"] = texture
	result = Bounds.style_bounds(adaptive, base)
	expect(bool(result.ok) and (result.rect as Rect2).end.y >= 62, "ADAPTIVE_PREPARED_LAYERS_INCLUDED")
	for mode: String in ["force_widesmall", "force_square", "small_family"]:
		adaptive.set(mode, true)
		result = Bounds.style_bounds(adaptive, base)
		expect(bool(result.ok) and (result.rect as Rect2).encloses(base), "ADAPTIVE_" + mode)
		adaptive.set(mode, false)

	var owner := Control.new()
	owner.position = Vector2(20, 30)
	owner.size = Vector2(500, 400)
	add_child(owner)
	var button := Button.new()
	button.position = Vector2(30, 50)
	button.size = Vector2(100, 40)
	button.scale = Vector2(1.25, 1.5)
	for state: StringName in Bounds.STATES:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover_pressed", texture)
	owner.add_child(button)
	result = Bounds.control_bounds(button)
	expect(bool(result.ok) and (result.rect as Rect2).encloses(Rect2(-3, -5, 110, 56)), "HOVER_PRESSED_NOT_MISSED")
	var actual := Space.visual_rect(owner, button)
	var wanted := Rect2(Vector2(30, 50) + Vector2(-3, -5) * button.scale, Vector2(110, 56) * button.scale)
	expect(near(actual, wanted), "PRODUCTION_VISUAL_RECT_SCALED")
	var ornament := Panel.new()
	ornament.position = Vector2(-10, 0)
	ornament.size = Vector2(20, 20)
	ornament.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	button.add_child(ornament)
	result = Bounds.control_bounds(button)
	expect(bool(result.ok) and (result.rect as Rect2).position.x <= -10, "QUANTITY_ROW_CHILD_ORNAMENT_INCLUDED")
	var before_style := texture.get_expand_margin(SIDE_LEFT)
	for index in range(64):
		Bounds.control_bounds(button)
	expect(texture.get_expand_margin(SIDE_LEFT) == before_style, "MEASUREMENT_DOES_NOT_MUTATE_STYLE")
	owner.queue_free()
	await get_tree().process_frame
	finish()

func finish() -> void:
	if finished:
		return
	finished = true
	print("R31_STYLE_BOUNDS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
