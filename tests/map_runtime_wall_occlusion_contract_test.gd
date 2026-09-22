extends Node

const VisualGeometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")

const ORC_RUNTIME_PATHS := {
	217: "res://assets/data/runtime/map_editor/orc_tomb_1.runtime.json",
	218: "res://assets/data/runtime/map_editor/orc_tomb_2.runtime.json",
	221: "res://assets/data/runtime/map_editor/orc_tomb_3.runtime.json",
}


func _ready() -> void:
	var wall_fronts := 0
	var wall_bases := 0
	var wall_shadows := 0
	for map_id: int in [217, 218, 221]:
		var loaded := MapEditorRuntimeMapService.load_runtime(
			str(ORC_RUNTIME_PATHS[map_id])
		)
		assert(loaded.ok, "orc runtime invalid: %d %s" % [map_id, loaded.errors])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.design.design_size
		var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		for command: Dictionary in VisualGeometry.sorted_draw_commands(runtime.instances):
			if str(command.asset.get("asset_type", "")) != "wall_module":
				continue
			var image_pass := int(command.image_pass)
			var domain := str(command.render_domain)
			if image_pass == 0:
				wall_shadows += 1
				assert(domain == VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND)
				assert(str(command.get("actor_sort_group", "")).is_empty())
			else:
				if image_pass == 2:
					wall_fronts += 1
				else:
					wall_bases += 1
				assert(image_pass in [1, 2])
				assert(domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
				assert(not str(command.get("actor_sort_group", "")).is_empty())
				var sort_world := VisualGeometry.command_actor_sort_world(command, size)
				assert(MapEditorCoordinate.screen_position_px_to_grid_cell(sort_world, size) == command.sort_tile)
	assert(wall_fronts > 0 and wall_bases > 0 and wall_shadows > 0)
	print("MAP_RUNTIME_WALL_OCCLUSION_CONTRACT_PASS maps=217,218,221 fronts=%d bases=%d shadows=%d" % [wall_fronts, wall_bases, wall_shadows])
	get_tree().quit(0)
