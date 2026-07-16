extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")


func _ready() -> void:
	var size := Vector2i(700, 700)
	var home := Vector2(289, 618)
	var world_home := Mapper.source_to_world(home, size)
	assert(world_home == Vector2(-10528, 3328), "服务端出生点映射错误")
	assert(Mapper.world_to_source(world_home, size).is_equal_approx(home), "出生点反向映射错误")
	assert(Mapper.world_bounds(size) == Rect2(-22368, -11184, 44736, 22368), "完整地图世界边界错误")
	var corners := Mapper.world_corners(size)
	assert(corners == PackedVector2Array([Vector2(0, -11184), Vector2(22368, 0), Vector2(0, 11184), Vector2(-22368, 0)]), "700×700四角映射错误")
	var content := RegionContent.get_map_content(4)
	assert(content.get("status", "") == "client_map_full_size", "运行地图仍是压缩切片")
	for group_name: String in ["spawns", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			var source: Vector2 = entry.get("source_coordinate", Vector2(-1, -1))
			assert(Mapper.contains_source(source, size), "%s源坐标越界" % group_name)
			assert(entry.get("position", Vector2.INF).is_equal_approx(Mapper.source_to_world(source, size)), "%s没有使用统一坐标映射" % group_name)
	for map_id: int in [217, 218, 221, 248, 249]:
		var map_content := RegionContent.get_map_content(map_id)
		assert(Vector2i(map_content.get("source_size", Vector2i.ZERO)) == Vector2i(400, 400) and map_content.get("status", "") == "client_map_full_size", "地图%d没有恢复400×400原尺寸" % map_id)
		for group_name: String in ["spawns", "bosses", "portals"]:
			for entry: Dictionary in map_content.get(group_name, []):
				var source: Vector2 = entry.get("source_coordinate", Vector2(-1, -1))
				assert(Mapper.contains_source(source, Vector2i(400, 400)), "地图%d的%s源坐标越界" % [map_id, group_name])
				assert(entry.position.is_equal_approx(Mapper.source_to_world(source, Vector2i(400, 400))), "地图%d的%s未统一映射" % [map_id, group_name])
	var mine_sizes := {401: 200, 402: 100, 403: 100, 404: 200, 405: 100, 406: 200, 407: 100, 408: 200, 409: 100, 410: 200, 411: 100, 412: 200, 1578: 30}
	for map_id: int in mine_sizes:
		var side: int = mine_sizes[map_id]
		var source_size := Vector2i(side, side)
		var map_content := RegionContent.get_map_content(map_id)
		assert(Vector2i(map_content.get("source_size", Vector2i.ZERO)) == source_size and map_content.get("status", "") == "client_map_full_size", "矿区地图%d没有恢复原尺寸" % map_id)
		for group_name: String in ["spawns", "bosses", "portals"]:
			for entry: Dictionary in map_content.get(group_name, []):
				var source: Vector2 = entry.get("source_coordinate", Vector2(-1, -1))
				assert(entry.get("source_confidence", "") == "C" and Mapper.contains_source(source, source_size), "矿区地图%d的%s候选坐标错误" % [map_id, group_name])
				assert(entry.position.is_equal_approx(Mapper.source_to_world(source, source_size)), "矿区地图%d的%s未统一映射" % [map_id, group_name])
	print("MAP_COORDINATE_MAPPING_PASS：比奇地表、古墓、洞穴、12张矿区与Q004原尺寸和运行坐标一致")
	get_tree().quit(0)
