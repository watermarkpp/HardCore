extends Node

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const PHONE_REPRODUCTIONS := [
	{
		"map_id": 4,
		"position": Vector2(-1296.47412109375, -631.391357421875),
		"label": "bich",
	},
	{
		"map_id": 268,
		"position": Vector2(-1535.923828125, -127.666328430176),
		"label": "wooma_forest",
	},
]


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	PlayerState.active_profile_id = "test.boundary.phone.reproduction"
	for reproduction: Dictionary in PHONE_REPRODUCTIONS:
		var map_id := int(reproduction.map_id)
		var phone_position: Vector2 = reproduction.position
		var label := str(reproduction.label)
		game.current_map_id = map_id
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		var raw_size: Array = runtime.design.design_size
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		game.player.global_position = phone_position
		PlayerState.update_world_location(map_id, phone_position)
		assert(
			not CollisionGeometry.player_foot_inside_boundary(
				game.player.global_position, design_size
			),
			"%s phone coordinate did not reproduce the black-area overlap"
				% label
		)
		assert(
			game._constrain_player_foot_to_runtime_ground(),
			"%s phone coordinate was not repaired" % label
		)
		assert(
			CollisionGeometry.player_foot_inside_boundary(
				game.player.global_position, design_size
			),
			"%s complete foot ellipse remains outside visible ground" % label
		)
		assert(
			game.player.global_position.distance_to(phone_position) < 32.0,
			"%s correction moved farther than one foot diameter" % label
		)
		assert(
			PlayerState.saved_map_id == map_id
				and PlayerState.saved_position.is_equal_approx(
					game.player.global_position
				),
			"%s persisted coordinate differs from the repaired world coordinate"
				% label
		)
		var stable_position: Vector2 = game.player.global_position
		assert(
			not game._constrain_player_foot_to_runtime_ground(),
			"%s legal coordinate was corrected a second time" % label
		)
		assert(
			game.player.global_position == stable_position,
			"%s legal coordinate drifted under repeated projection" % label
		)
		print(
			"PHONE_BOUNDARY_REPRO_PASS map=%s before=%s after=%s"
			% [label, phone_position, stable_position]
		)
	PlayerState.active_profile_id = ""
	print(
		"GAME_ROOT_PLAYER_FOOT_BOUNDARY_PASS contract=%s"
		% CollisionGeometry.PLAYER_FOOT_BOUNDARY_CONTRACT_ID
	)
	get_tree().quit(0)
