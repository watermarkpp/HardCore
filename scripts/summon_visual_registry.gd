class_name SummonVisualRegistry
extends RefCounted

const DIVINE_BEAST_MANIFEST_PATH := "res://assets/data/vanilla_176/divine_beast_animation.json"
const DIVINE_BEAST_CONTRACT_ID := "summon.visual.divine_beast.directional.v1"
const REQUIRED_ACTIONS: Array[String] = ["idle", "walk", "attack", "hit", "death"]

static var _profile_cache: Dictionary = {}


static func profile(summon_id: String) -> Dictionary:
	if summon_id != "divine_beast":
		return {}
	if not _profile_cache.is_empty():
		return _profile_cache
	var file := FileAccess.open(DIVINE_BEAST_MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != DIVINE_BEAST_CONTRACT_ID:
		return {}
	var actions: Dictionary = parsed.get("actions", {})
	var frame_size_data: Array = parsed.get("frameSize", [])
	var foot_anchor_data: Array = parsed.get("footAnchor", [])
	var ground_offset_data: Array = parsed.get("actorGroundOffset", [])
	if frame_size_data.size() != 2 or foot_anchor_data.size() != 2 or ground_offset_data.size() != 2:
		return {}
	var result := {
		"contract_id": DIVINE_BEAST_CONTRACT_ID,
		"direction_mode": str(parsed.get("directionMode", "")),
		"frame_size": Vector2i(int(frame_size_data[0]), int(frame_size_data[1])),
		"foot_anchor": Vector2i(int(foot_anchor_data[0]), int(foot_anchor_data[1])),
		"actor_ground_offset": Vector2i(int(ground_offset_data[0]), int(ground_offset_data[1])),
		"frame_counts": {},
		"frame_ms": {},
	}
	for action_name: String in REQUIRED_ACTIONS:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return {}
		var texture := load(path) as Texture2D
		if texture == null:
			return {}
		var frame_count := int(action.get("framesPerDirection", 0))
		if frame_count <= 0 or texture.get_size() != Vector2(result.frame_size.x * frame_count, result.frame_size.y * 8):
			return {}
		result[action_name] = texture
		result.frame_counts[action_name] = frame_count
		result.frame_ms[action_name] = int(action.get("frameMs", 100))
	_profile_cache = result
	return _profile_cache


static func clear_cache_for_tests() -> void:
	_profile_cache = {}
