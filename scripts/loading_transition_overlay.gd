class_name LoadingTransitionOverlay
extends Control

signal transition_covered(request: Dictionary)
signal transition_finished(request: Dictionary)

const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const CONTRACT_ID := "ui.loading.transition.v1"
const LOADING_TEXT := "Loading......"
const GAME_ICON := preload("res://assets/branding/game_icon.png")
const BATTLEFIELD_BACKGROUND := preload(
	"res://assets/ui/gothic_theme/v1/loading_battlefield_background.jpg"
)
const EMBER_COUNT := 14

var shade: ColorRect
var battlefield_background: TextureRect
var game_icon_watermark: TextureRect
var content_safe_root: Control
var red_glow: ColorRect
var vignette: ColorRect
var loading_label: Label
var progress_root: Control
var progress_track: ColorRect
var progress_fill: ColorRect
var progress_stage: Label
var progress_percent: Label
var embers: Array[ColorRect] = []
var transition_id := ""
var _progress_value := 0.0
var _coverage_request_serial := 0
var _presented_coverage_serial := -1
var _presented_shade_instance_id := 0
var _presented_cover_rect := Rect2()
var _presented_viewport_rect := Rect2()
var _pulse_time := 0.0
var _holding_final := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	set_meta("stable_id", "ui.loading.overlay")
	shade = ColorRect.new()
	shade.name = "LoadingShade"
	shade.color = Color(0.018, 0.025, 0.035, 1.0)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	# Any physical surface change retires the old presentation witness.
	shade.visibility_changed.connect(_invalidate_code_preparation_cover)
	shade.tree_exiting.connect(_invalidate_code_preparation_cover)
	shade.item_rect_changed.connect(_invalidate_code_preparation_cover)
	battlefield_background = TextureRect.new()
	battlefield_background.name = "BattlefieldBackground"
	battlefield_background.texture = BATTLEFIELD_BACKGROUND
	battlefield_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	battlefield_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	battlefield_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	battlefield_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield_background.set_meta("stable_id", "ui.loading.battlefield_background")
	add_child(battlefield_background)
	_build_vignette()
	content_safe_root = Control.new()
	content_safe_root.name = "LoadingSafeContent"
	content_safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_safe_root.set_meta("stable_id", "ui.loading.safe_content")
	add_child(content_safe_root)
	_build_atmosphere()
	loading_label = Label.new()
	loading_label.name = "LoadingText"
	loading_label.text = LOADING_TEXT
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 25)
	loading_label.add_theme_color_override("font_color", Color("ddd7ce"))
	loading_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.018, 0.8))
	loading_label.add_theme_constant_override("outline_size", 1)
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_safe_root.add_child(loading_label)
	_build_progress()
	_apply_runtime_layout()
	if not get_viewport().size_changed.is_connected(_apply_runtime_layout):
		get_viewport().size_changed.connect(_apply_runtime_layout)
	hide()


func _process(delta: float) -> void:
	if not visible:
		return
	if _holding_final:
		return
	_pulse_time += delta
	var breathing := sin(_pulse_time * 2.2)
	loading_label.modulate.a = 0.875 + breathing * 0.125
	var watermark_material := game_icon_watermark.material as ShaderMaterial
	watermark_material.set_shader_parameter("opacity", 0.55 + breathing * 0.07)
	var glow_material := red_glow.material as ShaderMaterial
	glow_material.set_shader_parameter("strength", 0.14 + breathing * 0.045)
	for ember: ColorRect in embers:
		var position_value := ember.position
		position_value.y -= float(ember.get_meta("speed", 5.0)) * delta
		position_value.x += sin(_pulse_time * float(ember.get_meta("drift", 0.5)) + float(ember.get_meta("phase", 0.0))) * delta * 1.5
		if position_value.y < content_safe_root.size.y * 0.07:
			position_value.y = content_safe_root.size.y * 0.958
		ember.position = position_value


