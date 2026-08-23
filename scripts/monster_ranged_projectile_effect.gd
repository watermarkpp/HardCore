class_name MonsterRangedProjectileEffect
extends Node2D

## Presentation-only projectile for monster physical ranged attacks. EnemyActor
## owns target binding and delayed damage; this node only traverses the frozen
## release path and cannot submit damage.

const EFFECT_ID := "monster.physical_arrow.v1"
const SHAFT_COLOR := Color("d7b06a")
const EDGE_COLOR := Color("4b2e1d")
const HEAD_COLOR := Color("e5d39c")

signal playback_finished(effect: Node2D)

var release_descriptor: Dictionary = {}
var release_id := ""
var origin_world_px := Vector2.ZERO
var target_world_px := Vector2.ZERO
var duration_seconds := 0.6
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
	origin_world_px = release_descriptor.get("origin_world_px", Vector2.ZERO)
	target_world_px = release_descriptor.get("target_world_px", origin_world_px)
	duration_seconds = maxf(
		0.001,
		float(release_descriptor.get("duration_seconds", 0.6)),
	)
	global_position = origin_world_px
	rotation = origin_world_px.direction_to(target_world_px).angle()


func _ready() -> void:
	z_as_relative = true
	z_index = 1
	add_to_group("zone_content")
	queue_redraw()
	set_process(visible)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds = minf(duration_seconds, _elapsed_seconds + maxf(0.0, delta))
	var progress := clampf(_elapsed_seconds / duration_seconds, 0.0, 1.0)
	global_position = origin_world_px.lerp(target_world_px, progress)
	if progress >= 1.0:
		_finished = true
		set_process(false)
		playback_finished.emit(self)
		queue_free()


func _draw() -> void:
	# A small opaque arrow remains legible over both bright outdoor tiles and
	# dark caves without inventing a background plate or glow rectangle.
	draw_line(Vector2(-11.0, 0.0), Vector2(7.0, 0.0), EDGE_COLOR, 4.0, true)
	draw_line(Vector2(-11.0, 0.0), Vector2(7.0, 0.0), SHAFT_COLOR, 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(12.0, 0.0),
			Vector2(5.0, -4.0),
			Vector2(5.0, 4.0),
		]),
		HEAD_COLOR,
	)
	draw_line(Vector2(-10.0, 0.0), Vector2(-14.0, -4.0), SHAFT_COLOR, 2.0, true)
	draw_line(Vector2(-10.0, 0.0), Vector2(-14.0, 4.0), SHAFT_COLOR, 2.0, true)


func progress_ratio() -> float:
	return clampf(_elapsed_seconds / duration_seconds, 0.0, 1.0)


func is_finished() -> bool:
	return _finished


func visual_descriptor() -> Dictionary:
	var descriptor := {
		"effect_id": EFFECT_ID,
		"release_id": release_id,
		"origin_world_px": origin_world_px,
		"target_world_px": target_world_px,
		"duration_seconds": duration_seconds,
		"damage_owner": "enemy.physical_projectile_release",
		"release_policy": "frozen_path_once_then_queue_free",
		"background_policy": "transparent_procedural_only",
	}
	descriptor.make_read_only()
	return descriptor
