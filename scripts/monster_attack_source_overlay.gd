extends Node2D

const Frames := preload("res://scripts/monster_source_frames.gd")
var sprite: Sprite2D
var profile: Dictionary = {}
var direction := 0
var frame_seconds := 0.1
var elapsed := 0.0
var start_delay := 0.0
var ground_offset := Vector2.ZERO
var source_frame_index := -1
var _fixed_world_origin := Vector2.INF

func setup(monster_id: int, direction8: int, direction16: int, body_frame_seconds: float, origin_offset: Vector2) -> void:
	profile = Frames.profile_for_id(monster_id)
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	z_index = 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = additive
	ground_offset = origin_offset
	direction = direction16 if int(profile.get("direction_count", 8)) == 16 else direction8
	frame_seconds = maxf(0.001, body_frame_seconds)
	start_delay = frame_seconds * 5.0 if monster_id == 146 else 0.0
	if monster_id == 146: frame_seconds = 0.1
	elapsed = 0.0
	_fixed_world_origin = Vector2.INF
	Frames.request_profile(profile, direction)
	visible = false
	set_process(not profile.is_empty())

func _process(delta: float) -> void:
	elapsed += maxf(0.0, delta)
	if elapsed < start_delay: return
	var frame := int((elapsed - start_delay) / frame_seconds)
	var count := int(profile.get("frame_count", 0))
	if frame >= count:
		visible = false
		queue_free()
		return
	# TWarriorElfMonster's frame-5 map effect stays at its release position.
	if start_delay > 0.0 and not _fixed_world_origin.is_finite():
		_fixed_world_origin = global_position
		var world_host := get_parent().get_parent().get_parent()
		reparent(world_host, true)
		global_position = _fixed_world_origin
		add_to_group("zone_content")
	var record: Dictionary = profile.frames[direction * count + frame]
	sprite.texture = Frames.texture(str(record.path))
	visible = sprite.texture != null and not bool(record.get("empty", false))
	sprite.position = Vector2(float(record.x), float(record.y)) - ground_offset
	source_frame_index = int(record.source_index)
