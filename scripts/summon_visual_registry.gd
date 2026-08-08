class_name SummonVisualRegistry
extends RefCounted

const SUMMON_BASELINE_PATH := "res://assets/data/vanilla_176/taoist_summon_baseline.json"
const DIVINE_BEAST_MANIFEST_PATH := "res://assets/data/vanilla_176/divine_beast_animation.json"
const DIVINE_BEAST_CONTRACT_ID := "summon.visual.divine_beast.directional.v1"
const REQUIRED_ACTIONS: Array[String] = ["idle", "walk", "attack", "hit", "death"]

static var _profile_cache: Dictionary = {}


static func profile(summon_id: String) -> Dictionary:
	if _profile_cache.has(summon_id):
		return (_profile_cache[summon_id] as Dictionary).duplicate()
	var result := (
		_load_divine_beast_profile()
		if summon_id == "divine_beast"
		else _load_skeleton_profile() if summon_id == "skeleton" else {}
	)
	if result.is_empty():
		return {}
	_profile_cache[summon_id] = result
	return result.duplicate()


static func _load_skeleton_profile() -> Dictionary:
	var parsed := _read_json(SUMMON_BASELINE_PATH)
	var templates: Dictionary = parsed.get("templates", {})
	var skeleton: Dictionary = templates.get("skeleton", {})
	var visual: Dictionary = skeleton.get("visual", {})
	return _build_action_profile(
		str(visual.get("contract_id", "")),
		str(visual.get("direction_mode", "")),
		visual.get("frame_size", []),
		visual.get("foot_anchor", []),
		visual.get("actor_ground_offset", []),
		int(visual.get("stable_body_top", 0)),
		visual.get("actions", {}),
		"frames_per_direction",
		"frame_ms"
	)


static func _load_divine_beast_profile() -> Dictionary:
	var parsed := _read_json(DIVINE_BEAST_MANIFEST_PATH)
	if str(parsed.get("contract_id", "")) != DIVINE_BEAST_CONTRACT_ID:
		return {}
	var result := _build_action_profile(
		DIVINE_BEAST_CONTRACT_ID,
		str(parsed.get("directionMode", "")),
		parsed.get("frameSize", []),
		parsed.get("footAnchor", []),
		parsed.get("actorGroundOffset", []),
		int(parsed.get("stableBodyTop", 39)),
		parsed.get("actions", {}),
		"framesPerDirection",
		"frameMs"
	)
	if result.is_empty():
		return {}
	var fire: Dictionary = parsed.get("fire", {})
	var fire_path := str(fire.get("path", ""))
	var fire_frame_size := _vector2i(fire.get("frameSize", []))
	var fire_foot_anchor := _vector2i(fire.get("footAnchor", []))
	var fire_ground_offset := _vector2i(fire.get("actorGroundOffset", []))
	var fire_frame_count := int(fire.get("framesPerDirection", 0))
	if (
		fire_path.is_empty()
		or fire_frame_size == Vector2i.ZERO
		or fire_frame_count <= 0
	):
		return {}
	var fire_texture := _load_texture(fire_path)
	if fire_texture == null or fire_texture.get_size() != Vector2(
		fire_frame_size.x * fire_frame_count,
		fire_frame_size.y * 8
	):
		return {}
	result.fire = fire_texture
	result.fire_frame_size = fire_frame_size
	result.fire_foot_anchor = fire_foot_anchor
	result.fire_actor_ground_offset = fire_ground_offset
	result.fire_frame_count = fire_frame_count
	result.fire_frame_ms = int(fire.get("frameMs", 100))
	result.attack_release_frame_index = int(parsed.get("attackReleaseFrameIndex", 5))
	result.attack_release_ms = int(parsed.get("attackReleaseMs", 500))
	return result


static func _build_action_profile(
	contract_id: String,
	direction_mode: String,
	frame_size_data: Variant,
	foot_anchor_data: Variant,
	ground_offset_data: Variant,
	stable_body_top: int,
	actions_value: Variant,
	frame_count_key: String,
	frame_ms_key: String
) -> Dictionary:
	if contract_id.is_empty() or not actions_value is Dictionary:
		return {}
	var frame_size := _vector2i(frame_size_data)
	var foot_anchor := _vector2i(foot_anchor_data)
	var ground_offset := _vector2i(ground_offset_data)
	if frame_size == Vector2i.ZERO:
		return {}
	var actions: Dictionary = actions_value
	var result := {
		"contract_id": contract_id,
		"direction_mode": direction_mode,
		"frame_size": frame_size,
		"foot_anchor": foot_anchor,
		"actor_ground_offset": ground_offset,
		"stable_body_top": stable_body_top,
		"frame_counts": {},
		"frame_ms": {},
	}
	for action_name: String in REQUIRED_ACTIONS:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		if path.is_empty():
			return {}
		var texture := _load_texture(path)
		var frame_count := int(action.get(frame_count_key, 0))
		if (
			texture == null
			or frame_count <= 0
			or texture.get_size() != Vector2(frame_size.x * frame_count, frame_size.y * 8)
		):
			return {}
		result[action_name] = texture
		result.frame_counts[action_name] = frame_count
		result.frame_ms[action_name] = int(action.get(frame_ms_key, 100))
	return result


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func _vector2i(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))


static func clear_cache_for_tests() -> void:
	_profile_cache = {}
