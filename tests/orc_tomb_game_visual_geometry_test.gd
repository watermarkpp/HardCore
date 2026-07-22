extends Node

const GeometryService := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const RuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const MAP_IDS := [217, 218, 221]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var verified_commands := 0
	for map_id: int in MAP_IDS:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		var runtime := RuntimeBridge.load_map(map_id)
		var raw_size: Array = runtime.design.get("design_size", [0, 0])
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var commands := GeometryService.sorted_draw_commands(
			runtime.get("instances", [])
		)
		var sprites: Array[Sprite2D] = []
		for child: Node in game.background.get_children():
			if child is Sprite2D and bool(child.get_meta("editor_runtime_instance", false)):
				sprites.append(child)
		assert(
			sprites.size() == commands.size(),
			"map %d runtime flattened/dropped draw commands: %d/%d"
				% [map_id, sprites.size(), commands.size()]
		)
		for index in commands.size():
			var command: Dictionary = commands[index]
			var sprite := sprites[index]
			var image_path := str(command.image_path)
			var resource_path := (
				image_path
				if image_path.begins_with("res://")
				else "res://" + image_path
			)
			assert(sprite.texture != null, resource_path)
			assert(
				str(sprite.get_meta("editor_runtime_image_path", "")) == image_path,
				"map %d command order mismatch at %d" % [map_id, index]
			)
			var geometry := GeometryService.runtime_command_geometry(
				command, design_size, sprite.texture.get_size()
			)
			assert(sprite.position.is_equal_approx(geometry.center))
			assert(sprite.offset.is_equal_approx(-geometry.anchor))
			assert(sprite.scale.is_equal_approx(geometry.visual_scale))
			assert(is_equal_approx(sprite.rotation, float(geometry.rotation)))
			verified_commands += 1
		assert(not game.background.uses_editor_runtime_fallback_ground())
	print(
		"ORC_TOMB_GAME_VISUAL_GEOMETRY_PASS "
		+ "contract=%s maps=217,218,221 commands=%d legacy_fallback=false"
		% [GeometryService.VISUAL_GEOMETRY_CONTRACT_ID, verified_commands]
	)
	get_tree().quit(0)
