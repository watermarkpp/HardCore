extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 338

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Reference data exists but no runtime build.
	assert(WorldContent.has_map(MAP_ID), "map 338 must exist in reference data")
	assert(
		not Bridge.is_runtime_built(MAP_ID),
		"map 338 must NOT be runtime-built"
	)
	assert(
		not Bridge.is_formal_playable(MAP_ID),
		"map 338 must NOT be formally playable"
	)
	var state: Dictionary = Bridge.implementation_state(MAP_ID)
	assert(
		str(state.get("state", ""))
		== str(Bridge.IMPLEMENTATION_STATE_PLANNED_UNBUILT),
		"map 338 must be planned_unbuilt"
	)
	var profile: Dictionary = Mapper.resolve_formal_runtime_projection_profile(
		MAP_ID
	)
	assert(
		not bool(profile.get("success", true)),
		"map 338 formal projection must fail"
	)
	assert(
		str(profile.get("reason", ""))
		== str(GroundUnit.REASON_MAP_NOT_IMPLEMENTED),
		"map 338 formal projection must use map_not_implemented"
	)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	for _wait in range(600):
		if (
			bool(_game.gameplay_input_is_enabled())
			and not bool(_game.get("_world_bootstrap_in_progress"))
		):
			break
		await get_tree().process_frame
	await get_tree().process_frame
	_game.current_map_id = MAP_ID
	_game.current_zone = "毒蛇山谷"
	var ready_before := int(_game.missing_projection_rejection_count)
	assert(
		not bool(_game._check_world_ready_contract()),
		"World READY must be false on unbuilt map 338"
	)
	assert(
		int(_game.missing_projection_rejection_count) > ready_before,
		"unbuilt READY gate must record the rejection"
	)
	var enemy: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(92),
		Vector2(-390.0, -200.0),
		false
	)
	assert(
		enemy == null,
		"formal actor spawn must be zero on unbuilt map 338"
	)
	var traveled: bool = _game._request_map_travel(MAP_ID)
	assert(not traveled, "map travel into unbuilt 338 must be refused")
	assert(
		int(_game.current_map_id) == MAP_ID,
		"refused travel must not switch the current map"
	)
	# Reference data fully preserved.
	assert(
		WorldContent.map_content(MAP_ID).get("spawns", []).size() == 6,
		"map 338 reference spawn data must be preserved"
	)
	_game.queue_free()
	await get_tree().process_frame
	print("UNBUILT_PLANNED_MAP_NOT_PLAYABLE_PASS map=338")
	get_tree().quit(0)
