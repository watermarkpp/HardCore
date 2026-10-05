class_name UIRelicProcEffect
extends Node2D

const GROW_SECONDS := 0.45
const HOLD_SECONDS := 0.5
const FADE_SECONDS := 0.35
const DURATION_SECONDS := GROW_SECONDS + HOLD_SECONDS + FADE_SECONDS
const DECAL_TEXTURE := preload("res://assets/art/effects/relic_proc_skull.png")
const FINAL_WIDTH_PX := 126.0
const VISUAL_OFFSET_PX := Vector2(0.0, 5.0)

var _elapsed := DURATION_SECONDS
var _decal: Sprite2D


func _ready() -> void:
	# The asset is already projected onto the game's oblique ground plane.
	# Keep the approved gameplay footpoint; offset only this visual by 5 px south.
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_decal = Sprite2D.new()
	_decal.texture = DECAL_TEXTURE
	_decal.centered = true
	_decal.position = VISUAL_OFFSET_PX
	add_child(_decal)
	visible = false
	set_process(false)


func replay(anchor: Vector2) -> void:
	position = anchor
	_elapsed = 0.0
	visible = true
	set_process(true)
	_update_decal()


func hold_at(anchor: Vector2, progress := 0.4) -> void:
	# Calibration preview uses the same image and exact anchor as runtime.
	position = anchor
	_elapsed = DURATION_SECONDS * clampf(progress, 0.0, 0.99)
	visible = true
	set_process(false)
	_update_decal()


func _process(delta: float) -> void:
	_elapsed = minf(DURATION_SECONDS, _elapsed + delta)
	_update_decal()
	if _elapsed >= DURATION_SECONDS:
		visible = false
		set_process(false)


func _update_decal() -> void:
	if not is_instance_valid(_decal):
		return
	var growth := lerpf(0.62, 1.0, smoothstep(0.0, GROW_SECONDS, _elapsed))
	var opacity := smoothstep(0.0, 0.12, _elapsed) * (
		1.0 - smoothstep(GROW_SECONDS + HOLD_SECONDS, DURATION_SECONDS, _elapsed)
	)
	_decal.scale = Vector2.ONE * (FINAL_WIDTH_PX / float(DECAL_TEXTURE.get_width()) * growth)
	_decal.modulate = Color(1.0, 1.0, 1.0, opacity)
