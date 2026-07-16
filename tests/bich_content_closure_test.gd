extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const BICH_MAPS := [4, 217, 218, 221, 248, 249, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 1578]


func _ready() -> void:
	var portal_edges := {}
	for map_id: int in BICH_MAPS:
		var content := RegionContent.get_map_content(map_id)
		var source_size: Vector2i = content.get("source_size", Vector2i.ZERO)
		assert(content.get("status", "") == "client_map_full_size" and source_size.x > 0 and source_size.y > 0, "地图%d未进入原尺寸运行体系" % map_id)
		var actor_coordinates := {}
		for group_name: String in ["spawns", "bosses", "npcs"]:
			for entry: Dictionary in content.get(group_name, []):
				var source: Vector2i = entry.get("source_coordinate", Vector2i(-1, -1))
				assert(Mapper.contains_source(Vector2(source), source_size), "地图%d的%s源坐标越界" % [map_id, group_name])
				assert(entry.position.is_equal_approx(Mapper.source_to_world(Vector2(source), source_size)), "地图%d的%s运行映射错误" % [map_id, group_name])
				var key := "%d,%d" % [source.x, source.y]
				assert(not actor_coordinates.has(key), "地图%d存在重叠出生坐标%s" % [map_id, key])
				actor_coordinates[key] = true
		for portal: Dictionary in content.get("portals", []):
			var target := int(portal.get("target_map_id", -1))
			var source: Vector2i = portal.get("source_coordinate", Vector2i(-1, -1))
			assert(Mapper.contains_source(Vector2(source), source_size), "地图%d门点源坐标越界" % map_id)
			assert(portal.get("source_confidence", "") in ["A", "B", "C"], "地图%d门点缺少可信度" % map_id)
			portal_edges["%d>%d" % [map_id, target]] = true
	for edge: String in portal_edges:
		var parts := edge.split(">")
		var source_map := int(parts[0])
		var target_map := int(parts[1])
		if target_map in BICH_MAPS:
			assert(portal_edges.has("%d>%d" % [target_map, source_map]), "比奇内部门点缺少反向连接：%s" % edge)
	print("BICH_CONTENT_CLOSURE_PASS：19图原尺寸、刷新不重叠、门点可信度与内部双向闭环正常")
	get_tree().quit(0)
