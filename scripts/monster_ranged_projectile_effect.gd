class_name MonsterRangedProjectileEffect
extends Node2D

## Presentation-only projectile for monster physical ranged attacks. EnemyActor
## owns target binding and delayed damage; this node only traverses the frozen
## release path and cannot submit damage.
##
## The live 1.76 client uses TFlyingArrow (not TFlyingAxe) with
## WEffectImg[ARCHERBASE2 + Dir16 + curframe]. The mtFlyArrow constructor has
## one visible frame, so this node selects the exact transparent source frame
## for the original 16 directions and keeps the original WIL hotspot offsets.

const EFFECT_ID := "monster.physical_arrow.v1"
const SOURCE_MANIFEST_PATH := (
	"res://assets/data/monster_physical_projectile_sources_v1.json"
)
const SOURCE_FRAME_ROOT := (
	"res://assets/art/monsters/effects/monster_physical_arrow_v1"
)
const SOURCE_ARCHER_BASE := 272
const SOURCE_FRAME_COUNT := 16
const SOURCE_FRAME_TIME_MS := 30
const UNIT_X_PX := 48.0
const UNIT_Y_PX := 32.0
const ORIGINAL_DRAW_Y_OFFSET_PX := -46.0
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

# WEffectImg metadata returned by TWMImages.GetCachedImage. These are the
# original per-direction hotspots, not hand-tuned visual offsets.
const SOURCE_FRAME_OFFSETS := [
	Vector2(22.0, -5.0),
	Vector2(15.0, -4.0),
	Vector2(9.0, 1.0),
	Vector2(3.0, 8.0),
	Vector2(2.0, 15.0),
	Vector2(1.0, 8.0),
	Vector2(7.0, 5.0),
	Vector2(14.0, 2.0),
	Vector2(21.0, 3.0),
	Vector2(12.0, 1.0),
	Vector2(4.0, 4.0),
	Vector2(-2.0, 8.0),
	Vector2(-7.0, 15.0),
	Vector2(-4.0, 9.0),
	Vector2(1.0, 2.0),
	Vector2(12.0, -2.0),
]

signal playback_finished(effect: Node2D)

var release_descriptor: Dictionary = {}
var release_id := ""
var origin_world_px := Vector2.ZERO
var target_world_px := Vector2.ZERO
var duration_seconds := 0.6
var _elapsed_seconds := 0.0
var _finished := false
var _blocked_by_world := false
var _direction16 := 0
var _source_frame_index := SOURCE_ARCHER_BASE
var _source_frame_offset := Vector2.ZERO
var _previous_world_px := Vector2.ZERO
var _sprite: Sprite2D


static func create_visual(descriptor: Dictionary) -> Node2D:
	var effect := new()
	effect.setup(descriptor)
	return effect


func setup(descriptor: Dictionary) -> void:
	release_descriptor = descriptor if descriptor.is_read_only() else descriptor.duplicate(true)
	if not release_descriptor.is_read_only():
		release_descriptor.make_read_only()
	if str(release_descriptor.get("effect_id", "")) != EFFECT_ID:
		_reject_visual()
		return
	release_id = str(release_descriptor.get("release_id", ""))
	var origin_value: Variant = release_descriptor.get("origin_world_px", Vector2.ZERO)
	var target_value: Variant = release_descriptor.get("target_world_px", origin_value)
	origin_world_px = origin_value if origin_value is Vector2 else Vector2.ZERO
	target_world_px = target_value if target_value is Vector2 else origin_world_px
	if not origin_world_px.is_finite() or not target_world_px.is_finite():
		_reject_visual()
		return
	duration_seconds = maxf(
		0.001,
		float(release_descriptor.get("duration_seconds", 0.6)),
	)
	_direction16 = _direction16_for_line(origin_world_px, target_world_px)
	_source_frame_index = SOURCE_ARCHER_BASE + _direction16
	_source_frame_offset = SOURCE_FRAME_OFFSETS[_direction16]
	global_position = origin_world_px
	_previous_world_px = origin_world_px
	rotation = 0.0
	if is_inside_tree():
		_install_source_frame()


func _ready() -> void:
	z_as_relative = true
	z_index = 1
	add_to_group("zone_content")
	_install_source_frame()
	set_process(visible and _sprite != null)