func apply_layout(viewport_size: Vector2, safe_margins := Vector4.ZERO) -> void:
	var full_size := Vector2(maxf(1.0, viewport_size.x), maxf(1.0, viewport_size.y))
	_set_top_left_rect(self, Vector2.ZERO, full_size)
	_set_top_left_rect(shade, Vector2.ZERO, full_size)
	_set_top_left_rect(battlefield_background, Vector2.ZERO, full_size)
	_set_top_left_rect(vignette, Vector2.ZERO, full_size)
	var safe_position := Vector2(maxf(0.0, safe_margins.x), maxf(0.0, safe_margins.y))
	var safe_size := Vector2(
		maxf(1.0, full_size.x - safe_position.x - maxf(0.0, safe_margins.z)),
		maxf(1.0, full_size.y - safe_position.y - maxf(0.0, safe_margins.w))
	)
	_set_top_left_rect(content_safe_root, safe_position, safe_size)
	# Center the caption on the viewport, like the logo and progress track.
	_set_top_left_rect(loading_label, Vector2(-safe_position.x, 0.0), Vector2(full_size.x, safe_size.y))
	# The gameplay center is the full viewport center. On landscape phones a
	# one-sided cutout makes the safe rectangle's midpoint drift to the east.
	var content_center := Vector2(full_size.x * 0.5 - safe_position.x, safe_size.y * 0.5)
	var icon_size := Vector2.ONE * minf(300.0, safe_size.y * 0.416667)
	_set_top_left_rect(game_icon_watermark, content_center - icon_size * 0.5 - Vector2(0.0, 26.0), icon_size)
	var glow_size := Vector2(minf(280.0, safe_size.x * 0.24), minf(150.0, safe_size.y * 0.208333))
	_set_top_left_rect(red_glow, content_center - glow_size * 0.5 + Vector2(0.0, 19.0), glow_size)
	var progress_width := minf(490.0, safe_size.x * 0.62)
	_set_top_left_rect(progress_root, Vector2(content_center.x - progress_width * 0.5, safe_size.y * 0.78), Vector2(progress_width, 63.0))
	_set_top_left_rect(progress_track, Vector2(0.0, 28.0), Vector2(progress_width, 12.0))
	_update_progress_fill()
	_set_top_left_rect(progress_stage, Vector2.ZERO, Vector2(progress_width - 68.0, 25.0))
	_set_top_left_rect(progress_percent, Vector2(progress_width - 66.0, 0.0), Vector2(66.0, 25.0))
	for ember: ColorRect in embers:
		var normalized_position: Vector2 = ember.get_meta("normalized_position", Vector2.ZERO)
		ember.position = Vector2(normalized_position.x * safe_size.x, normalized_position.y * safe_size.y)


func _apply_runtime_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe_rect := Rect2(DisplayServer.get_display_safe_area())
	var margins := MobileLayoutRules.safe_margins(window_size, safe_rect, viewport_size)
	apply_layout(viewport_size, margins)


func _set_top_left_rect(control: Control, next_position: Vector2, next_size: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = next_position
	control.size = next_size


func _build_atmosphere() -> void:
	game_icon_watermark = TextureRect.new()
	game_icon_watermark.name = "GameIconWatermark"
	game_icon_watermark.texture = GAME_ICON
	game_icon_watermark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	game_icon_watermark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	game_icon_watermark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	game_icon_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_icon_watermark.set_meta("stable_id", "ui.loading.game_icon_watermark")
	var watermark_shader := Shader.new()
	watermark_shader.code = """
shader_type canvas_item;
uniform float opacity : hint_range(0.0, 0.8) = 0.55;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float brightness = max(source.r, max(source.g, source.b));
	float mask = smoothstep(0.075, 0.34, brightness);
	vec2 focus_point = (UV - vec2(0.5)) * vec2(1.0, 0.86);
	float edge_fade = 1.0 - smoothstep(0.38, 0.68, length(focus_point));
	vec3 tint = mix(source.rgb, vec3(0.56, 0.47, 0.40), 0.16);
	COLOR = vec4(tint, source.a * mask * edge_fade * opacity);
}
"""
	var watermark_material := ShaderMaterial.new()
	watermark_material.shader = watermark_shader
	game_icon_watermark.material = watermark_material
	content_safe_root.add_child(game_icon_watermark)

	red_glow = ColorRect.new()
	red_glow.name = "RedBreathingGlow"
	red_glow.color = Color.WHITE
	red_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_glow.set_meta("stable_id", "ui.loading.red_breathing_glow")
	var glow_shader := Shader.new()
	glow_shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 0.3) = 0.14;
