class_name WorldBootstrapCoordinator
extends RefCounted

# --- P1-B: Staged World Bootstrap Coordinator ---

enum Stage {
	IDLE,
	SHOW_LOADING,
	COLLECT_REQUIREMENTS,
	REQUEST_RESOURCES,
	WAIT_RESOURCES,
	BUILD_MAP,
	BUILD_COLLISION,
	SPAWN_ACTORS,
	FINALIZE,
	READY,
	FAILED,
}

var stage := Stage.IDLE
var generation := 0
var map_id := -1
var mode := ""
var started_at_usec := 0
var diagnostic: Dictionary = {}
var actor_plan: Array[Dictionary] = []
var resource_manifest: Dictionary = {}


func begin_initial_world(map_id_value: int) -> void:
	_internal_begin(map_id_value, "initial_world")


func begin_map_transition(map_id_value: int) -> void:
	_internal_begin(map_id_value, "map_transition")


func _internal_begin(_map_id: int, _mode: String) -> void:
	generation += 1
	map_id = _map_id
	mode = _mode
	stage = Stage.IDLE
	started_at_usec = Time.get_ticks_usec()
	actor_plan.clear()
	resource_manifest.clear()
	diagnostic = _empty_diagnostic()


func _empty_diagnostic() -> Dictionary:
	return {
		"map_id": -1,
		"mode": "",
		"stage": "",
		"success": true,
		"planned_actors": 0,
		"spawned_actors": 0,
		"failed_actors": 0,
		"total_duration_ms": 0,
		"frame_slice_count": 0,
		"sync_load_count": 0,
	}


func mark_heavy_work_started(gen: int) -> bool:
	return gen == generation


func advance(new_stage: Stage) -> void:
	stage = new_stage
	diagnostic["stage"] = Stage.keys()[new_stage]


func finish(success: bool, reason: String) -> Dictionary:
	if success:
		stage = Stage.READY
	else:
		stage = Stage.FAILED
	diagnostic["success"] = success
	diagnostic["failure_reason"] = reason
	diagnostic["total_duration_ms"] = (Time.get_ticks_usec() - started_at_usec) / 1000.0
	return snapshot()


func snapshot() -> Dictionary:
	var d := diagnostic.duplicate(true)
	d["stage"] = Stage.keys()[stage]
	d["generation"] = generation
	return d
