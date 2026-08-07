extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 248

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Reference resolver keeps the legacy source-absolute math for migration /
	# import audits / test-dev preview.
	var reference: Dictionary = Mapper.resolve_reference_projection_profile(
		MAP_ID
	)
	assert(
		bool(reference.get("success", false)),
		"map 248 reference projection must succeed"
	)
	assert(
		str(reference.get("policy", ""))
		== str(Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE),
		"map 248 reference policy must be authored_source_absolute"
	)
	var screen_to_ground: Callable = reference.get("screen_to_ground", Callable())
	var ground: Vector2 = screen_to_ground.call(Vector2(448.0, -3760.0))
	assert(
		ground.distance_to(Vector2(89.0, 75.0)) <= 0.01,
		"map 248 reference math must still resolve (89,75)"
	)
	# Formal GameRoot path must NEVER use the reference projection for 248.
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_game.current_map_id = MAP_ID
	var result: Dictionary = _game._try_canonical_screen_px_to_ground_gu(
		Vector2(448.0, -3760.0)
	)
	assert(
		not bool(result.get("success", true)),
		"formal GameRoot conversion must reject reference map 248"
	)
	assert(
		str(result.get("reason", ""))
		== str(GroundUnit.REASON_MAP_NOT_IMPLEMENTED),
		"formal GameRoot rejection must use map_not_implemented"
	)
	var raw: Vector2 = _game._canonical_screen_px_to_ground_gu(
		Vector2(448.0, -3760.0)
	)
	assert(
		not raw.is_finite(),
		"formal GameRoot must never return the reference ground for 248"
	)
	_game.queue_free()
	await get_tree().process_frame
	print("LEGACY_REFERENCE_PROJECTION_ISOLATION_PASS map=248")
	get_tree().quit(0)
