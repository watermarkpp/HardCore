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


func configure(
	source_skill_id: String,
	direction := Vector2.DOWN,
	desired_extent := 0.0,
	loop_override: Variant = null,
	requested_phase_id := ""
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
	var native: Array = animation.get("native_extent", [1, 1])
	_native_extent = maxf(1.0, float(maxi(int(native[0]), int(native[1]))))
	var render := CasterSkillVisualRegistry.render_policy(skill_id, phase_id)
	_desired_extent = maxf(0.0, desired_extent)
	if _desired_extent > 0.0:
		scale = Vector2.ONE * (_desired_extent / _native_extent)
	else:
		scale = Vector2.ONE * maxf(0.001, float(render.get("source_scale", 1.0)))
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


func _apply_frame(frame_index: int) -> bool:
	if frame_index < 0 or frame_index >= _frames.size():
		return false
	var frame: Dictionary = _frames[frame_index]
	var path := "res://%s" % str(frame.get("path", ""))
	var loaded := CasterSkillVisualRegistry.load_texture_path(path)
	if loaded == null:
		return false
	texture = loaded
	var top_left: Array = frame.get("top_left_from_world_anchor", [0, 0])
	offset = Vector2(
		float(top_left[0]) + float(loaded.get_width()) * 0.5,
		float(top_left[1]) + float(loaded.get_height()) * 0.5
	)
	skill_frame_changed.emit(frame_index)
	return true
