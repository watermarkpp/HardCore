extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 478: reference data with authored centered positions, no runtime.
	assert(WorldContent.has_map(478), "map 478 must exist in reference data")
	assert(
		not Bridge.is_formal_playable(478),
		"map 478 must NOT be formally playable without a runtime"
	)
	var state: Dictionary = Bridge.implementation_state(478)
	assert(
		str(state.get("state", ""))
		== str(Bridge.IMPLEMENTATION_STATE_PLANNED_UNBUILT),
		"map 478 must be planned_unbuilt"
	)
	var formal: Dictionary = Mapper.resolve_formal_runtime_projection_profile(478)
	assert(
		not bool(formal.get("success", true)),
		"map 478 formal projection must fail"
	)
	var reference: Dictionary = Mapper.resolve_reference_projection_profile(478)
	assert(
		bool(reference.get("success", false)),
		"map 478 reference projection must succeed"
	)
	assert(
		str(reference.get("policy", ""))
		== str(Mapper.PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE),
		"map 478 reference policy must be authored_centered_absolute"
	)
	# 401: reference source-size math still available.
	var ref401: Dictionary = Mapper.resolve_reference_projection_profile(401)
	assert(
		bool(ref401.get("success", false))
		and str(ref401.get("policy", ""))
			== str(Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE),
		"map 401 reference policy must be authored_source_absolute"
	)
	assert(
		ref401.get("source_size", Vector2i.ZERO) == Vector2i(200, 200),
		"map 401 reference source_size must be 200x200"
	)
	# Formal GameRoot spawn refused on 478.
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_game.current_map_id = 478
	var enemy: EnemyActor = _game._spawn_enemy(
		GameData.get_monster_by_id(97),
		Vector2(-390.0, -200.0),
		false
	)
	assert(
		enemy == null,
		"formal actor spawn must be zero on reference map 478"
	)
	_game.queue_free()
	await get_tree().process_frame
	print("REFERENCE_MAP_NOT_PLAYABLE_PASS maps=478,401")
	get_tree().quit(0)
