class_name MonsterTargetMagicEffect
extends Node2D

## Presentation-only target lightning for Race 200 monster magic. The effect is
## created at the frozen target footpoint immediately; EnemyActor owns the
## delayed magic-defense transaction.

const EFFECT_ID := "monster.target_lightning.v1"
const DURATION_SECONDS := 0.42
const BOLT_HEIGHT_PX := 104.0
const CORE_COLOR := Color("e8fff4")
const GLOW_COLOR := Color("68e7d0")

signal playback_finished(effect: Node2D)

var release_descriptor: Dictionary = {}
var release_id := ""
var target_world_px := Vector2.ZERO
var _elapsed_seconds := 0.0
var _finished := false


static func create_visual(descriptor: Dictionary) -> Node2D:
	var effect := new()
	effect.setup(descriptor)
	return effect


func setup(descriptor: Dictionary) -> void:
	release_descriptor = descriptor if descriptor.is_read_only() else descriptor.duplicate(true)
	if not release_descriptor.is_read_only():
		release_descriptor.make_read_only()
	if str(release_descriptor.get("effect_id", "")) != EFFECT_ID:
		visible = false
		set_process(false)
		return
	release_id = str(release_descriptor.get("release_id", ""))
	target_world_px = release_descriptor.get("target_world_px", Vector2.ZERO)
	global_position = target_world_px


func _ready() -> void:
	z_as_relative = true
	z_index = 2
	add_to_group("zone_content")
	queue_redraw()
	set_process(visible)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds = minf(
		DURATION_SECONDS,
		_elapsed_seconds + maxf(0.0, delta),
	)
	queue_redraw()
	if _elapsed_seconds >= DURATION_SECONDS:
		_finished = true
		set_process(false)
		playback_finished.emit(self)
		queue_free()


func _draw() -> void:
	var progress := clampf(_elapsed_seconds / DURATION_SECONDS, 0.0, 1.0)
	var alpha := 1.0 - progress
	var phase := int(floor(progress * 6.0))
	var points := PackedVector2Array([
		Vector2(2.0, -BOLT_HEIGHT_PX),
		Vector2(-7.0 if phase % 2 == 0 else 8.0, -78.0),
		Vector2(5.0 if phase % 3 == 0 else -4.0, -52.0),
		Vector2(-3.0 if phase % 2 == 0 else 5.0, -25.0),
		Vector2.ZERO,
	])
	draw_polyline(points, Color(GLOW_COLOR, alpha * 0.65), 8.0, true)
	draw_polyline(points, Color(CORE_COLOR, alpha), 2.5, true)
	draw_arc(Vector2.ZERO, 13.0 + progress * 8.0, 0.0, TAU, 24, Color(GLOW_COLOR, alpha), 2.0, true)


func current_progress() -> float:
	return clampf(_elapsed_seconds / DURATION_SECONDS, 0.0, 1.0)


func visual_descriptor() -> Dictionary:
	var descriptor := {
		"effect_id": EFFECT_ID,
		"release_id": release_id,
		"target_world_px": target_world_px,
		"duration_seconds": DURATION_SECONDS,
		"damage_owner": "enemy.target_magic_release",
		"background_policy": "transparent_procedural_only",
	}
	descriptor.make_read_only()
	return descriptor
