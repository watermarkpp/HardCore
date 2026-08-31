extends Node

const GeometryService := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const RuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const MAP_IDS := [911001, 911002, 911003]


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
		var sprites_by_index: Dictionary = {}
		for child: Node in game.background.get_children():
			if child is Sprite2D and bool(child.get_meta("editor_runtime_instance", false)):
				sprites_by_index[int(child.get_meta("editor_runtime_command_index", -1))] = child
		for child: Node in game.get_children():
			if not bool(child.get_meta("editor_runtime_actor_occluder", false)):
				continue
			for nested: Node in child.get_children():
				if nested is Sprite2D and bool(nested.get_meta("editor_runtime_instance", false)):
					sprites_by_index[int(nested.get_meta("editor_runtime_command_index", -1))] = nested
		assert(
			sprites_by_index.size() == commands.size(),
			"map %d runtime flattened/dropped draw commands: %d/%d"
				% [map_id, sprites_by_index.size(), commands.size()]
		)
		for index in commands.size():
			var command: Dictionary = commands[index]
			assert(sprites_by_index.has(index), "missing command %d" % index)
			var sprite: Sprite2D = sprites_by_index[index]
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
			assert(sprite.global_position.is_equal_approx(geometry.center))
			assert(sprite.offset.is_equal_approx(-geometry.anchor))
			assert(sprite.scale.is_equal_approx(geometry.visual_scale))
			assert(is_equal_approx(sprite.rotation, float(geometry.rotation)))
			verified_commands += 1
		assert(not game.background.uses_editor_runtime_fallback_ground())
	print(
		"ORC_TOMB_GAME_VISUAL_GEOMETRY_PASS "
		+ "contract=%s maps=911001,911002,911003 commands=%d legacy_fallback=false"
		% [GeometryService.VISUAL_GEOMETRY_CONTRACT_ID, verified_commands]
	)
	get_tree().quit(0)
