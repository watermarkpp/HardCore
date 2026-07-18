class_name MapEditorCollisionService
extends RefCounted


static func add_manual_shape(document: Dictionary, shape_type: String, data: Dictionary) -> Dictionary:
	if shape_type not in ["rect", "ellipse", "polygon"]:
		return {"ok": false, "errors": ["invalid_collision_shape"]}
	var errors := _validate_shape(shape_type, data)
	if not errors.is_empty(): return {"ok": false, "errors": errors}
	var entries: Array = document.layers.collision
	entries.append({"collision_id": _next_manual_collision_id(entries), "shape": shape_type, "data": data.duplicate(true), "source": "manual", "blocks_player": true, "blocks_monster": true, "content_layer": "personal_expansion"})
	document.layers.collision = entries
	return {"ok": true, "collision": entries.back()}


static func remove_manual_shape_at_tile(document: Dictionary, tile: Vector2i) -> Dictionary:
	var entries: Array = document.layers.collision
	for index in range(entries.size() - 1, -1, -1):
		var collision: Dictionary = entries[index]
		if _manual_contains_tile(collision, tile):
			entries.remove_at(index)
			document.layers.collision = entries
			return {"ok": true, "collision": collision}
	return {"ok": false, "errors": ["manual_collision_not_found_at_tile"]}


static func paint_collision_cell(document: Dictionary, tile: Vector2i) -> Dictionary:
	if not _tile_inside_map(document, tile):
		return {"ok": false, "errors": ["collision_tile_out_of_bounds"]}
	var erased_cells: Array = document.layers.get("collision_erase", [])
	var restored := false
	for index in range(erased_cells.size() - 1, -1, -1):
		var entry: Dictionary = erased_cells[index]
		if _entry_tile(entry) == tile:
			erased_cells.remove_at(index)
			restored = true
	document.layers["collision_erase"] = erased_cells
	var key := "%d,%d" % [tile.x, tile.y]
	if build_walkability(document).blocked_tiles.has(key):
		return {"ok": true, "created": false, "restored": restored, "tile": [tile.x, tile.y]}
	var added := add_manual_shape(document, "rect", {"rect": [tile.x, tile.y, 1, 1]})
	added["created"] = bool(added.get("ok", false))
	added["restored"] = restored
	added["tile"] = [tile.x, tile.y]
	return added


static func erase_collision_cell(document: Dictionary, tile: Vector2i) -> Dictionary:
	if not _tile_inside_map(document, tile):
		return {"ok": false, "errors": ["collision_tile_out_of_bounds"]}
	var key := "%d,%d" % [tile.x, tile.y]
	if not build_walkability(document).blocked_tiles.has(key):
		return {"ok": false, "errors": ["collision_not_found_at_tile"], "tile": [tile.x, tile.y]}
	var erased_cells: Array = document.layers.get("collision_erase", [])
	for entry: Dictionary in erased_cells:
		if _entry_tile(entry) == tile:
			return {"ok": true, "created": false, "tile": [tile.x, tile.y]}
	erased_cells.append({
		"tile": [tile.x, tile.y],
		"source": "single_cell_erase",
		"content_layer": "personal_expansion",
	})
	document.layers["collision_erase"] = erased_cells
	return {"ok": true, "created": true, "tile": [tile.x, tile.y]}


static func erase_collision_at_tile(document: Dictionary, tile: Vector2i) -> Dictionary:
	var removed_manual: Array[Dictionary] = []
	var manual_entries: Array = document.layers.collision
	for index in range(manual_entries.size() - 1, -1, -1):
		var manual: Dictionary = manual_entries[index]
		if _manual_contains_tile(manual, tile):
			removed_manual.append(manual)
			manual_entries.remove_at(index)
	document.layers.collision = manual_entries

	var disabled_instances: Array[String] = []
	var size: Array = document.design.design_size
	var map_size := Vector2i(int(size[0]), int(size[1]))
	var layers: Dictionary = document.layers
	for layer_name: String in layers:
		var entries: Array = layers[layer_name]
		for index in entries.size():
			var instance: Dictionary = entries[index]
			if not instance.has("instance_id") or not _instance_collision_contains_tile(instance, tile, map_size):
				continue
			disabled_instances.append(str(instance.instance_id))
			instance["collision_policy"] = "none"
			instance["collision_profile_id"] = "none_visual"
			instance["collision_footprint_tiles"] = [0, 0]
			instance["collision_cells"] = []
			instance["navigation_policy"] = "ignore"
			instance["map_collision_override"] = "disabled"
			entries[index] = instance
		layers[layer_name] = entries
	document.layers = layers

	if removed_manual.is_empty() and disabled_instances.is_empty():
		return {"ok": false, "errors": ["collision_not_found_at_tile"], "manual_count": 0, "instance_count": 0}
	return {
		"ok": true,
		"manual_collisions": removed_manual,
		"disabled_instance_ids": disabled_instances,
		"manual_count": removed_manual.size(),
		"instance_count": disabled_instances.size(),
	}


