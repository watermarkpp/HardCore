extends Control

signal intro_animation_finished
signal intro_first_frame_presented

const SLOGAN := "刷是一种状态，刷没有目的没有终点"
const NEXT_SCENE := "res://scenes/character_select.tscn"
const MINIMUM_SKIP_SECONDS := 1.0
# The first drawable frame is already an authored CG frame.  Android and the
# Godot boot surface may remain visible until this frame is presented, so the
# runtime intro must never begin from an empty black frame or a translucent
# logo that reveals a different startup surface underneath it.
const INITIAL_LOGO_ALPHA := 1.0
const INITIAL_GLOW_ALPHA := 0.28
# StartupLoading, rather than a fixed timer, owns the final-frame hold. The
# authored motion completes once and remains visible exactly as long as the
# character-selection scene still needs to become ready.
const FINAL_PRESENTATION_SECONDS := 0.0

@export var auto_advance := true

@onready var glow_logo: TextureRect = $GlowLogo
@onready var brand_logo: TextureRect = $BrandLogo
@onready var slogan: Label = $Slogan
@onready var fade_overlay: ColorRect = $FadeOverlay

var _elapsed := 0.0
var _transitioning := false
var animation_complete := false
var first_frame_presented := false

const CODE_COVER_CONTRACT_ID := "startup.brand_intro.opaque_preparation.v1"
var _code_cover_serial := 0
var _code_presented_serial := -1
var _code_background_id := 0
var _code_cover_rect := Rect2()
var _code_viewport_rect := Rect2()
@onready var _code_background: ColorRect = $Background


func _ready() -> void:
	set_process_input(true)
	resized.connect(_layout_brand)
	_layout_brand()
	_prepare_animation_state()
	visibility_changed.connect(_invalidate_code_cover)
	resized.connect(_invalidate_code_cover)
	_code_background.visibility_changed.connect(_invalidate_code_cover)
	_code_background.tree_exiting.connect(_invalidate_code_cover)
	_code_background.item_rect_changed.connect(_invalidate_code_cover)
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
	first_frame_presented = false
	_code_cover_serial += 1
	_invalidate_code_cover()
	brand_logo.modulate = Color(1.0, 1.0, 1.0, INITIAL_LOGO_ALPHA)
	brand_logo.scale = Vector2.ONE
	glow_logo.modulate = Color(1.0, 0.12, 0.04, INITIAL_GLOW_ALPHA)
	glow_logo.scale = Vector2.ONE
	slogan.text = SLOGAN
	slogan.modulate = Color(1.0, 1.0, 1.0, 0.0)
	slogan.visible_ratio = 0.0
	fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)


func _play_intro() -> void:
	# Publish the opaque authored start pose before starting any motion.  This
	# gives StartupLoading a precise first-frame boundary and removes the old
	# black -> translucent-logo lead-in from the animation itself.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# Match the existing Loading overlay's explicit headless frame protocol.
	# Graphical runs still require the actual rendered frame before admission.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	first_frame_presented = true
	if _code_surface_covers_viewport():
		_code_presented_serial = _code_cover_serial
		_code_background_id = _code_background.get_instance_id()
		_code_cover_rect = _code_surface_rect()
		_code_viewport_rect = get_viewport_rect()
	intro_first_frame_presented.emit()

	var text_reveal := create_tween().set_parallel(true)
	text_reveal.tween_property(slogan, "modulate:a", 1.0, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	text_reveal.tween_property(slogan, "visible_ratio", 1.0, 1.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var pulse := create_tween().set_loops(2)
	pulse.tween_property(glow_logo, "modulate:a", 0.28, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow_logo, "modulate:a", 0.08, 0.62).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# The pulse is the longest authored tween. Waiting for it means all logo and
	# slogan motion has reached its exact final frame without an arbitrary delay.
	# StartupLoading keeps this node unchanged until handoff.
	await pulse.finished
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


func _invalidate_code_cover() -> void:
	_code_presented_serial = -1
	_code_background_id = 0

func _code_surface_rect() -> Rect2:
	var transform := _code_background.get_global_transform_with_canvas()
	return Rect2(transform.origin, _code_background.size * Vector2(transform.x.x, transform.y.y))

func _code_surface_covers_viewport() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree() or _transitioning or auto_advance:
		return false
	if not is_instance_valid(_code_background) or not _code_background.is_inside_tree() or _code_background.is_queued_for_deletion() or not is_same(_code_background.get_parent(), self) or not _code_background.is_visible_in_tree():
		return false
	if _code_background.color.a != 1.0 or _code_background.modulate.a != 1.0 or _code_background.self_modulate.a != 1.0:
		return false
	var transform := _code_background.get_global_transform_with_canvas()
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
	return get_viewport_rect().has_area() and _code_surface_rect().encloses(get_viewport_rect())

func code_preparation_cover_receipt() -> Dictionary:
	if not first_frame_presented or _code_presented_serial != _code_cover_serial or not _code_surface_covers_viewport():
		return {}
	if _code_background.get_instance_id() != _code_background_id or _code_surface_rect() != _code_cover_rect or get_viewport_rect() != _code_viewport_rect:
		_invalidate_code_cover()
		return {}
	return {"contract_id": CODE_COVER_CONTRACT_ID, "serial": _code_cover_serial,
		"overlay_instance_id": get_instance_id(), "shade_instance_id": _code_background_id,
		"cover_rect": _code_cover_rect, "viewport_rect": _code_viewport_rect,
		"presentation_mode": "headless_process_frame" if DisplayServer.get_name() == "headless" else "rendered_frame_post_draw"}

func code_preparation_cover_current(receipt: Dictionary) -> bool:
	var current: Dictionary = code_preparation_cover_receipt()
	return not current.is_empty() and current == receipt
