class_name LoadingTransitionOverlay
extends Control

signal transition_covered(request: Dictionary)
signal transition_finished(request: Dictionary)

const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")
const CONTRACT_ID := "ui.loading.transition.v1"
const LOADING_TEXT := "Loading......"
const GAME_ICON := preload("res://assets/branding/game_icon.png")
const EMBER_COUNT := 14

var shade: ColorRect
var game_icon_watermark: TextureRect
var content_safe_root: Control
var red_glow: ColorRect
var vignette: ColorRect
var loading_label: Label
var embers: Array[ColorRect] = []
var transition_id := ""
var _fade_tween: Tween
var _pulse_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	set_meta("stable_id", "ui.loading.overlay")
	shade = ColorRect.new()
	shade.name = "LoadingShade"
	shade.color = Color(0.018, 0.025, 0.035, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
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
	_apply_runtime_layout()
	if not get_viewport().size_changed.is_connected(_apply_runtime_layout):
		get_viewport().size_changed.connect(_apply_runtime_layout)
	hide()


func _process(delta: float) -> void:
	if not visible:
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
	_set_top_left_rect(vignette, Vector2.ZERO, full_size)
	var safe_position := Vector2(maxf(0.0, safe_margins.x), maxf(0.0, safe_margins.y))
	var safe_size := Vector2(
		maxf(1.0, full_size.x - safe_position.x - maxf(0.0, safe_margins.z)),
		maxf(1.0, full_size.y - safe_position.y - maxf(0.0, safe_margins.w))
	)
	_set_top_left_rect(content_safe_root, safe_position, safe_size)
	_set_top_left_rect(loading_label, Vector2.ZERO, safe_size)
	var content_center := safe_size * 0.5
	var icon_size := Vector2.ONE * minf(300.0, safe_size.y * 0.416667)
	_set_top_left_rect(game_icon_watermark, content_center - icon_size * 0.5 - Vector2(0.0, 26.0), icon_size)
	var glow_size := Vector2(minf(280.0, safe_size.x * 0.24), minf(150.0, safe_size.y * 0.208333))
	_set_top_left_rect(red_glow, content_center - glow_size * 0.5 + Vector2(0.0, 19.0), glow_size)
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


func begin_loading(next_transition_id := "") -> void:
	_stop_fade()
	transition_id = str(next_transition_id)
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	modulate.a = 0.0
	show()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_callback(_emit_covered)


func show_loading_immediately(next_transition_id := "") -> void:
	_stop_fade()
	transition_id = str(next_transition_id)
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	modulate.a = 1.0
	show()


func finish_loading() -> void:
	if not visible:
		return
	_stop_fade()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_finish_hide)


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


func _stop_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
