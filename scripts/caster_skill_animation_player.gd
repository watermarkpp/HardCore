class_name CasterSkillAnimationPlayer
extends Sprite2D

const FORWARD_ENDPOINT_FIT_CONTRACT_ID := (
	"skills.caster.line_visual.forward_endpoint_uniform.v1"
)
const AXIS_CROSS_FIT_CONTRACT_ID := (
	"skills.caster.line_visual.frame_alpha_cross_affine.v3"
)
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
var _desired_cross_axis_extent := 0.0
var _fit_axis_world := Vector2.ZERO
var _source_axis_local := Vector2.UP
var _source_cross_axis_local := Vector2.RIGHT
var _anchor_policy := "top_left_from_world_anchor"
var _sequence_bounds := Rect2()
var _sequence_anchor_rebase := Vector2.ZERO
var _axis_cross_fit_active := false
var _longitudinal_scale := 1.0
var _target_cross_axis := Vector2.RIGHT


func configure(
	source_skill_id: String,
	direction := Vector2.DOWN,
	desired_extent := 0.0,
	loop_override: Variant = null,
	requested_phase_id := "",
	desired_footprint := Vector2.ZERO,
	desired_axis_extent := 0.0,
	fit_axis_world := Vector2.ZERO,
	desired_cross_axis_extent := 0.0
) -> bool:
	skill_id = ProfessionRules.skill_id(source_skill_id)
	phase_id = requested_phase_id
	visual_loaded = false
	playback_complete = false
	texture = null
	transform = Transform2D.IDENTITY
	offset = Vector2.ZERO
	_axis_cross_fit_active = false
	_longitudinal_scale = 1.0
	_target_cross_axis = Vector2.RIGHT
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
	var visual_type := CasterSkillVisualRegistry.visual_type(skill_id)
	var visual_width_scale := maxf(
		0.001,
		float(
			render.get(
				"visual_width_scale",
				render.get("source_scale_x", 1.0)
			)
		)
	)
	var visual_height_scale := maxf(
		0.001,
		float(
			render.get(
				"visual_height_scale",
				render.get("source_scale_y", 1.0)
			)
		)
	)
	_anchor_policy = str(render.get("anchor_policy", "top_left_from_world_anchor"))
	_sequence_bounds = _visual_bounds_for_frames(_frames, _anchor_policy)
	# Compute source axis before anchor rebase so the new policy can use it.
	_source_axis_local = Vector2.UP.rotated(
		float(direction_index) * TAU / 16.0
	).normalized()
	_source_cross_axis_local = Vector2(
		-_source_axis_local.y, _source_axis_local.x
	)
	if _anchor_policy == "align_sequence_visible_axis_start_to_geometry_origin":
		_sequence_anchor_rebase = _rebase_to_visible_axis_start(_sequence_bounds)
	elif _anchor_policy == "center_sequence_bounds_on_geometry_origin":
		_sequence_anchor_rebase = -_sequence_bounds.get_center()
	else:
		_sequence_anchor_rebase = Vector2.ZERO
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
	_desired_cross_axis_extent = maxf(0.0, desired_cross_axis_extent)
	_fit_axis_world = (
		fit_axis_world.normalized()
		if fit_axis_world.length_squared() > 0.000001
		else Vector2.ZERO
	)
	if visual_type == "sky_strike":
		var visual_profile: Dictionary = (
			CasterSkillVisualRegistry.visual_profile(skill_id)
		)
		var profile_animation: Dictionary = (
			visual_profile.get("animation", {}) as Dictionary
		)
		if str(profile_animation.get("scale_mode", "")) == "fixed_source":
			visual_width_scale = maxf(
				0.001,
				float(profile_animation.get("width_scale", visual_width_scale))
			)
			visual_height_scale = maxf(
				0.001,
				float(profile_animation.get("height_scale", visual_height_scale))
			)
		scale = Vector2(visual_width_scale, visual_height_scale)
	elif (
		_desired_axis_extent > 0.0
		and not _fit_axis_world.is_zero_approx()
		and _desired_cross_axis_extent > 0.0
	):
		# Each primary Laser sequence already owns a correct 16-way source
		# orientation. Map its longitudinal source axis onto the exact continuous
		# aim axis, then fit the visual thickness independently from the damage
		# strip. A direction-dependent isometric projection changed apparent width
		# by about 2x, before per-frame alpha-envelope variance was considered.
		var native_forward_extent := _rect_forward_projection_extent(
			_sequence_bounds, _sequence_anchor_rebase, _source_axis_local
		)
		_longitudinal_scale = (
			_desired_axis_extent / maxf(0.001, native_forward_extent)
		)
		_target_cross_axis = Vector2(-_fit_axis_world.y, _fit_axis_world.x)
		_axis_cross_fit_active = true
		# Length uses one sequence-stable mapping. Only the cross component is
		# recomputed per formal frame from its alpha envelope.
		_apply_axis_cross_transform(_frames[0])
	elif (
		_desired_axis_extent > 0.0
		and not _fit_axis_world.is_zero_approx()
	):
		var fallback_native_forward_extent := _rect_forward_projection_extent(
			_sequence_bounds, _sequence_anchor_rebase, _source_axis_local
		)
		scale = Vector2.ONE * (
			_desired_axis_extent / maxf(0.001, fallback_native_forward_extent)
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
	return transform.basis_xform(
		_sequence_bounds.get_center() + _sequence_anchor_rebase
	)


func fitted_visual_bounds() -> Rect2:
	return _transformed_rect_bounds(_sequence_bounds, _sequence_anchor_rebase)


func fitted_visual_axis_extent(axis_world: Vector2) -> float:
	if axis_world.length_squared() <= 0.000001:
		return 0.0
	return _transformed_rect_projection_extent(
		_sequence_bounds, _sequence_anchor_rebase, axis_world.normalized()
	)


func fitted_visual_forward_extent(axis_world: Vector2) -> float:
	if axis_world.length_squared() <= 0.000001:
		return 0.0
	return _transformed_rect_forward_projection_extent(
		_sequence_bounds,
		_sequence_anchor_rebase,
		axis_world.normalized()
	)


func fitted_visual_cross_extent(axis_world: Vector2) -> float:
	if axis_world.length_squared() <= 0.000001:
		return 0.0
	var normalized_axis := axis_world.normalized()
	return _transformed_rect_projection_extent(
		_sequence_bounds,
		_sequence_anchor_rebase,
		Vector2(-normalized_axis.y, normalized_axis.x)
	)


func current_frame_visual_forward_extent(axis_world: Vector2) -> float:
	if (
		axis_world.length_squared() <= 0.000001
		or current_frame_index < 0
		or current_frame_index >= _frames.size()
	):
		return 0.0
	var frame_rect := _visual_rect_for_frame(
		_frames[current_frame_index], _anchor_policy
	)
	return _transformed_rect_forward_projection_extent(
		frame_rect,
		_sequence_anchor_rebase,
		axis_world.normalized()
	)


func current_frame_visible_cross_extent(axis_world: Vector2) -> float:
	if (
		axis_world.length_squared() <= 0.000001
		or current_frame_index < 0
		or current_frame_index >= _frames.size()
	):
		return 0.0
	var native_extent := _frame_visible_cross_extent(_frames[current_frame_index])
	return native_extent * transform.basis_xform(_source_cross_axis_local).length()


func _apply_frame(frame_index: int) -> bool:
	if frame_index < 0 or frame_index >= _frames.size():
		return false
	var frame: Dictionary = _frames[frame_index]
	var path := "res://%s" % str(frame.get("path", ""))
	var loaded := CasterSkillVisualRegistry.load_texture_path(path)
	if loaded == null:
		return false
	texture = loaded
	if _axis_cross_fit_active:
		_apply_axis_cross_transform(frame)
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


func _apply_axis_cross_transform(frame: Dictionary) -> void:
	var native_cross_extent := _frame_visible_cross_extent(frame)
	var cross_scale := (
		_desired_cross_axis_extent / maxf(0.001, native_cross_extent)
	)
	var basis_x := (
		_fit_axis_world * (_source_axis_local.x * _longitudinal_scale)
		+ _target_cross_axis * (_source_cross_axis_local.x * cross_scale)
	)
	var basis_y := (
		_fit_axis_world * (_source_axis_local.y * _longitudinal_scale)
		+ _target_cross_axis * (_source_cross_axis_local.y * cross_scale)
	)
	transform = Transform2D(basis_x, basis_y, Vector2.ZERO)


func _frame_visible_cross_extent(frame: Dictionary) -> float:
	var formal_alpha_extent := float(frame.get("visible_cross_extent_pixels", 0.0))
	if formal_alpha_extent > 0.0:
		return formal_alpha_extent
	return _rect_projection_extent(
		_visual_rect_for_frame(frame, _anchor_policy),
		_source_cross_axis_local
	)


func _visual_rect_for_frame(frame: Dictionary, anchor_policy: String) -> Rect2:
	var anchor_field := (
		"source_draw_offset"
		if anchor_policy == "source_draw_offset_from_actor_foot"
		else "top_left_from_world_anchor"
	)
	var top_left: Array = frame.get(anchor_field, [0, 0])
	var pixel_size: Array = frame.get("pixel_size", [0, 0])
	return Rect2(
		Vector2(float(top_left[0]), float(top_left[1])),
		Vector2(float(pixel_size[0]), float(pixel_size[1]))
	)


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


func _rect_forward_projection_extent(
	rect: Rect2,
	anchor_rebase: Vector2,
	axis: Vector2
) -> float:
	var normalized_axis := axis.normalized()
	var minimum := rect.position + anchor_rebase
	var maximum := rect.end + anchor_rebase
	var forward_extent := -INF
	for corner: Vector2 in [
		minimum,
		Vector2(maximum.x, minimum.y),
		maximum,
		Vector2(minimum.x, maximum.y),
	]:
		forward_extent = maxf(forward_extent, corner.dot(normalized_axis))
	return maxf(0.001, forward_extent)


func _transformed_rect_bounds(rect: Rect2, anchor_rebase: Vector2) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector2 in _rect_corners(rect, anchor_rebase):
		var transformed := transform.basis_xform(point)
		minimum.x = minf(minimum.x, transformed.x)
		minimum.y = minf(minimum.y, transformed.y)
		maximum.x = maxf(maximum.x, transformed.x)
		maximum.y = maxf(maximum.y, transformed.y)
	return Rect2(minimum, maximum - minimum)


func _transformed_rect_projection_extent(
	rect: Rect2,
	anchor_rebase: Vector2,
	axis: Vector2
) -> float:
	var minimum := INF
	var maximum := -INF
	var normalized_axis := axis.normalized()
	for point: Vector2 in _rect_corners(rect, anchor_rebase):
		var projection := transform.basis_xform(point).dot(normalized_axis)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return maxf(0.001, maximum - minimum)


func _transformed_rect_forward_projection_extent(
	rect: Rect2,
	anchor_rebase: Vector2,
	axis: Vector2
) -> float:
	var forward_extent := -INF
	var normalized_axis := axis.normalized()
	for point: Vector2 in _rect_corners(rect, anchor_rebase):
		forward_extent = maxf(
			forward_extent,
			transform.basis_xform(point).dot(normalized_axis)
		)
	return maxf(0.001, forward_extent)


func _rect_corners(rect: Rect2, anchor_rebase: Vector2) -> Array[Vector2]:
	var minimum := rect.position + anchor_rebase
	var maximum := rect.end + anchor_rebase
	return [
		minimum,
		Vector2(maximum.x, minimum.y),
		maximum,
		Vector2(minimum.x, maximum.y),
	]


func _rebase_to_visible_axis_start(bounds: Rect2) -> Vector2:
	# Shift the sequence bounds so the minimum projection onto the source
	# axis lands at the geometry origin. This prevents the animation from
	# extending backward (behind the caster) while keeping the forward
	# extent driven by the desired axis stretch.
	var source_axis_min: float = INF
	var cross_min: float = INF
	var cross_max: float = -INF
	var corners: PackedVector2Array = PackedVector2Array([
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + bounds.size,
		bounds.position + Vector2(0.0, bounds.size.y),
	])
	for corner: Vector2 in corners:
		var axis_proj: float = corner.dot(_source_axis_local)
		source_axis_min = minf(source_axis_min, axis_proj)
		var cross_proj: float = corner.dot(_source_cross_axis_local)
		cross_min = minf(cross_min, cross_proj)
		cross_max = maxf(cross_max, cross_proj)
	var cross_center: float = (cross_min + cross_max) * 0.5
	return -source_axis_min * _source_axis_local - cross_center * _source_cross_axis_local