func _install_source_frame() -> void:
	if not visible or _sprite != null:
		return
	var source_texture := load(source_texture_path()) as Texture2D
	if source_texture == null:
		_reject_visual()
		return
	_sprite = Sprite2D.new()
	_sprite.name = "SourceFrame"
	_sprite.texture = source_texture
	_sprite.centered = false
	_sprite.position = Vector2(
		_source_frame_offset.x - UNIT_X_PX * 0.5,
		_source_frame_offset.y - UNIT_Y_PX * 0.5 + ORIGINAL_DRAW_Y_OFFSET_PX,
	)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds = minf(duration_seconds, _elapsed_seconds + maxf(0.0, delta))
	var progress := clampf(_elapsed_seconds / duration_seconds, 0.0, 1.0)
	var next_world_px := origin_world_px.lerp(target_world_px, progress)
	if not _world_segment_is_clear(_previous_world_px, next_world_px):
		_finish(true)
		return
	global_position = next_world_px
	_previous_world_px = next_world_px
	if progress >= 1.0:
		_finish(false)


func _world_segment_is_clear(from_world_px: Vector2, to_world_px: Vector2) -> bool:
	var world := get_world_2d()
	if world == null:
		return false
	var physics_space: PhysicsDirectSpaceState2D = world.direct_space_state
	if physics_space == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(
		from_world_px,
		to_world_px,
		WorldSpatialRulesScript.WORLD_MASK,
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return physics_space.intersect_ray(query).is_empty()


func _finish(blocked_by_world: bool) -> void:
	if _finished:
		return
	_finished = true
	_blocked_by_world = blocked_by_world
	set_process(false)
	if blocked_by_world:
		visible = false
	playback_finished.emit(self)
	queue_free()


func _reject_visual() -> void:
	visible = false
	set_process(false)
	_finished = true


static func _direction16_for_line(from_world_px: Vector2, to_world_px: Vector2) -> int:
	var fx := to_world_px.x - from_world_px.x
	var fy := to_world_px.y - from_world_px.y
	if fx == 0.0:
		return 0 if fy < 0.0 else 8
	if fy == 0.0:
		return 12 if fx < 0.0 else 4
	var result := 0
	if fx > 0.0 and fy < 0.0:
		result = 4
		if -fy > fx / 4.0:
			result = 3
		if -fy > fx / 1.9:
			result = 2
		if -fy > fx * 1.4:
			result = 1
		if -fy > fx * 4.0:
			result = 0
	if fx > 0.0 and fy > 0.0:
		result = 4
		if fy > fx / 4.0:
			result = 5
		if fy > fx / 1.9:
			result = 6
		if fy > fx * 1.4:
			result = 7
		if fy > fx * 4.0:
			result = 8
	if fx < 0.0 and fy > 0.0:
		result = 12
		if fy > -fx / 4.0:
			result = 11
		if fy > -fx / 1.9:
			result = 10
		if fy > -fx * 1.4:
			result = 9
		if fy > -fx * 4.0:
			result = 8
	if fx < 0.0 and fy < 0.0:
		result = 12
		if -fy > -fx / 4.0:
			result = 13
		if -fy > -fx / 1.9:
			result = 14
		if -fy > -fx * 1.4:
			result = 15
		if -fy > -fx * 4.0:
			result = 0
	return result


func progress_ratio() -> float:
	return clampf(_elapsed_seconds / duration_seconds, 0.0, 1.0)


func is_finished() -> bool:
	return _finished


func collision_interrupted() -> bool:
	return _blocked_by_world


func source_texture_path() -> String:
	return "%s/Effect_%05d.png" % [SOURCE_FRAME_ROOT, _source_frame_index]


func visual_descriptor() -> Dictionary:
	var descriptor := {
		"effect_id": EFFECT_ID,
		"release_id": release_id,
		"origin_world_px": origin_world_px,
		"target_world_px": target_world_px,
		"duration_seconds": duration_seconds,
		"damage_owner": "enemy.physical_projectile_release",
		"release_policy": "frozen_path_once_then_queue_free",
		"source_manifest_path": SOURCE_MANIFEST_PATH,
		"source_texture_path": source_texture_path(),
		"source_frame_index": _source_frame_index,
		"source_frame_offset_px": _source_frame_offset,
		"source_direction16": _direction16,
		"source_frame_time_ms": SOURCE_FRAME_TIME_MS,
		"background_policy": "transparent_source_wil_frame",
		"collision_policy": "continuous_world_mask_visual_cutoff",
	}
	descriptor.make_read_only()
	return descriptor
