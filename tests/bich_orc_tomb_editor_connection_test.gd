extends Node


func _ready() -> void:
	var bich_result := MapEditorLoadService.load_document(
		"res://map_editor_workspace/bich_province/bich_province.editor.json"
	)
	var tomb_result := MapEditorLoadService.load_document(
		"res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
	)
	assert(bich_result.ok, str(bich_result.get("errors", [])))
	assert(tomb_result.ok, str(tomb_result.get("errors", [])))
	var bich: Dictionary = bich_result.document
	var tomb: Dictionary = tomb_result.document
	var doors: Array = bich.layers.door_points
	assert(doors.size() == 4)
	var east_door: Dictionary = doors[0]
	var east_score := _east_score(east_door)
	for door: Dictionary in doors.slice(1):
		var score := _east_score(door)
		if score > east_score:
			east_score = score
			east_door = door
	assert(str(east_door.semantic_id) == "door_000002")
	assert(Vector2i(int(east_door.tile[0]), int(east_door.tile[1])) == Vector2i(71, 2))

	var entrance: Dictionary = tomb.layers.map_entrance_points[0]
	assert(str(entrance.entrance_id) == "map_entrance_000001")
	assert(Vector2i(int(entrance.tile[0]), int(entrance.tile[1])) == Vector2i(3, 35))
	assert(bool(east_door.target_configured))
	assert(int(east_door.target_map_id) == 217)
	assert(str(east_door.target_map_key) == "orc_tomb_1")
	assert(str(east_door.target_entrance_id) == str(entrance.entrance_id))
	assert(
		Vector2i(int(east_door.target_tile[0]), int(east_door.target_tile[1]))
		== Vector2i(int(entrance.tile[0]), int(entrance.tile[1]))
	)

	var runtime_result := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(runtime_result.ok, str(runtime_result.get("errors", [])))
	var runtime_door: Dictionary = (
		runtime_result.runtime.semantics.door_points
		.filter(func(entry: Dictionary) -> bool: return str(entry.semantic_id) == str(east_door.semantic_id))
		[0]
	)
	assert(int(runtime_door.target_map_id) == 217)
	assert(str(runtime_door.target_entrance_id) == str(entrance.entrance_id))
	var game_portals: Array = MapEditorRuntimeBridge.game_content().get("portals", [])
	var tomb_portals := game_portals.filter(
		func(portal: Dictionary) -> bool: return int(portal.target_map_id) == 217
	)
	assert(tomb_portals.size() == 1)
	assert(
		(tomb_portals[0].position as Vector2).is_equal_approx(
			MapEditorRuntimeBridge.tile_to_world(runtime_result.runtime, east_door.tile)
		)
	)
	var marker_file := FileAccess.open(
		"res://assets/data/runtime/map_editor/bich_province.manual_ready.json",
		FileAccess.READ
	)
	assert(marker_file != null)
	var marker: Variant = JSON.parse_string(marker_file.get_as_text())
	assert(marker is Dictionary)
	assert(int(marker.content.doors_pending_target_configuration) == 3)
	assert(int(marker.content.configured_connections[0].target_map_id) == 217)
	print("BICH_ORC_TOMB_EDITOR_CONNECTION_PASS exit=71,2 entrance=3,35 target=217")
	get_tree().quit(0)


func _east_score(entry: Dictionary) -> int:
	var tile: Array = entry.get("tile", [0, 0])
	return int(tile[0]) - int(tile[1])
