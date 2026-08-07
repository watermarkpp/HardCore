extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const EXPECTED_11 := [4, 217, 218, 221, 268, 313, 314, 315, 406, 408, 1578]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Bridge.reset_release_registry_override()
	var released: Array[int] = Bridge.released_map_ids()
	assert(
		released == EXPECTED_11,
		"current released map ids must be exactly the 11; got %s" % str(released)
	)
	for map_id: int in released:
		assert(
			Bridge.runtime_artifact_exists(map_id),
			"map %d runtime artifact must exist" % map_id
		)
		assert(
			Bridge.has_runtime_map(map_id),
			"map %d must be formally playable (approved release)" % map_id
		)
		assert(
			str(Bridge.release_rejection_reason(map_id)) == "",
			"map %d must have no rejection reason" % map_id
		)
		var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		assert(
			bool(profile.get("success", false)),
			"map %d formal profile must be ready" % map_id
		)
	for map_id: int in [338, 478, 248, 401]:
		assert(
			not Bridge.is_formal_playable(map_id),
			"unbuilt map %d must remain formal_playable=false" % map_id
		)
	await get_tree().process_frame
	print(
		"RELEASE_REGISTRY_CURRENT_MAPS_PASS released=%d 11/11 valid+approved+key-match+profile-ready"
		% released.size()
	)
	get_tree().quit(0)
