extends RefCounted

const DATA_PATH := "res://assets/data/monster_target_ring_profiles.json"
const CONTRACT := "monster.target_ring.posture_scale.v1"
static var _loaded := false
static var _crawling_ids: Dictionary = {}
static var _crawling_scale := 1.0
static var _direction_offsets: Dictionary = {}

static func resolve(monster_id: int, physics_radii: Vector2) -> Vector2:
	if not _loaded:
		_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not data is Dictionary or str(data.get("contract", "")) != CONTRACT:
			push_error("Invalid monster target ring posture contract")
			return physics_radii
		_crawling_scale = float(data.get("crawling_scale", 1.0))
		if not is_finite(_crawling_scale) or _crawling_scale < 1.0 or _crawling_scale > 1.3:
			push_error("Invalid crawling target ring scale")
			_crawling_scale = 1.0
		for key: String in data.get("crawling_monsters", {}):
			_crawling_ids[int(key)] = true
		_direction_offsets = data.get("direction_offsets_px", {})
	return physics_radii * _crawling_scale if _crawling_ids.has(monster_id) else physics_radii

static func direction_offsets(monster_id: int) -> Dictionary:
	if not _loaded:
		resolve(monster_id, Vector2.ZERO)
	var result := {}
	for key: String in _direction_offsets.get(str(monster_id), {}):
		var values: Array = _direction_offsets[str(monster_id)][key]
		result[int(key)] = Vector2(float(values[0]), float(values[1]))
	return result
