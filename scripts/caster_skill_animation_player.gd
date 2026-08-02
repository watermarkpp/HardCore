class_name CasterSkillAnimationPlayer
extends Sprite2D

signal animation_finished(skill_id: String)
signal skill_frame_changed(frame_index: int)

var skill_id := ""
var phase_id := ""
var visual_loaded := false
var playback_complete := false
var current_frame_index := 0
var direction_index := 0

var _frames: Array[Dictionary] = []
var _frame_time_seconds := 0.05
var _elapsed := 0.0
var _loop := false
var _manual_mode := false
var _native_extent := 1.0
var _desired_extent := 0.0
var _desired_footprint := Vector2.ZERO
var _desired_axis_extent := 0.0
var _fit_axis_world := Vector2.ZERO
var _anchor_policy := "top_left_from_world_anchor"
var _sequence_bounds := Rect2()
var _sequence_anchor_rebase := Vector2.ZERO


func configure(
	source_skill_id: String,
	direction := Vector2.DOWN,
	desired_extent := 0.0,
	loop_override: Variant = null,
	requested_phase_id := "",
	desired_footprint := Vector2.ZERO,
	desired_axis_extent := 0.0,
	fit_axis_world := Vector2.ZERO
) -> bool:
	skill_id = ProfessionRules.skill_id(source_skill_id)
	phase_id = requested_phase_id
	visual_loaded = false
	playback_complete = false
	texture = null
	set_process(false)
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		return false
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var animation := CasterSkillVisualRegistry.animation_profile(skill_id, phase_id)
	if animation.get("contract", "") != "caster_skill_animation.v1":
		return false
	var sequences: Array = animation.get("sequences", [])
	if sequences.is_empty():
		return false
	direction_index = CasterSkillVisualRegistry.direction_index(direction) if int(animation.get("direction_count", 1)) > 1 else 0
	var selected: Dictionary = sequences[
		CasterSkillVisualRegistry.sequence_index(direction_index, sequences)
	]
	_frames.assign(selected.get("frames", []))
	if _frames.is_empty():
		return false
	_frame_time_seconds = maxf(0.001, float(animation.get("frame_time_ms", 50)) / 1000.0)
	_loop = bool(animation.get("playback", "once") == "loop")
	if loop_override is bool:
		_loop = bool(loop_override)
	var render := CasterSkillVisualRegistry.render_policy(skill_id, phase_id)
	_anchor_policy = str(render.get("anchor_policy", "top_left_from_world_anchor"))
	_sequence_bounds = _visual_bounds_for_frames(_frames, _anchor_policy)
	_sequence_anchor_rebase = (
		-_sequence_bounds.get_center()
		if _anchor_policy == "center_sequence_bounds_on_geometry_origin"
		else Vector2.ZERO
	)
	var explicit_anchor_rebase: Array = render.get(
		"anchor_rebase_pixels", [0.0, 0.0]
	)
	if explicit_anchor_rebase.size() >= 2:
		_sequence_anchor_rebase += Vector2(
			float(explicit_anchor_rebase[0]),
			float(explicit_anchor_rebase[1])
		)
	_native_extent = maxf(
		1.0,
		maxf(_sequence_bounds.size.x, _sequence_bounds.size.y)
	)
	_desired_extent = maxf(0.0, desired_extent)
	_desired_footprint = Vector2(
		maxf(0.0, desired_footprint.x),
		maxf(0.0, desired_footprint.y)
	)
	_desired_axis_extent = maxf(0.0, desired_axis_extent)
	_fit_axis_world = (
		fit_axis_world.normalized()
		if fit_axis_world.length_squared() > 0.000001
		else Vector2.ZERO
	)
	if (
		_desired_axis_extent > 0.0
		and not _fit_axis_world.is_zero_approx()
	):
		# Directional line art must be fitted by its projection along the cast
		# axis. Bounding-box contain fitting used the short side of diagonal
		# frames, shrinking them to roughly two tiles, while cardinal frames were
		# stretched by a different screen-space box. One uniform scale preserves
		# source pixels/aspect ratio and makes every direction cover the same map
		# line represented by the shared geometry axis.
		var native_axis_extent := _rect_projection_extent(
			_sequence_bounds, _fit_axis_world
		)
		scale = Vector2.ONE * (
			_desired_axis_extent / maxf(0.001, native_axis_extent)
		)
	elif (
		_desired_footprint.x > 0.0
		and _desired_footprint.y > 0.0
		and _sequence_bounds.size.x > 0.0
		and _sequence_bounds.size.y > 0.0
	):
		var contain_scale := minf(
			_desired_footprint.x / _sequence_bounds.size.x,
			_desired_footprint.y / _sequence_bounds.size.y
		)
		scale = Vector2.ONE * maxf(0.001, contain_scale)
	elif _desired_extent > 0.0:
		scale = Vector2.ONE * (_desired_extent / _native_extent)
	else:
		var source_scale := maxf(0.001, float(render.get("source_scale", 1.0)))
		scale = Vector2(
			source_scale * maxf(0.001, float(render.get("source_scale_x", 1.0))),
			source_scale * maxf(0.001, float(render.get("source_scale_y", 1.0)))
		)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	current_frame_index = 0
	_elapsed = 0.0
	_manual_mode = false
	playback_complete = false
	visual_loaded = _apply_frame(0)
	set_process(visual_loaded)
	return visual_loaded