void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(1.0, 2.1);
	float fade = 1.0 - smoothstep(0.08, 0.62, length(point));
	COLOR = vec4(0.48, 0.025, 0.012, fade * strength);
}
"""
	var glow_material := ShaderMaterial.new()
	glow_material.shader = glow_shader
	red_glow.material = glow_material
	content_safe_root.add_child(red_glow)

	for index in range(EMBER_COUNT):
		var ember := ColorRect.new()
		ember.name = "Ember%02d" % (index + 1)
		var ember_size := 1.0 + float(index % 2)
		ember.size = Vector2(ember_size, ember_size)
		ember.position = Vector2(
			80.0 + fmod(float(index * 97), 1120.0),
			96.0 + fmod(float(index * 137), 570.0)
		)
		ember.set_meta("normalized_position", ember.position / Vector2(1280.0, 720.0))
		ember.color = Color(0.64, 0.10, 0.035, 0.12 + float(index % 4) * 0.035)
		ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ember.set_meta("speed", 3.0 + float(index % 5))
		ember.set_meta("drift", 0.35 + float(index % 3) * 0.18)
		ember.set_meta("phase", float(index) * 0.73)
		embers.append(ember)
		content_safe_root.add_child(ember)


func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.name = "EdgeVignette"
	vignette.color = Color.WHITE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_meta("stable_id", "ui.loading.edge_vignette")
	var vignette_shader := Shader.new()
	vignette_shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(0.86, 1.0);
	float edge = smoothstep(0.30, 0.72, length(point));
	COLOR = vec4(0.018, 0.014, 0.012, edge * 0.58);
}
"""
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = vignette_shader
	vignette.material = vignette_material
	add_child(vignette)


func _build_progress() -> void:
	progress_root = Control.new()
	progress_root.name = "LoadingProgress"
	progress_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_root.set_meta("stable_id", "ui.loading.progress")
	content_safe_root.add_child(progress_root)
	progress_track = ColorRect.new()
	progress_track.name = "ProgressTrack"
	progress_track.color = Color("8e6c4d")
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_root.add_child(progress_track)
	var unfilled := ColorRect.new()
	unfilled.name = "Unfilled"
	unfilled.color = Color("211a19")
	unfilled.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unfilled.position = Vector2(2.0, 2.0)
	unfilled.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	unfilled.offset_left = 2.0
	unfilled.offset_top = 2.0
	unfilled.offset_right = -2.0
	unfilled.offset_bottom = -2.0
	progress_track.add_child(unfilled)
	progress_fill = ColorRect.new()
	progress_fill.name = "ProgressFill"
	progress_fill.color = Color("b44228")
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_track.add_child(progress_fill)
	progress_stage = Label.new()
	progress_stage.name = "ProgressStage"
	progress_stage.text = "准备进入世界"
	progress_stage.add_theme_color_override("font_color", Color("dcc7a5"))
	progress_stage.add_theme_font_size_override("font_size", 17)
	progress_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_root.add_child(progress_stage)
	progress_percent = Label.new()
	progress_percent.name = "ProgressPercent"
	progress_percent.text = "0%"
	progress_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_percent.add_theme_color_override("font_color", Color("f1c584"))
	progress_percent.add_theme_font_size_override("font_size", 17)
	progress_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_root.add_child(progress_percent)


func _update_progress_fill() -> void:
	progress_fill.position = Vector2(2.0, 2.0)
	progress_fill.size = Vector2(maxf(0.0, (progress_track.size.x - 4.0) * _progress_value), 8.0)


func set_loading_progress(request_transition_id: String, completed: float, stage: String) -> void:
	if request_transition_id != transition_id:
		return
	_progress_value = maxf(_progress_value, clampf(completed, 0.0, 1.0))
	progress_stage.text = stage
	progress_percent.text = "%d%%" % roundi(_progress_value * 100.0)
	_update_progress_fill()


func _reset_progress() -> void:
	_progress_value = 0.0
	progress_stage.text = "准备进入世界"
	progress_percent.text = "0%"
	_update_progress_fill()


func begin_loading(next_transition_id := "") -> void:
	_coverage_request_serial += 1
	var request_serial := _coverage_request_serial
	_holding_final = false
	transition_id = str(next_transition_id)
	var request_transition_id := transition_id
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	_reset_progress()
	# The complete overlay remains opaque for every frame in which it is visible.
	# Only the internal text/glow atmosphere animates; gameplay and HUD pixels
	# must never become part of the Loading presentation.
	modulate.a = 1.0
	show()
	_emit_covered_after_present(request_serial, request_transition_id)


func show_loading_immediately(next_transition_id := "") -> void:
	_coverage_request_serial += 1
	_holding_final = false
	transition_id = str(next_transition_id)
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	_reset_progress()
	modulate.a = 1.0
	show()


