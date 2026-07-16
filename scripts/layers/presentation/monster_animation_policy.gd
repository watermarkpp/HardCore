class_name MonsterAnimationPolicy
extends RefCounted

const REQUIRED_ACTIONS := [&"idle", &"walk", &"attack", &"hit", &"death"]
const DIRECTION_MODES := [&"mir2_north_first", &"logical_south_first"]
const DEFAULT_FRAME_COUNTS := {&"idle":4, &"walk":6, &"attack":6, &"hit":2, &"death":4}
const ACTION_FPS := {&"idle":6.0, &"walk":12.0}


static func direction_row(direction: Vector2, mode: StringName) -> int:
	return ArtSpec.mir2_client_direction_row(direction) if mode == &"mir2_north_first" else ArtSpec.direction_index(direction)


static func validate(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var mode := StringName(str(profile.get("direction_mode", "")))
	if mode not in DIRECTION_MODES:
		errors.append("direction_mode_invalid")
	var frame_size: Vector2i = profile.get("frame_size", Vector2i.ZERO)
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size_invalid")
	var foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	if foot_anchor.x < 0 or foot_anchor.y < 0 or foot_anchor.x > frame_size.x or foot_anchor.y > frame_size.y:
		errors.append("foot_anchor_invalid")
	var counts: Dictionary = profile.get("frame_counts", {})
	for action: StringName in REQUIRED_ACTIONS:
		var texture: Texture2D = profile.get(action, null)
		var count := int(counts.get(action, DEFAULT_FRAME_COUNTS[action]))
		if texture == null:
			errors.append("%s_texture_missing" % action)
			continue
		if count <= 0:
			errors.append("%s_frame_count_invalid" % action)
			continue
		var expected := Vector2(frame_size.x * count, frame_size.y * 8)
		if not texture.get_size().is_equal_approx(expected):
			errors.append("%s_atlas_size_invalid" % action)
	return errors


static func frame_count(profile: Dictionary, action: StringName) -> int:
	return int(profile.get("frame_counts", {}).get(action, DEFAULT_FRAME_COUNTS.get(action, 1)))


static func loop_fps(action: StringName) -> float:
	return float(ACTION_FPS.get(action, 6.0))
