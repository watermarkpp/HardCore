extends Node

const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const VisualGeometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")


func _ready() -> void:
	var wall_fronts := 0
	var wall_backgrounds := 0
	for map_id: int in [217, 218, 221]:
		var runtime := RuntimeBridge.load_map(map_id)
		var raw_size: Array = runtime.design.design_size
		var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		for command: Dictionary in VisualGeometry.sorted_draw_commands(runtime.instances):
			if str(command.asset.get("asset_type", "")) != "wall_module":
				continue
			var image_pass := int(command.image_pass)
			var domain := str(command.render_domain)
			if image_pass == 2:
				wall_fronts += 1
				assert(domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
				var sort_world := VisualGeometry.command_actor_sort_world(command, size)
				assert(MapEditorCoordinate.world_to_cell(sort_world, size) == command.sort_tile)
			else:
				wall_backgrounds += 1
				assert(domain == VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND)
	assert(wall_fronts > 0 and wall_backgrounds > wall_fronts)
	print("MAP_RUNTIME_WALL_OCCLUSION_CONTRACT_PASS maps=217,218,221 fronts=%d backgrounds=%d" % [wall_fronts, wall_backgrounds])
	get_tree().quit(0)