## Startup and other finite loading phases may hold the completed visual while
## an asynchronous resource finishes. Existing map transitions never call
## this API and retain their breathing/ember animation unchanged.
func freeze_final_visual() -> void:
	_holding_final = true
	loading_label.modulate.a = 1.0
	var watermark_material := game_icon_watermark.material as ShaderMaterial
	watermark_material.set_shader_parameter("opacity", 0.55)
	var glow_material := red_glow.material as ShaderMaterial
	glow_material.set_shader_parameter("strength", 0.14)


func finish_loading() -> void:
	if not visible:
		return
	_coverage_request_serial += 1
	_finish_hide()


func _emit_covered_after_present(request_serial: int, request_transition_id: String) -> void:
	# Keep the handshake asynchronous so callers can attach their signal await
	# immediately after begin_loading(). Production waits for a rendered opaque
	# frame before it permits world replacement.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if (
		request_serial != _coverage_request_serial
		or not visible
		or request_transition_id != transition_id
	):
		return
	_invalidate_code_preparation_cover()
	if _code_preparation_surface_covers_viewport():
		_presented_coverage_serial = request_serial
		_presented_shade_instance_id = shade.get_instance_id()
		_presented_cover_rect = _code_preparation_surface_rect()
		_presented_viewport_rect = get_viewport_rect()
	_emit_covered()


func _invalidate_code_preparation_cover() -> void:
	_presented_coverage_serial = -1
	_presented_shade_instance_id = 0


func _code_preparation_surface_rect() -> Rect2:
	var transform := shade.get_global_transform_with_canvas()
	return Rect2(transform.origin, shade.size * Vector2(transform.x.x, transform.y.y))


func _code_preparation_surface_covers_viewport() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree():
		return false
	if not is_instance_valid(shade) or not shade.is_inside_tree() or shade.is_queued_for_deletion() or not is_same(shade.get_parent(), self) or not shade.is_visible_in_tree():
		return false
	if shade.color.a != 1.0 or shade.modulate.a != 1.0 or shade.self_modulate.a != 1.0:
		return false
	# The existing overlay layout is an axis-aligned full viewport rectangle.
	# Reject rotation/skew and clipping ancestors instead of using an AABB
	# which could claim cover while leaving a corner of the viewport exposed.
	var transform := shade.get_global_transform_with_canvas()
	if transform.x.y != 0.0 or transform.y.x != 0.0 or transform.x.x <= 0.0 or transform.y.y <= 0.0:
		return false
	var ancestor: Node = self
	var depth := 0
	while ancestor != null:
		depth += 1
		if depth > 64:
			return false
		if ancestor is CanvasItem and (not ancestor.is_visible_in_tree() or ancestor.modulate.a != 1.0 or ancestor.self_modulate.a != 1.0):
			return false
		if ancestor is Control and ancestor.clip_contents:
			return false
		ancestor = ancestor.get_parent()
	var viewport_rect := get_viewport_rect()
	return viewport_rect.has_area() and _code_preparation_surface_rect().encloses(viewport_rect)


func code_preparation_cover_receipt() -> Dictionary:
	if _presented_coverage_serial != _coverage_request_serial or not _code_preparation_surface_covers_viewport():
		return {}
	if shade.get_instance_id() != _presented_shade_instance_id or _code_preparation_surface_rect() != _presented_cover_rect or get_viewport_rect() != _presented_viewport_rect:
		_invalidate_code_preparation_cover()
		return {}
	return {"contract_id": CONTRACT_ID, "transition_id": transition_id,
		"serial": _coverage_request_serial, "overlay_instance_id": get_instance_id(),
		"shade_instance_id": _presented_shade_instance_id,
		"cover_rect": _presented_cover_rect, "viewport_rect": _presented_viewport_rect,
		"presentation_mode": "headless_process_frame" if DisplayServer.get_name() == "headless" else "rendered_frame_post_draw"}


func code_preparation_cover_current(receipt: Dictionary) -> bool:
	var current := code_preparation_cover_receipt()
	return not current.is_empty() and receipt == current


func _emit_covered() -> void:
	transition_covered.emit({
		"contract_id": CONTRACT_ID,
		"transition_id": transition_id,
	})


func _finish_hide() -> void:
	hide()
	modulate.a = 1.0
	transition_finished.emit({
		"contract_id": CONTRACT_ID,
		"transition_id": transition_id,
	})