func _process(delta: float) -> void:
	if not visual_loaded or playback_complete or _manual_mode:
		return
	_elapsed += delta
	while _elapsed >= _frame_time_seconds:
		_elapsed -= _frame_time_seconds
		var next_frame := current_frame_index + 1
		if next_frame >= _frames.size():
			if _loop:
				next_frame = 0
			else:
				next_frame = _frames.size() - 1
				playback_complete = true
				animation_finished.emit(skill_id)
		current_frame_index = next_frame
		_apply_frame(current_frame_index)
		if playback_complete:
			break


func set_manual_frame(frame_index: int) -> bool:
	if _frames.is_empty():
		return false
	_manual_mode = true
	playback_complete = false
	_elapsed = 0.0
	current_frame_index = clampi(frame_index, 0, _frames.size() - 1)
	return _apply_frame(current_frame_index)


func animation_duration() -> float:
	return float(_frames.size()) * _frame_time_seconds


func frame_count() -> int:
	return _frames.size()


func visual_bounds_center() -> Vector2:
	return (_sequence_bounds.get_center() + _sequence_anchor_rebase) * scale


func fitted_visual_bounds() -> Rect2:
	return Rect2(
		(_sequence_bounds.position + _sequence_anchor_rebase) * scale,
		_sequence_bounds.size * scale
	)


func fitted_visual_axis_extent(axis_world: Vector2) -> float:
	if axis_world.length_squared() <= 0.000001:
		return 0.0
	return _rect_projection_extent(
		_sequence_bounds, axis_world.normalized()
	) * absf(scale.x)


func _apply_frame(frame_index: int) -> bool:
	if frame_index < 0 or frame_index >= _frames.size():
		return false
	var frame: Dictionary = _frames[frame_index]
	var path := "res://%s" % str(frame.get("path", ""))
	var loaded := CasterSkillVisualRegistry.load_texture_path(path)
	if loaded == null:
		return false
	texture = loaded
	var anchor_field := (
		"source_draw_offset"
		if _anchor_policy == "source_draw_offset_from_actor_foot"
		else "top_left_from_world_anchor"
	)
	var top_left: Array = frame.get(anchor_field, [0, 0])
	offset = Vector2(
		float(top_left[0]) + float(loaded.get_width()) * 0.5,
		float(top_left[1]) + float(loaded.get_height()) * 0.5
	) + _sequence_anchor_rebase
	skill_frame_changed.emit(frame_index)
	return true


func _visual_bounds_for_frames(frames: Array[Dictionary], anchor_policy: String) -> Rect2:
	var anchor_field := (
		"source_draw_offset"
		if anchor_policy == "source_draw_offset_from_actor_foot"
		else "top_left_from_world_anchor"
	)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for frame: Dictionary in frames:
		var top_left: Array = frame.get(anchor_field, [0, 0])
		var pixel_size: Array = frame.get("pixel_size", [0, 0])
		var frame_minimum := Vector2(float(top_left[0]), float(top_left[1]))
		var frame_maximum := frame_minimum + Vector2(
			float(pixel_size[0]), float(pixel_size[1])
		)
		minimum.x = minf(minimum.x, frame_minimum.x)
		minimum.y = minf(minimum.y, frame_minimum.y)
		maximum.x = maxf(maximum.x, frame_maximum.x)
		maximum.y = maxf(maximum.y, frame_maximum.y)
	if frames.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(minimum, maximum - minimum)


func _rect_projection_extent(rect: Rect2, axis: Vector2) -> float:
	var normalized_axis := axis.normalized()
	return (
		absf(normalized_axis.x) * rect.size.x
		+ absf(normalized_axis.y) * rect.size.y
	)
