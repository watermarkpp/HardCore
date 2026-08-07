extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const RUNTIME_MAP_IDS := [4, 268, 313, 314, 315, 217, 218, 221, 406, 408, 1578]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Formal coverage is defined by runtime-built maps, NOT by WorldContent.
	var implemented_count := 0
	var unresolved: Array = []
	for map_id: int in RUNTIME_MAP_IDS:
		assert(
			Bridge.is_runtime_built(map_id)
			and Bridge.is_formal_playable(map_id),
			"runtime map %d must be built + playable" % map_id
		)
		implemented_count += 1
		var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		if not bool(profile.get("success", false)):
			unresolved.append(map_id)
	assert(
		unresolved.is_empty(),
		"every formal runtime map must resolve; unresolved=%s" % str(unresolved)
	)
	assert(
		implemented_count == 11,
		"implemented_playable set must be exactly 11"
	)
	# Reference/planned maps are NOT formally playable.
	var non_playable: Array = []
	for map_id: int in WorldContent.maps.keys():
		if map_id in RUNTIME_MAP_IDS:
			continue
		if Bridge.is_formal_playable(map_id):
			non_playable.append(map_id)
			continue
		var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		assert(
			not bool(profile.get("success", true)),
			"reference map %d must not resolve a formal profile" % map_id
		)
		assert(
			str(profile.get("reason", ""))
			== str(GroundUnit.REASON_MAP_NOT_IMPLEMENTED),
			"reference map %d must use map_not_implemented" % map_id
		)
	assert(
		non_playable.is_empty(),
		"no WorldContent-only map may be formally playable; %s" % str(non_playable)
	)
	# Special maps.
	for map_id: int in [248, 338, 401, 478]:
		assert(
			not Bridge.is_formal_playable(map_id),
			"map %d must be formal_playable=false without a runtime" % map_id
		)
	# Unknown map fails closed.
	var unknown: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
		9999
	)
	assert(
		not bool(unknown.get("success", true))
		and str(unknown.get("reason", ""))
			== str(GroundUnit.REASON_UNSUPPORTED_MAP_PROJECTION),
		"unknown map 9999 must be unsupported_map_projection"
	)
	await get_tree().process_frame
	print(
		"FORMAL_MAP_PROJECTION_COVERAGE_PASS implemented=%d unresolved=0 reference_not_playable=%d"
		% [implemented_count, WorldContent.maps.size() - implemented_count]
	)
	get_tree().quit(0)
