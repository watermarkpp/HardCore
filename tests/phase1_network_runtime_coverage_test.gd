extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var runtime_map_ids := Bridge.released_map_ids()
	assert(runtime_map_ids.size() == 67, "formal runtime-ready set must be exactly 67 maps")
	var unresolved: Array = []
	for map_id: int in runtime_map_ids:
		assert(
			Bridge.is_runtime_built(map_id),
			"phase1 map %d must be runtime-built" % map_id
		)
		var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		if not bool(profile.get("success", false)):
			unresolved.append(map_id)
	assert(
		unresolved.is_empty(),
		"every phase1 runtime map must have a formal projection; unresolved=%s"
		% str(unresolved)
	)
	await get_tree().process_frame
	print(
		"PHASE1_NETWORK_RUNTIME_COVERAGE_PASS count=%d unresolved=0"
		% runtime_map_ids.size()
	)
	get_tree().quit(0)