static func _instance_collision_contains_tile(instance: Dictionary, tile: Vector2i, map_size: Vector2i) -> bool:
	var policy := str(instance.get("collision_policy", "none"))
	if policy == "none":
		return false
	if policy == "wall_cells_generated" and not (instance.get("collision_cells", []) as Array).is_empty():
		var blocked := {}
		_mark_scaled_collision_cells(blocked, instance, map_size)
		return blocked.has("%d,%d" % [tile.x, tile.y])
	var collision_size := _collision_footprint(instance)
	if collision_size.x <= 0 or collision_size.y <= 0:
		return false
	var origin := _collision_origin(instance)
	return tile.x >= origin.x and tile.y >= origin.y and tile.x < origin.x + collision_size.x and tile.y < origin.y + collision_size.y


static func _next_manual_collision_id(entries: Array) -> String:
	var maximum := 0
	for entry: Dictionary in entries:
		maximum = maxi(maximum, str(entry.get("collision_id", "")).trim_prefix("manual_").to_int())
	return "manual_%06d" % (maximum + 1)


static func _manual_contains_tile(manual: Dictionary, tile: Vector2i) -> bool:
	var shape := str(manual.get("shape", ""))
	var data: Dictionary = manual.get("data", {})
	if shape in ["rect", "ellipse"]:
		var rect: Array = data.get("rect", [])
		if rect.size() != 4:
			return false
		if shape == "rect":
			return tile.x >= int(rect[0]) and tile.y >= int(rect[1]) and tile.x < int(rect[0]) + int(rect[2]) and tile.y < int(rect[1]) + int(rect[3])
		var center := Vector2(float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3]) * 0.5)
		var point := Vector2(tile) + Vector2(0.5, 0.5)
		var normalized := Vector2(
			(point.x - center.x) / (float(rect[2]) * 0.5),
			(point.y - center.y) / (float(rect[3]) * 0.5)
		)
		return normalized.length_squared() <= 1.0
	if shape == "polygon":
		var points := PackedVector2Array()
		for raw_point: Array in data.get("points", []):
			if raw_point.size() == 2:
				points.append(Vector2(int(raw_point[0]), int(raw_point[1])))
		return points.size() >= 3 and Geometry2D.is_point_in_polygon(Vector2(tile) + Vector2(0.5, 0.5), points)
	return false


static func build_walkability(document: Dictionary) -> Dictionary:
	var size: Array = document.design.design_size
	var map_size := Vector2i(int(size[0]), int(size[1]))
	var blocked := {}
	var sources: Array = []
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var policy := str(instance.get("collision_policy", "none"))
		if policy == "none": continue
		if policy == "wall_cells_generated" and not (instance.get("collision_cells", []) as Array).is_empty():
			_mark_scaled_collision_cells(blocked, instance, map_size)
			sources.append({"source":"instance","id":instance.instance_id,"policy":policy,"shape":"explicit_cells"})
			continue
		var collision_size:=_collision_footprint(instance)
		if collision_size.x<=0 or collision_size.y<=0:continue
		var collision_origin := _collision_origin(instance)
		_mark_rect(blocked, collision_origin, collision_size, map_size)
		sources.append({"source":"instance","id":instance.instance_id,"policy":policy})
	for manual: Dictionary in document.layers.collision:
		_mark_manual(blocked, manual, map_size)
		sources.append({"source":"manual","id":manual.collision_id,"shape":manual.shape})
	var erased_tiles: Array[String] = []
	for entry: Dictionary in document.layers.get("collision_erase", []):
		var erased_tile := _entry_tile(entry)
		if erased_tile.x < 0 or erased_tile.y < 0 or erased_tile.x >= map_size.x or erased_tile.y >= map_size.y:
			continue
		var key := "%d,%d" % [erased_tile.x, erased_tile.y]
		blocked.erase(key)
		erased_tiles.append(key)
	return {"map_size":[map_size.x,map_size.y],"blocked_tiles":blocked,"blocked_count":blocked.size(),"walkable_count":map_size.x*map_size.y-blocked.size(),"sources":sources,"erased_tiles":erased_tiles}


static func _entry_tile(entry: Dictionary) -> Vector2i:
	var raw: Array = entry.get("tile", [-1, -1])
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(raw[0]), int(raw[1]))


static func _tile_inside_map(document: Dictionary, tile: Vector2i) -> bool:
	var raw_size: Array = document.design.design_size
	return tile.x >= 0 and tile.y >= 0 and tile.x < int(raw_size[0]) and tile.y < int(raw_size[1])


