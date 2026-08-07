extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")

var _counts := {
	"map_editor_runtime_count": 0,
	"authored_source_count": 0,
	"authored_centered_count": 0,
	"unsupported_count": 0,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# WorldContent is the runtime source of the 142 formal maps.
	var map_ids: Array = WorldContent.maps.keys()
	map_ids.sort()
	assert(
		map_ids.size() >= 142,
		"formal map inventory must cover the full WorldContent set"
	)
	var missing_profiles: Array = []
	for map_id: int in map_ids:
		var profile: Dictionary = Mapper.resolve_map_projection_profile(map_id)
		if not bool(profile.get("success", false)):
			missing_profiles.append(map_id)
			_count("unsupported_count")
			continue
		match str(profile.get("policy", "")):
			Mapper.PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE:
				_count("map_editor_runtime_count")
			Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE:
				_count("authored_source_count")
			Mapper.PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE:
				_count("authored_centered_count")
			_:
				missing_profiles.append(map_id)
				_count("unsupported_count")
	assert(
		missing_profiles.is_empty(),
		"every formal map must resolve a projection profile; missing=%s"
		% str(missing_profiles)
	)
	# Special maps registry checks.
	_check_policy(4, Mapper.PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE)
	_check_policy(217, Mapper.PROJECTION_POLICY_MAP_EDITOR_RUNTIME_ABSOLUTE)
	_check_policy(248, Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE)
	_check_policy(401, Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE)
	_check_policy(338, Mapper.PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE)
	_check_policy(478, Mapper.PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE)
	var unknown: Dictionary = Mapper.resolve_map_projection_profile(9999)
	assert(
		not bool(unknown.get("success", true)),
		"unknown map 9999 must fail-closed"
	)
	assert(
		str(unknown.get("reason", ""))
		== str(Mapper.PROJECTION_POLICY_UNSUPPORTED),
		"unknown map must use unsupported_map_projection"
	)
	_count("unsupported_count")
	assert(
		_counts["unsupported_count"] == 1,
		"formal playable unsupported_count must be 0 (only the unknown probe is unsupported)"
	)
	await get_tree().process_frame
	print(
		"FORMAL_MAP_PROJECTION_COVERAGE_PASS total=%d runtime=%d authored_source=%d authored_centered=%d unsupported=%d"
		% [
			map_ids.size(),
			_counts["map_editor_runtime_count"],
			_counts["authored_source_count"],
			_counts["authored_centered_count"],
			_counts["unsupported_count"],
		]
	)
	get_tree().quit(0)


func _check_policy(map_id: int, expected_policy: StringName) -> void:
	var profile: Dictionary = Mapper.resolve_map_projection_profile(map_id)
	assert(
		str(profile.get("policy", "")) == str(expected_policy),
		"map %d must use policy %s (got %s)" % [
			map_id,
			expected_policy,
			profile.get("policy", ""),
		]
	)


func _count(key: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1
