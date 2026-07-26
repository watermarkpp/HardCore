class_name CasterSkillAnimationPlayer
extends Sprite2D

var skill_id := ""
var visual_loaded := false
var playback_complete := false
var current_frame_index := 0
var direction_index := 0

var _frames: Array[Dictionary] = []
var _frame_time_seconds := 0.05
var _elapsed := 0.0
var _loop := false
var _native_extent := 1.0
var _desired_extent := 72.0


func configure(
	source_skill_id: String,
	direction := Vector2.DOWN,
	desired_extent := 72.0,
	loop_override: Variant = null
) -> bool:
	skill_id = ProfessionRules.skill_id(source_skill_id)
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var animation: Dictionary = profile.get("animation", {})
	if animation.get("contract", "") != "caster_skill_animation.v1":
		return false
	var sequences: Array = animation.get("sequences", [])
	if sequences.is_empty():
		return false
	direction_index = CasterSkillVisualRegistry.direction_index(direction) if int(animation.get("direction_count", 1)) > 1 else 0
	var selected: Dictionary = sequences[mini(direction_index, sequences.size() - 1)]
	_frames.assign(selected.get("frames", []))
	if _frames.is_empty():
		return false
	_frame_time_seconds = maxf(0.001, float(animation.get("frame_time_ms", 50)) / 1000.0)
	_loop = bool(animation.get("playback", "once") == "loop")
	if loop_override is bool:
		_loop = bool(loop_override)
	var native: Array = animation.get("native_extent", [1, 1])
	_native_extent = maxf(1.0, float(maxi(int(native[0]), int(native[1]))))
	_desired_extent = maxf(1.0, desired_extent)
	scale = Vector2.ONE * (_desired_extent / _native_extent)
	current_frame_index = 0
	_elapsed = 0.0
	playback_complete = false
	visual_loaded = _apply_frame(0)
	return visual_loaded


func _process(delta: float) -> void:
	if not visual_loaded or playback_complete or _frames.size() <= 1:
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
		current_frame_index = next_frame
		_apply_frame(current_frame_index)
		if playback_complete:
			break


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
	return true
