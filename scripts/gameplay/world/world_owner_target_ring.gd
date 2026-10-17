extends RefCounted

const DATA_PATH := "res://assets/data/monster_target_ring_profiles.json"
const CONTRACT := "monster.target_ring.posture_scale.v1"
var _loaded := false
var _crawling_ids: Dictionary = {}
var _crawling_scale := 1.0
var _direction_offsets: Dictionary = {}

func resolve(monster_id: int, physics_radii: Vector2) -> Vector2:
	if not _loaded:
		_loaded = true
		var data: Variant = JSON.parse_string(_source_text.open_published(DATA_PATH).get_as_text())
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

func direction_offsets(monster_id: int) -> Dictionary:
	if not _loaded:
		resolve(monster_id, Vector2.ZERO)
	var result := {}
	for key: String in _direction_offsets.get(str(monster_id), {}):
		var values: Array = _direction_offsets[str(monster_id)][key]
		result[int(key)] = Vector2(float(values[0]), float(values[1]))
	return result

var _owner := OS.get_thread_caller_id()
var _source_text: RefCounted
func _init(source_text: RefCounted) -> void: _source_text = source_text
func owner_thread_id() -> int: return _owner
