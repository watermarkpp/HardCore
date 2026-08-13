extends Control

signal intro_animation_finished

const SLOGAN := "刷是一种状态，刷没有目的没有终点"
const NEXT_SCENE := "res://scenes/character_select.tscn"
const MINIMUM_SKIP_SECONDS := 1.0
const FINAL_PRESENTATION_SECONDS := 4.75

@export var auto_advance := true

@onready var glow_logo: TextureRect = $GlowLogo
@onready var brand_logo: TextureRect = $BrandLogo
@onready var slogan: Label = $Slogan
@onready var fade_overlay: ColorRect = $FadeOverlay

var _elapsed := 0.0
var _transitioning := false
var animation_complete := false


func _ready() -> void:
	set_process_input(true)
	resized.connect(_layout_brand)
	_layout_brand()
	_prepare_animation_state()
	_play_intro.call_deferred()


func _process(delta: float) -> void:
	_elapsed += delta


func _input(event: InputEvent) -> void:
	if not auto_advance or _transitioning or _elapsed < MINIMUM_SKIP_SECONDS:
		return
	if event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch):
		_finish_intro()
		get_viewport().set_input_as_handled()


func _layout_brand() -> void:
	if not is_node_ready():
		return
	var side := minf(size.y * 0.72, size.x * 0.70)
	var logo_size := Vector2(side, side)
	var center := size * 0.5 + Vector2(0.0, -size.y * 0.06)
	for logo: TextureRect in [glow_logo, brand_logo]:
		logo.size = logo_size
		logo.position = center - logo_size * 0.5
		logo.pivot_offset = logo_size * 0.5
	var text_height := maxf(56.0, size.y * 0.10)
	slogan.position = Vector2(size.x * 0.08, size.y * 0.835)
	slogan.size = Vector2(size.x * 0.84, text_height)
	slogan.add_theme_font_size_override("font_size", int(clampf(size.y * 0.046, 25.0, 44.0)))


func _prepare_animation_state() -> void:
	animation_complete = false
	brand_logo.modulate = Color(1.0, 1.0, 1.0, 0.0)
	brand_logo.scale = Vector2(0.90, 0.90)
	glow_logo.modulate = Color(1.0, 0.12, 0.04, 0.0)
	glow_logo.scale = Vector2(0.92, 0.92)
	slogan.text = SLOGAN
	slogan.modulate = Color(1.0, 1.0, 1.0, 0.0)
	slogan.visible_ratio = 0.0
	fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)


func _play_intro() -> void:
	await get_tree().create_timer(0.12).timeout
	if not is_inside_tree():
		return
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(brand_logo, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.tween_property(brand_logo, "scale", Vector2.ONE, 2.20).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	reveal.tween_property(glow_logo, "modulate:a", 0.16, 1.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	reveal.tween_property(glow_logo, "scale", Vector2.ONE, 2.20).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.92).timeout
	if not is_inside_tree():
		return
	var text_reveal := create_tween().set_parallel(true)
	text_reveal.tween_property(slogan, "modulate:a", 1.0, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	text_reveal.tween_property(slogan, "visible_ratio", 1.0, 1.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var pulse := create_tween().set_loops(2)
	pulse.tween_property(glow_logo, "modulate:a", 0.28, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow_logo, "modulate:a", 0.08, 0.62).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Keep the authored final composition visible long enough to survive cold
	# Android window creation and make the entry animation perceptible.
	await get_tree().create_timer(FINAL_PRESENTATION_SECONDS).timeout
	if not is_inside_tree():
		return
	animation_complete = true
	intro_animation_finished.emit()
	if auto_advance:
		_finish_intro()


func _finish_intro() -> void:
	if _transitioning:
		return
	_transitioning = true
	var fade := create_tween()
	fade.tween_property(fade_overlay, "color:a", 1.0, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fade.finished
	if is_inside_tree():
		get_tree().change_scene_to_file(NEXT_SCENE)