static func _mark_scaled_collision_cells(blocked: Dictionary, instance: Dictionary, map_size: Vector2i) -> void:
	var origin := _tile(instance)
	var current := _footprint(instance)
	var raw_base: Array = instance.get("instance_base_footprint_tiles", instance.get("base_footprint_tiles", instance.get("footprint_tiles", [1, 1])))
	var base := Vector2i(maxi(1, int(raw_base[0])), maxi(1, int(raw_base[1])))
	var source_cells := {}
	for raw_cell: Variant in instance.get("collision_cells", []):
		if raw_cell is Array and raw_cell.size() == 2:
			source_cells["%d,%d" % [int(raw_cell[0]), int(raw_cell[1])]] = true
	for y in current.y:
		for x in current.x:
			var source_x := clampi(floori((float(x) + 0.5) * float(base.x) / float(current.x)), 0, base.x - 1)
			var source_y := clampi(floori((float(y) + 0.5) * float(base.y) / float(current.y)), 0, base.y - 1)
			if source_cells.has("%d,%d" % [source_x, source_y]):
				var tile := origin + Vector2i(x, y)
				if tile.x >= 0 and tile.y >= 0 and tile.x < map_size.x and tile.y < map_size.y:
					blocked["%d,%d" % [tile.x, tile.y]] = true


static func _validate_shape(shape_type: String, data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if shape_type in ["rect", "ellipse"]:
		var rect: Array = data.get("rect", [])
		if rect.size()!=4 or int(rect[2])<=0 or int(rect[3])<=0: errors.append("invalid_rect")
	if shape_type == "polygon":
		var points: Array = data.get("points", [])
		if points.size()<3: errors.append("polygon_requires_three_points")
	return errors


static func _tile(instance: Dictionary) -> Vector2i:
	var tile: Array=instance.get("tile",[0,0]); return Vector2i(int(tile[0]),int(tile[1]))


static func _footprint(instance: Dictionary) -> Vector2i:
	var value: Array=instance.get("footprint_tiles",[1,1]); return Vector2i(int(value[0]),int(value[1]))


static func _collision_footprint(instance:Dictionary)->Vector2i:
	var value:Array=instance.get("collision_footprint_tiles",instance.get("footprint_tiles",[1,1])); return Vector2i(int(value[0]),int(value[1]))


static func _collision_origin(instance: Dictionary) -> Vector2i:
	var visual_size := _footprint(instance)
	var collision_size := _collision_footprint(instance)
	# First centre a smaller collider inside its logical visual footprint.
	var centred := _tile(instance) + Vector2i(
		maxi(0, (visual_size.x - collision_size.x) / 2),
		maxi(0, (visual_size.y - collision_size.y) / 2)
	)
	# In an isometric grid the placement anchor is the sprite's ground-contact
	# point. A diamond centred on that point extends half of itself below the
	# sprite, which is the ~50% downward error visible in Walkable Preview.
	# Moving equally in -X/-Y raises it on screen without changing its shape.
	var lift_tiles := maxi(1, roundi(float(collision_size.x + collision_size.y) / 4.0))
	return centred - Vector2i(lift_tiles, lift_tiles)


static func _mark_rect(blocked: Dictionary, position: Vector2i, extent: Vector2i, map_size: Vector2i) -> void:
	for y in range(position.y,position.y+extent.y):
		for x in range(position.x,position.x+extent.x):
			if x>=0 and y>=0 and x<map_size.x and y<map_size.y: blocked["%d,%d"%[x,y]]=true


static func _mark_manual(blocked: Dictionary, manual: Dictionary, map_size: Vector2i) -> void:
	var shape:=str(manual.shape); var data:Dictionary=manual.data
	if shape=="rect":
		var r:Array=data.rect; _mark_rect(blocked,Vector2i(int(r[0]),int(r[1])),Vector2i(int(r[2]),int(r[3])),map_size); return
	if shape=="ellipse":
		var e:Array=data.rect; var center:=Vector2(float(e[0])+float(e[2])*0.5,float(e[1])+float(e[3])*0.5)
		for y in range(int(e[1]),int(e[1])+int(e[3])):
			for x in range(int(e[0]),int(e[0])+int(e[2])):
				var p:=Vector2(x+0.5,y+0.5); var q:=Vector2((p.x-center.x)/(float(e[2])*0.5),(p.y-center.y)/(float(e[3])*0.5))
				if q.length_squared()<=1.0 and x>=0 and y>=0 and x<map_size.x and y<map_size.y: blocked["%d,%d"%[x,y]]=true
	if shape=="polygon":
		var points := PackedVector2Array()
		for point: Array in data.points:
			points.append(Vector2(int(point[0]), int(point[1])))
		for y in map_size.y:
			for x in map_size.x:
				if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),points): blocked["%d,%d"%[x,y]]=true
